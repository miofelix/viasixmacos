import Darwin
import Foundation

public typealias MihomoEventHandler = @Sendable (MihomoEvent) async -> Void
public typealias MihomoPortProbe = @Sendable (_ host: String, _ port: UInt16) async -> Bool

public enum MihomoState: Equatable, Sendable {
    case stopped
    case validating
    case starting
    case running(pid: Int32)
    case stopping
}

public enum MihomoEvent: Equatable, Sendable {
    case stateChanged(MihomoState)
    case log(String)
    case unexpectedExit(status: Int32, output: String)
}

public enum MihomoControllerError: Error, Equatable, LocalizedError, Sendable {
    case alreadyRunning
    case executableNotFound(String)
    case executableNotExecutable(String)
    case configNotFound(String)
    case configNotReadable(String)
    case homeNotFound(String)
    case homeIsSymbolicLink(String)
    case homeNotDirectory(String)
    case homeNotWritable(String)
    case launchFailed(path: String, reason: String)
    case validationFailed(status: Int32, output: String)
    case versionFailed(status: Int32, output: String)
    case outputReadFailed(String)
    case portInUse(host: String, port: UInt16)
    case validationTimedOut
    case versionTimedOut
    case exitedBeforeReady(status: Int32, output: String)
    case startupTimedOut(host: String, port: UInt16)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            "Mihomo 已在运行或正在启动。"
        case .executableNotFound(let path):
            "未找到 Mihomo 可执行文件：\(path)"
        case .executableNotExecutable(let path):
            "Mihomo 文件不可执行：\(path)"
        case .configNotFound(let path):
            "未找到 Mihomo 配置文件：\(path)"
        case .configNotReadable(let path):
            "Mihomo 配置文件不可读取：\(path)"
        case .homeNotFound(let path):
            "未找到 Mihomo 数据目录：\(path)"
        case .homeIsSymbolicLink(let path):
            "Mihomo 数据目录不能是符号链接：\(path)"
        case .homeNotDirectory(let path):
            "Mihomo 数据目录不是目录：\(path)"
        case .homeNotWritable(let path):
            "Mihomo 数据目录不可写：\(path)"
        case .launchFailed(let path, let reason):
            "无法启动 Mihomo \(path)：\(reason)"
        case .validationFailed(let status, let output):
            output.isEmpty
                ? "Mihomo 配置校验失败（状态码 \(status)）。"
                : "Mihomo 配置校验失败（状态码 \(status)）：\(output)"
        case .versionFailed(let status, let output):
            output.isEmpty
                ? "无法读取 Mihomo 版本（状态码 \(status)）。"
                : "无法读取 Mihomo 版本（状态码 \(status)）：\(output)"
        case .outputReadFailed(let reason):
            "读取 Mihomo 输出失败：\(reason)"
        case .portInUse(let host, let port):
            "本地代理端口已被占用：\(host):\(port)"
        case .validationTimedOut:
            "Mihomo 配置校验超时，已停止校验进程。"
        case .versionTimedOut:
            "读取 Mihomo 版本超时，已停止版本检查进程。"
        case .exitedBeforeReady(let status, let output):
            output.isEmpty
                ? "Mihomo 在代理端口就绪前退出（状态码 \(status)）。"
                : "Mihomo 在代理端口就绪前退出（状态码 \(status)）：\(output)"
        case .startupTimedOut(let host, let port):
            "等待 Mihomo 监听 \(host):\(port) 超时。"
        case .cancelled:
            "Mihomo 启动已取消。"
        }
    }
}

/// Owns the complete lifetime of one supervised Mihomo runtime and its process group.
///
/// Validation and runtime output merge stdout and stderr into one ordered log
/// stream. Only the process group spawned by this controller is ever signalled.
public actor MihomoController {
    public let executableURL: URL
    public let configURL: URL
    public let homeURL: URL
    public let host: String
    public let port: UInt16

    public private(set) var state: MihomoState = .stopped

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    private let environment: [String: String]
    private let validationTimeout: Duration
    private let startupTimeout: Duration
    private let readinessStability: Duration
    private let probeInterval: Duration
    private let stopTimeout: Duration
    private let portProbe: MihomoPortProbe

    private var operationID: UUID?
    private var cancellationRequested = false
    private var eventHandler: MihomoEventHandler?
    private var activeProcess: ManagedMihomoProcess?
    private var terminationTask: (pid: pid_t, task: Task<SupervisedProcessTermination, Never>)?

    deinit {
        guard let process = activeProcess, process.processGroup > 1 else { return }
        process.lifetime.close()
        _ = Darwin.kill(-process.processGroup, SIGKILL)
    }

    public init(
        executableURL: URL,
        configURL: URL,
        homeURL: URL,
        environment: [String: String] = [:],
        host: String = "127.0.0.1",
        port: UInt16 = 11_451,
        validationTimeout: Duration = .seconds(3),
        startupTimeout: Duration = .seconds(5),
        readinessStability: Duration = .milliseconds(100),
        probeInterval: Duration = .milliseconds(50),
        stopTimeout: Duration = .seconds(2),
        portProbe: MihomoPortProbe? = nil
    ) {
        self.executableURL = executableURL.standardizedFileURL
        self.configURL = configURL.standardizedFileURL
        self.homeURL = homeURL.standardizedFileURL
        self.environment = environment
        self.host = host
        self.port = port
        self.validationTimeout = validationTimeout
        self.startupTimeout = startupTimeout
        self.readinessStability = readinessStability
        self.probeInterval = probeInterval
        self.stopTimeout = stopTimeout
        self.portProbe =
            portProbe ?? { host, port in
                Self.probeTCPPort(host: host, port: port)
            }
    }

    /// Returns the complete output of `mihomo -v` after a bounded supervised run.
    public func version(timeout: Duration = .seconds(3)) async throws -> String {
        try validateExecutable()
        try validateHome()

        let result: SupervisedCommandResult
        do {
            result = try await SupervisedCommand.run(
                executableURL: executableURL,
                arguments: ["-v"],
                workingDirectoryURL: homeURL,
                environmentOverrides: environment,
                timeout: timeout
            )
        } catch SupervisedCommandError.timedOut {
            throw MihomoControllerError.versionTimedOut
        } catch is CancellationError {
            throw MihomoControllerError.cancelled
        } catch {
            throw MihomoControllerError.launchFailed(
                path: executableURL.path,
                reason: error.localizedDescription
            )
        }

        if let readError = result.outputReadError {
            throw MihomoControllerError.outputReadFailed(readError)
        }

        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.status == 0, !output.isEmpty else {
            throw MihomoControllerError.versionFailed(status: result.status, output: output)
        }
        return output
    }

    /// Validates the configuration, verifies the local port is free, starts
    /// Mihomo, and returns only after the port remains reachable long enough.
    public func start(
        onEvent: @escaping MihomoEventHandler = { _ in }
    ) async throws {
        guard operationID == nil, state == .stopped else {
            throw MihomoControllerError.alreadyRunning
        }

        let id = UUID()
        operationID = id
        cancellationRequested = false
        eventHandler = onEvent

        do {
            try await withTaskCancellationHandler {
                try await performStart(id: id, onEvent: onEvent)
            } onCancel: {
                Task.detached { await self.cancelOperation(id: id) }
            }
        } catch {
            let wasCancelled =
                Task.isCancelled
                || cancellationRequested
                || (error as? MihomoControllerError) == .cancelled
            await shutDownOperation(id: id, emitStopping: wasCancelled)
            if wasCancelled { throw MihomoControllerError.cancelled }
            throw error
        }
    }

    /// Stops only the process group created by this controller.
    public func stop() async {
        guard let id = operationID else { return }
        await cancelOperation(id: id)
    }

    public func restart(
        onEvent: @escaping MihomoEventHandler = { _ in }
    ) async throws {
        await stop()
        try await start(onEvent: onEvent)
    }

    private func performStart(
        id: UUID,
        onEvent: @escaping MihomoEventHandler
    ) async throws {
        try validateRuntimeFiles()
        try ensureActiveOperation(id)

        await transition(to: .validating, handler: onEvent)
        try ensureActiveOperation(id)

        let validation = try launch(
            arguments: ["-t", "-d", homeURL.path, "-f", configURL.path],
            onEvent: onEvent
        )
        activeProcess = validation

        let validationTermination = try await waitForValidationTermination(validation)
        SupervisedProcessControl.killRemainingGroupIfNeeded(validation.processGroup)
        let validationOutput = await validation.outputTask.value
        try ensureActiveOperation(id)
        activeProcess = nil

        if let readError = validationOutput.readError {
            throw MihomoControllerError.outputReadFailed(readError)
        }
        let cleanedValidationOutput = validationOutput.output.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard validationTermination.status == 0, !validationOutput.containsFatalDiagnostic else {
            throw MihomoControllerError.validationFailed(
                status: validationTermination.status,
                output: cleanedValidationOutput
            )
        }

        guard !(await portProbe(host, port)) else {
            try ensureActiveOperation(id)
            throw MihomoControllerError.portInUse(host: host, port: port)
        }
        try ensureActiveOperation(id)

        await transition(to: .starting, handler: onEvent)
        try ensureActiveOperation(id)

        let runtime = try launch(
            arguments: ["-d", homeURL.path, "-f", configURL.path],
            onEvent: onEvent
        )
        activeProcess = runtime

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: startupTimeout)
        var readinessDeadline: ContinuousClock.Instant?
        while true {
            try ensureActiveOperation(id)

            if let termination = runtime.terminationBox.value {
                try await throwEarlyExit(
                    runtime,
                    termination: termination,
                    operationID: id
                )
            }

            if await portProbe(host, port) {
                try ensureActiveOperation(id)
                if let termination = runtime.terminationBox.value {
                    try await throwEarlyExit(
                        runtime,
                        termination: termination,
                        operationID: id
                    )
                }

                if let readinessDeadline {
                    if clock.now >= readinessDeadline {
                        await transition(to: .running(pid: runtime.pid), handler: onEvent)
                        try ensureActiveOperation(id)
                        watchForUnexpectedExit(of: runtime, operationID: id, handler: onEvent)
                        return
                    }
                } else {
                    readinessDeadline = clock.now.advanced(by: readinessStability)
                }
            } else {
                readinessDeadline = nil
            }

            if clock.now >= deadline {
                throw MihomoControllerError.startupTimedOut(host: host, port: port)
            }

            do {
                try await Task.sleep(for: probeInterval)
            } catch {
                throw MihomoControllerError.cancelled
            }
        }
    }

    private func throwEarlyExit(
        _ runtime: ManagedMihomoProcess,
        termination: SupervisedProcessTermination,
        operationID id: UUID
    ) async throws -> Never {
        SupervisedProcessControl.killRemainingGroupIfNeeded(runtime.processGroup)
        let output = await runtime.outputTask.value
        let portStillInUse = await portProbe(host, port)
        try ensureActiveOperation(id)
        activeProcess = nil
        if let readError = output.readError {
            throw MihomoControllerError.outputReadFailed(readError)
        }
        if portStillInUse {
            throw MihomoControllerError.portInUse(host: host, port: port)
        }
        throw MihomoControllerError.exitedBeforeReady(
            status: termination.status,
            output: output.output.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func waitForValidationTermination(
        _ process: ManagedMihomoProcess
    ) async throws -> SupervisedProcessTermination {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: validationTimeout)

        while true {
            if let termination = process.terminationBox.value {
                return termination
            }
            if clock.now >= deadline {
                throw MihomoControllerError.validationTimedOut
            }

            do {
                try await Task.sleep(for: .milliseconds(20))
            } catch {
                throw MihomoControllerError.cancelled
            }
        }
    }

    private func validateRuntimeFiles() throws {
        try validateExecutable()
        try validateHome()

        let configPath = configURL.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: configPath, isDirectory: &isDirectory) else {
            throw MihomoControllerError.configNotFound(configPath)
        }
        guard !isDirectory.boolValue, FileManager.default.isReadableFile(atPath: configPath) else {
            throw MihomoControllerError.configNotReadable(configPath)
        }
    }

    private func validateExecutable() throws {
        let executablePath = executableURL.path
        guard FileManager.default.fileExists(atPath: executablePath) else {
            throw MihomoControllerError.executableNotFound(executablePath)
        }
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw MihomoControllerError.executableNotExecutable(executablePath)
        }
    }

    private func validateHome() throws {
        let homePath = homeURL.path
        var fileStatus = stat()
        guard lstat(homePath, &fileStatus) == 0 else {
            throw MihomoControllerError.homeNotFound(homePath)
        }

        let fileType = fileStatus.st_mode & S_IFMT
        guard fileType != S_IFLNK else {
            throw MihomoControllerError.homeIsSymbolicLink(homePath)
        }
        guard fileType == S_IFDIR else {
            throw MihomoControllerError.homeNotDirectory(homePath)
        }
        guard access(homePath, W_OK | X_OK) == 0 else {
            throw MihomoControllerError.homeNotWritable(homePath)
        }
    }

    private func launch(
        arguments: [String],
        onEvent: @escaping MihomoEventHandler
    ) throws -> ManagedMihomoProcess {
        let spawned: SupervisedProcess
        do {
            spawned = try SupervisedProcess.start(
                executableURL: executableURL,
                arguments: arguments,
                workingDirectoryURL: homeURL,
                environmentOverrides: environment
            )
        } catch {
            throw MihomoControllerError.launchFailed(
                path: executableURL.path,
                reason: error.localizedDescription
            )
        }

        let terminationBox = MihomoTerminationBox()
        let waitTask = Task.detached {
            let termination = SupervisedProcessControl.waitForProcess(spawned.pid)
            spawned.lifetime.close()
            terminationBox.store(termination)
            return termination
        }
        let outputTask = Task.detached {
            await Self.readOutput(from: spawned.output, onEvent: onEvent)
        }
        return ManagedMihomoProcess(
            pid: spawned.pid,
            processGroup: spawned.processGroup,
            lifetime: spawned.lifetime,
            terminationBox: terminationBox,
            waitTask: waitTask,
            outputTask: outputTask
        )
    }

    private func ensureActiveOperation(_ id: UUID) throws {
        guard operationID == id, !cancellationRequested else {
            throw MihomoControllerError.cancelled
        }
    }

    private func transition(to newState: MihomoState, handler: MihomoEventHandler) async {
        state = newState
        await handler(.stateChanged(newState))
    }

    private func cancelOperation(id: UUID) async {
        guard operationID == id else { return }
        cancellationRequested = true
        await shutDownOperation(id: id, emitStopping: true)
    }

    private func shutDownOperation(id: UUID, emitStopping: Bool) async {
        guard operationID == id else { return }
        let handler = eventHandler

        if emitStopping, state != .stopping {
            state = .stopping
            if let handler { await handler(.stateChanged(.stopping)) }
            guard operationID == id else { return }
        }

        if let process = activeProcess {
            let task: Task<SupervisedProcessTermination, Never>
            if let existing = terminationTask, existing.pid == process.pid {
                task = existing.task
            } else {
                task = Task.detached {
                    await Self.terminate(process, gracePeriod: self.stopTimeout)
                }
                terminationTask = (process.pid, task)
            }
            _ = await task.value
            _ = await process.outputTask.value
        }

        guard operationID == id else { return }
        activeProcess = nil
        terminationTask = nil
        operationID = nil
        cancellationRequested = false
        eventHandler = nil
        state = .stopped
        if let handler { await handler(.stateChanged(.stopped)) }
    }

    private func watchForUnexpectedExit(
        of process: ManagedMihomoProcess,
        operationID id: UUID,
        handler: @escaping MihomoEventHandler
    ) {
        Task.detached { [weak self] in
            let termination = await process.waitTask.value
            guard let self else { return }
            await self.handleUnexpectedExit(
                process: process,
                termination: termination,
                operationID: id,
                handler: handler
            )
        }
    }

    private func handleUnexpectedExit(
        process: ManagedMihomoProcess,
        termination: SupervisedProcessTermination,
        operationID id: UUID,
        handler: MihomoEventHandler
    ) async {
        guard operationID == id,
            activeProcess?.pid == process.pid,
            !cancellationRequested,
            state != .stopping
        else {
            return
        }

        SupervisedProcessControl.killRemainingGroupIfNeeded(process.processGroup)
        let output = await process.outputTask.value

        guard operationID == id,
            activeProcess?.pid == process.pid,
            !cancellationRequested
        else {
            return
        }

        activeProcess = nil
        terminationTask = nil
        operationID = nil
        eventHandler = nil
        state = .stopped
        await handler(
            .unexpectedExit(
                status: termination.status,
                output: output.output.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        await handler(.stateChanged(.stopped))
    }

    private nonisolated static func terminate(
        _ process: ManagedMihomoProcess,
        gracePeriod: Duration
    ) async -> SupervisedProcessTermination {
        process.lifetime.close()
        if SupervisedProcessControl.processGroupExists(process.processGroup) {
            _ = Darwin.kill(-process.processGroup, SIGTERM)
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: gracePeriod)
        while SupervisedProcessControl.processGroupExists(process.processGroup),
            clock.now < deadline
        {
            do {
                try await Task.sleep(for: .milliseconds(20))
            } catch {
                break
            }
        }

        if SupervisedProcessControl.processGroupExists(process.processGroup) {
            _ = Darwin.kill(-process.processGroup, SIGKILL)
        }
        return await process.waitTask.value
    }

    private nonisolated static func readOutput(
        from output: SupervisedProcessOutput,
        onEvent: MihomoEventHandler
    ) async -> MihomoOutputCapture {
        defer { Darwin.close(output.fileDescriptor) }

        var pending = Data()
        var captured = Data()
        var containsFatalDiagnostic = false
        var buffer = [UInt8](repeating: 0, count: 4_096)
        let captureLimit = 64 * 1_024

        while true {
            let byteCount = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(output.fileDescriptor, bytes.baseAddress, bytes.count)
            }
            if byteCount > 0 {
                let data = Data(buffer.prefix(byteCount))
                if captured.count < captureLimit {
                    captured.append(data.prefix(captureLimit - captured.count))
                }
                pending.append(data)
                while let newline = pending.firstIndex(of: 0x0a) {
                    var line = pending[..<newline]
                    if line.last == 0x0d { line = line.dropLast() }
                    let text = String(decoding: line, as: UTF8.self)
                    containsFatalDiagnostic = containsFatalDiagnostic || isFatalDiagnostic(text)
                    await onEvent(.log(text))
                    pending.removeSubrange(...newline)
                }
                continue
            }
            if byteCount == -1, errno == EINTR {
                continue
            }
            if byteCount == -1 {
                return MihomoOutputCapture(
                    output: String(decoding: captured, as: UTF8.self),
                    readError: String(cString: strerror(errno)),
                    containsFatalDiagnostic: containsFatalDiagnostic
                )
            }
            break
        }

        if !pending.isEmpty {
            let text = String(decoding: pending, as: UTF8.self)
            containsFatalDiagnostic = containsFatalDiagnostic || isFatalDiagnostic(text)
            await onEvent(.log(text))
        }
        return MihomoOutputCapture(
            output: String(decoding: captured, as: UTF8.self),
            readError: nil,
            containsFatalDiagnostic: containsFatalDiagnostic
        )
    }

    private nonisolated static func isFatalDiagnostic(_ output: String) -> Bool {
        let normalized = output.lowercased()
        if normalized.contains("parse config error") || normalized.contains("level=fatal") {
            return true
        }

        let words = normalized.split { character in
            !character.isLetter && !character.isNumber && character != "_"
        }
        return words.contains("fata") || words.contains("fatal")
    }

    nonisolated static func probeTCPPort(host: String, port: UInt16) -> Bool {
        var hints = addrinfo(
            ai_flags: AI_NUMERICSERV,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var addresses: UnsafeMutablePointer<addrinfo>?
        let service = String(port)
        let resolutionStatus = host.withCString { hostPointer in
            service.withCString { servicePointer in
                getaddrinfo(hostPointer, servicePointer, &hints, &addresses)
            }
        }
        guard resolutionStatus == 0, let addresses else { return false }
        defer { freeaddrinfo(addresses) }

        var current: UnsafeMutablePointer<addrinfo>? = addresses
        while let addressInfo = current?.pointee {
            defer { current = addressInfo.ai_next }
            guard let address = addressInfo.ai_addr else { continue }

            let socketDescriptor = Darwin.socket(
                addressInfo.ai_family,
                addressInfo.ai_socktype,
                addressInfo.ai_protocol
            )
            guard socketDescriptor >= 0 else { continue }
            defer { Darwin.close(socketDescriptor) }

            let flags = fcntl(socketDescriptor, F_GETFL, 0)
            guard flags >= 0, fcntl(socketDescriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
                continue
            }

            let result = Darwin.connect(socketDescriptor, address, addressInfo.ai_addrlen)
            if result == 0 { return true }
            guard errno == EINPROGRESS else { continue }

            var descriptor = pollfd(fd: socketDescriptor, events: Int16(POLLOUT), revents: 0)
            guard Darwin.poll(&descriptor, 1, 100) > 0 else { continue }

            var socketError: Int32 = 0
            var optionLength = socklen_t(MemoryLayout<Int32>.size)
            guard
                getsockopt(
                    socketDescriptor,
                    SOL_SOCKET,
                    SO_ERROR,
                    &socketError,
                    &optionLength
                ) == 0,
                socketError == 0
            else {
                continue
            }
            return true
        }
        return false
    }
}

private struct MihomoOutputCapture: Sendable {
    let output: String
    let readError: String?
    let containsFatalDiagnostic: Bool
}

private final class MihomoTerminationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: SupervisedProcessTermination?

    var value: SupervisedProcessTermination? {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func store(_ value: SupervisedProcessTermination) {
        lock.lock()
        storedValue = value
        lock.unlock()
    }
}

private struct ManagedMihomoProcess: Sendable {
    let pid: pid_t
    let processGroup: pid_t
    let lifetime: ProcessLifetime
    let terminationBox: MihomoTerminationBox
    let waitTask: Task<SupervisedProcessTermination, Never>
    let outputTask: Task<MihomoOutputCapture, Never>
}
