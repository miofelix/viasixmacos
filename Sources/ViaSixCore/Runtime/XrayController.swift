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

/// Owns the complete lifetime of one Xray process and its process group.
///
/// The controller never searches for or signals processes it did not spawn.
/// Both validation and runtime output merge stdout/stderr into one ordered log
/// stream, and every spawned process is reaped with `waitpid`.
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
    private var terminationTask: (pid: pid_t, task: Task<XrayProcessTermination, Never>)?

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
        self.workingDirectoryURL = (workingDirectoryURL
            ?? executableURL.deletingLastPathComponent()).standardizedFileURL
        self.environment = environment
        self.host = host
        self.port = port
        self.startupTimeout = startupTimeout
        self.probeInterval = probeInterval
        self.stopTimeout = stopTimeout
        self.portProbe = portProbe ?? { host, port in
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
            let wasCancelled = Task.isCancelled
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
        Self.killRemainingGroupIfNeeded(validation.processGroup)
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
                Self.killRemainingGroupIfNeeded(runtime.processGroup)
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
                    Self.killRemainingGroupIfNeeded(runtime.processGroup)
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
        let spawned: SpawnedXrayProcess
        do {
            spawned = try SpawnedXrayProcess.start(
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
            let termination = Self.waitForProcess(spawned.pid)
            terminationBox.store(termination)
            return termination
        }
        let outputTask = Task.detached {
            await Self.readOutput(from: spawned.output, onEvent: onEvent)
        }
        return ManagedXrayProcess(
            pid: spawned.pid,
            processGroup: spawned.processGroup,
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
            let task: Task<XrayProcessTermination, Never>
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
        termination: XrayProcessTermination,
        operationID id: UUID,
        handler: XrayEventHandler
    ) async {
        guard operationID == id,
              activeProcess?.pid == process.pid,
              !cancellationRequested,
              state != .stopping else {
            return
        }

        Self.killRemainingGroupIfNeeded(process.processGroup)
        let output = await process.outputTask.value

        guard operationID == id,
              activeProcess?.pid == process.pid,
              !cancellationRequested else {
            return
        }

        activeProcess = nil
        terminationTask = nil
        operationID = nil
        eventHandler = nil
        state = .stopped
        await handler(.unexpectedExit(
            status: termination.status,
            output: output.output.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        await handler(.stateChanged(.stopped))
    }

    private nonisolated static func terminate(
        _ process: ManagedXrayProcess,
        gracePeriod: Duration
    ) async -> XrayProcessTermination {
        if processGroupExists(process.processGroup) {
            _ = Darwin.kill(-process.processGroup, SIGTERM)
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: gracePeriod)
        while processGroupExists(process.processGroup), clock.now < deadline {
            do {
                try await Task.sleep(for: .milliseconds(20))
            } catch {
                break
            }
        }

        if processGroupExists(process.processGroup) {
            _ = Darwin.kill(-process.processGroup, SIGKILL)
        }
        return await process.waitTask.value
    }

    private nonisolated static func killRemainingGroupIfNeeded(_ processGroup: pid_t) {
        if processGroupExists(processGroup) {
            _ = Darwin.kill(-processGroup, SIGKILL)
        }
    }

    private nonisolated static func processGroupExists(_ processGroup: pid_t) -> Bool {
        if Darwin.kill(-processGroup, 0) == 0 { return true }
        return errno == EPERM
    }

    private nonisolated static func waitForProcess(_ pid: pid_t) -> XrayProcessTermination {
        var waitStatus: Int32 = 0
        while Darwin.waitpid(pid, &waitStatus, 0) == -1 {
            if errno == EINTR { continue }
            return XrayProcessTermination(status: -1)
        }

        let signal = waitStatus & 0x7f
        if signal == 0 {
            return XrayProcessTermination(status: (waitStatus >> 8) & 0xff)
        }
        return XrayProcessTermination(status: 128 + signal)
    }

    private nonisolated static func readOutput(
        from output: XrayProcessOutput,
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

    private nonisolated static func probeTCPPort(host: String, port: UInt16) -> Bool {
        let socketDescriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else { return false }
        defer { Darwin.close(socketDescriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard host.withCString({ inet_pton(AF_INET, $0, &address.sin_addr) }) == 1 else {
            return false
        }

        let flags = fcntl(socketDescriptor, F_GETFL, 0)
        guard flags >= 0, fcntl(socketDescriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            return false
        }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(
                    socketDescriptor,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }
        if result == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        var descriptor = pollfd(fd: socketDescriptor, events: Int16(POLLOUT), revents: 0)
        guard Darwin.poll(&descriptor, 1, 100) > 0 else { return false }

        var socketError: Int32 = 0
        var optionLength = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(
            socketDescriptor,
            SOL_SOCKET,
            SO_ERROR,
            &socketError,
            &optionLength
        ) == 0 else {
            return false
        }
        return socketError == 0
    }
}

private struct XrayProcessTermination: Sendable {
    let status: Int32
}

private struct XrayOutputCapture: Sendable {
    let output: String
    let readError: String?
}

private final class XrayTerminationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: XrayProcessTermination?

    var value: XrayProcessTermination? {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func store(_ value: XrayProcessTermination) {
        lock.lock()
        storedValue = value
        lock.unlock()
    }
}

private struct ManagedXrayProcess: Sendable {
    let pid: pid_t
    let processGroup: pid_t
    let terminationBox: XrayTerminationBox
    let waitTask: Task<XrayProcessTermination, Never>
    let outputTask: Task<XrayOutputCapture, Never>
}

private final class XrayProcessOutput: @unchecked Sendable {
    let fileDescriptor: Int32

    init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }
}

private struct SpawnedXrayProcess: Sendable {
    let pid: pid_t
    let processGroup: pid_t
    let output: XrayProcessOutput

    static func start(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        environmentOverrides: [String: String]
    ) throws -> Self {
        var descriptors: [Int32] = [0, 0]
        guard Darwin.pipe(&descriptors) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var shouldCloseReadDescriptor = true
        defer {
            if shouldCloseReadDescriptor { Darwin.close(descriptors[0]) }
            Darwin.close(descriptors[1])
        }

        var fileActions: posix_spawn_file_actions_t?
        var spawnAttributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&fileActions) == 0 else {
            throw POSIXError(.EIO)
        }
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        guard posix_spawnattr_init(&spawnAttributes) == 0 else {
            throw POSIXError(.EIO)
        }
        defer { posix_spawnattr_destroy(&spawnAttributes) }

        try check(posix_spawn_file_actions_adddup2(&fileActions, descriptors[1], STDOUT_FILENO))
        try check(posix_spawn_file_actions_adddup2(&fileActions, descriptors[1], STDERR_FILENO))
        try check(posix_spawn_file_actions_addclose(&fileActions, descriptors[0]))
        try check(posix_spawn_file_actions_addclose(&fileActions, descriptors[1]))
        try workingDirectoryURL.path.withCString { path in
            try check(posix_spawn_file_actions_addchdir_np(&fileActions, path))
        }

        try check(posix_spawnattr_setflags(&spawnAttributes, Int16(POSIX_SPAWN_SETPGROUP)))
        try check(posix_spawnattr_setpgroup(&spawnAttributes, 0))

        let argumentStrings = [executableURL.path] + arguments
        var argv = argumentStrings.map { strdup($0) }
        defer { argv.forEach { free($0) } }
        argv.append(nil)

        let environment = ProcessInfo.processInfo.environment.merging(
            environmentOverrides,
            uniquingKeysWith: { _, override in override }
        )
        let environmentStrings = environment
            .map { "\($0.key)=\($0.value)" }
            .sorted()
        var envp = environmentStrings.map { strdup($0) }
        defer { envp.forEach { free($0) } }
        envp.append(nil)

        var pid: pid_t = 0
        let spawnResult = executableURL.path.withCString { executablePath in
            posix_spawn(
                &pid,
                executablePath,
                &fileActions,
                &spawnAttributes,
                &argv,
                &envp
            )
        }
        try check(spawnResult)

        shouldCloseReadDescriptor = false
        return Self(
            pid: pid,
            processGroup: pid,
            output: XrayProcessOutput(fileDescriptor: descriptors[0])
        )
    }

    private static func check(_ status: Int32) throws {
        guard status != 0 else { return }
        throw POSIXError(POSIXErrorCode(rawValue: status) ?? .EIO)
    }
}
