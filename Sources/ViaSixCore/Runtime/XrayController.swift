import Darwin
import Foundation

public typealias XrayEventHandler = @Sendable (XrayEvent) async -> Void
public typealias XrayPortProbe = @Sendable (_ host: String, _ port: UInt16) async -> Bool

public enum XrayState: Equatable, Sendable {
    case stopped
    case validating
    case starting
    case running(pid: Int32)
    case stopping
}

public enum XrayEvent: Equatable, Sendable {
    case stateChanged(XrayState)
    case log(String)
    case unexpectedExit(status: Int32, output: String)
}

public enum XrayControllerError: Error, Equatable, LocalizedError, Sendable {
    case alreadyRunning
    case executableNotFound(String)
    case executableNotExecutable(String)
    case configNotFound(String)
    case configNotReadable(String)
    case launchFailed(path: String, reason: String)
    case validationFailed(status: Int32, output: String)
    case outputReadFailed(String)
    case portInUse(host: String, port: UInt16)
    case exitedBeforeReady(status: Int32, output: String)
    case startupTimedOut(host: String, port: UInt16)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            "Xray 已在运行或正在启动。"
        case .executableNotFound(let path):
            "未找到 Xray 可执行文件：\(path)"
        case .executableNotExecutable(let path):
            "Xray 文件不可执行：\(path)"
        case .configNotFound(let path):
            "未找到 Xray 配置文件：\(path)"
        case .configNotReadable(let path):
            "Xray 配置文件不可读取：\(path)"
        case .launchFailed(let path, let reason):
            "无法启动 Xray \(path)：\(reason)"
        case .validationFailed(let status, let output):
            output.isEmpty
                ? "Xray 配置校验失败（状态码 \(status)）。"
                : "Xray 配置校验失败（状态码 \(status)）：\(output)"
        case .outputReadFailed(let reason):
            "读取 Xray 输出失败：\(reason)"
        case .portInUse(let host, let port):
            "本地代理端口已被占用：\(host):\(port)"
        case .exitedBeforeReady(let status, let output):
            output.isEmpty
                ? "Xray 在代理端口就绪前退出（状态码 \(status)）。"
                : "Xray 在代理端口就绪前退出（状态码 \(status)）：\(output)"
        case .startupTimedOut(let host, let port):
            "等待 Xray 监听 \(host):\(port) 超时。"
        case .cancelled:
            "Xray 启动已取消。"
        }
    }
}

/// Owns the complete lifetime of one supervised Xray runtime and its process group.
///
/// The controller never searches for or signals processes it did not spawn.
/// Both validation and runtime output merge stdout/stderr into one ordered log
/// stream. The controller reaps each supervisor with `waitpid`; the supervisor
/// waits for and cleans up the runtime it launches.
public actor XrayController {
    public let executableURL: URL
    public let configURL: URL
    public let workingDirectoryURL: URL
    public let host: String
    public let port: UInt16

    public private(set) var state: XrayState = .stopped

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    private let environment: [String: String]
    private let startupTimeout: Duration
    private let probeInterval: Duration
    private let stopTimeout: Duration
    private let portProbe: XrayPortProbe

    private var operationID: UUID?
    private var cancellationRequested = false
    private var eventHandler: XrayEventHandler?
    private var activeProcess: ManagedXrayProcess?
    private var terminationTask: (pid: pid_t, task: Task<SupervisedProcessTermination, Never>)?

    public init(
        executableURL: URL,
        configURL: URL,
        workingDirectoryURL: URL? = nil,
        environment: [String: String] = [:],
        host: String = "127.0.0.1",
        port: UInt16 = 11_451,
        startupTimeout: Duration = .seconds(5),
        probeInterval: Duration = .milliseconds(50),
        stopTimeout: Duration = .seconds(2),
        portProbe: XrayPortProbe? = nil
    ) {
        let executableURL = executableURL.standardizedFileURL
        self.executableURL = executableURL
        self.configURL = configURL.standardizedFileURL
        self.workingDirectoryURL =
            (workingDirectoryURL
            ?? executableURL.deletingLastPathComponent()).standardizedFileURL
        self.environment = environment
        self.host = host
        self.port = port
        self.startupTimeout = startupTimeout
        self.probeInterval = probeInterval
        self.stopTimeout = stopTimeout
        self.portProbe =
            portProbe ?? { host, port in
                Self.probeTCPPort(host: host, port: port)
            }
    }

    /// Validates the configuration, verifies the local port is free, starts
    /// Xray, and returns only after the port becomes reachable.
    public func start(
        onEvent: @escaping XrayEventHandler = { _ in }
    ) async throws {
        guard operationID == nil, state == .stopped else {
            throw XrayControllerError.alreadyRunning
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
                || (error as? XrayControllerError) == .cancelled
            await shutDownOperation(id: id, emitStopping: wasCancelled)
            if wasCancelled { throw XrayControllerError.cancelled }
            throw error
        }
    }

    /// Stops only the process group created by this controller. SIGTERM is
    /// attempted first; SIGKILL follows after `stopTimeout` if the group remains.
    public func stop() async {
        guard let id = operationID else { return }
        await cancelOperation(id: id)
    }

    public func restart(
        onEvent: @escaping XrayEventHandler = { _ in }
    ) async throws {
        await stop()
        try await start(onEvent: onEvent)
    }

    private func performStart(id: UUID, onEvent: @escaping XrayEventHandler) async throws {
        try validateFiles()
        try ensureActiveOperation(id)

        await transition(to: .validating, handler: onEvent)
        try ensureActiveOperation(id)

        let validation = try launch(
            arguments: ["run", "-test", "-config", configURL.path],
            onEvent: onEvent
        )
        activeProcess = validation

        let validationTermination = await validation.waitTask.value
        SupervisedProcessControl.killRemainingGroupIfNeeded(validation.processGroup)
        let validationOutput = await validation.outputTask.value
        try ensureActiveOperation(id)
        activeProcess = nil

        if let readError = validationOutput.readError {
            throw XrayControllerError.outputReadFailed(readError)
        }
        guard validationTermination.status == 0 else {
            throw XrayControllerError.validationFailed(
                status: validationTermination.status,
                output: validationOutput.output.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        guard !(await portProbe(host, port)) else {
            try ensureActiveOperation(id)
            throw XrayControllerError.portInUse(host: host, port: port)
        }
        try ensureActiveOperation(id)

        await transition(to: .starting, handler: onEvent)
        try ensureActiveOperation(id)

        let runtime = try launch(
            arguments: ["run", "-config", configURL.path],
            onEvent: onEvent
        )
        activeProcess = runtime

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: startupTimeout)
        while true {
            try ensureActiveOperation(id)

            if let termination = runtime.terminationBox.value {
                SupervisedProcessControl.killRemainingGroupIfNeeded(runtime.processGroup)
                let output = await runtime.outputTask.value
                try ensureActiveOperation(id)
                activeProcess = nil
                if let readError = output.readError {
                    throw XrayControllerError.outputReadFailed(readError)
                }
                throw XrayControllerError.exitedBeforeReady(
                    status: termination.status,
                    output: output.output.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }

            if await portProbe(host, port) {
                try ensureActiveOperation(id)
                if let termination = runtime.terminationBox.value {
                    SupervisedProcessControl.killRemainingGroupIfNeeded(runtime.processGroup)
                    let output = await runtime.outputTask.value
                    try ensureActiveOperation(id)
                    activeProcess = nil
                    throw XrayControllerError.exitedBeforeReady(
                        status: termination.status,
                        output: output.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }

                await transition(to: .running(pid: runtime.pid), handler: onEvent)
                try ensureActiveOperation(id)
                watchForUnexpectedExit(of: runtime, operationID: id, handler: onEvent)
                return
            }

            if clock.now >= deadline {
                throw XrayControllerError.startupTimedOut(host: host, port: port)
            }

            do {
                try await Task.sleep(for: probeInterval)
            } catch {
                throw XrayControllerError.cancelled
            }
        }
    }

    private func validateFiles() throws {
        let fileManager = FileManager.default
        let executablePath = executableURL.path
        guard fileManager.fileExists(atPath: executablePath) else {
            throw XrayControllerError.executableNotFound(executablePath)
        }
        guard fileManager.isExecutableFile(atPath: executablePath) else {
            throw XrayControllerError.executableNotExecutable(executablePath)
        }

        let configPath = configURL.path
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: configPath, isDirectory: &isDirectory) else {
            throw XrayControllerError.configNotFound(configPath)
        }
        guard !isDirectory.boolValue, fileManager.isReadableFile(atPath: configPath) else {
            throw XrayControllerError.configNotReadable(configPath)
        }
    }

    private func launch(
        arguments: [String],
        onEvent: @escaping XrayEventHandler
    ) throws -> ManagedXrayProcess {
        let spawned: SupervisedProcess
        do {
            spawned = try SupervisedProcess.start(
                executableURL: executableURL,
                arguments: arguments,
                workingDirectoryURL: workingDirectoryURL,
                environmentOverrides: environment
            )
        } catch {
            throw XrayControllerError.launchFailed(
                path: executableURL.path,
                reason: error.localizedDescription
            )
        }

        let terminationBox = XrayTerminationBox()
        let waitTask = Task.detached {
            let termination = SupervisedProcessControl.waitForProcess(spawned.pid)
            // Once the supervisor has exited there is no reason to keep its
            // watchdog waiting on the parent pipe. Closing the write end also
            // makes the watchdog reap any descendants left by a runtime that
            // exited on its own.
            spawned.lifetime.close()
            terminationBox.store(termination)
            return termination
        }
        let outputTask = Task.detached {
            await Self.readOutput(from: spawned.output, onEvent: onEvent)
        }
        return ManagedXrayProcess(
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
            throw XrayControllerError.cancelled
        }
    }

    private func transition(to newState: XrayState, handler: XrayEventHandler) async {
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
        of process: ManagedXrayProcess,
        operationID id: UUID,
        handler: @escaping XrayEventHandler
    ) {
        Task.detached {
            let termination = await process.waitTask.value
            await self.handleUnexpectedExit(
                process: process,
                termination: termination,
                operationID: id,
                handler: handler
            )
        }
    }

    private func handleUnexpectedExit(
        process: ManagedXrayProcess,
        termination: SupervisedProcessTermination,
        operationID id: UUID,
        handler: XrayEventHandler
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
        _ process: ManagedXrayProcess,
        gracePeriod: Duration
    ) async -> SupervisedProcessTermination {
        // Closing this pipe is also what the kernel does if the parent app
        // crashes or is force-quit. The supervisor owns graceful group
        // termination so the same path is used for normal and abnormal exits.
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
        onEvent: XrayEventHandler
    ) async -> XrayOutputCapture {
        defer { Darwin.close(output.fileDescriptor) }

        var pending = Data()
        var captured = Data()
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
                    await onEvent(.log(String(decoding: line, as: UTF8.self)))
                    pending.removeSubrange(...newline)
                }
                continue
            }
            if byteCount == -1, errno == EINTR {
                continue
            }
            if byteCount == -1 {
                return XrayOutputCapture(
                    output: String(decoding: captured, as: UTF8.self),
                    readError: String(cString: strerror(errno))
                )
            }
            break
        }

        if !pending.isEmpty {
            await onEvent(.log(String(decoding: pending, as: UTF8.self)))
        }
        return XrayOutputCapture(
            output: String(decoding: captured, as: UTF8.self),
            readError: nil
        )
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

private struct XrayOutputCapture: Sendable {
    let output: String
    let readError: String?
}

private final class XrayTerminationBox: @unchecked Sendable {
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

private struct ManagedXrayProcess: Sendable {
    let pid: pid_t
    let processGroup: pid_t
    let lifetime: ProcessLifetime
    let terminationBox: XrayTerminationBox
    let waitTask: Task<SupervisedProcessTermination, Never>
    let outputTask: Task<XrayOutputCapture, Never>
}
