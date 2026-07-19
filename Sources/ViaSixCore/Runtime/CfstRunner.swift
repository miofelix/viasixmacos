import Darwin
import Foundation

public typealias CfstEventHandler = @Sendable (CfstOutputEvent) async -> Void

public enum CfstRunnerError: Error, Equatable, LocalizedError, Sendable {
    case alreadyRunning
    case executableNotFound(String)
    case executableNotExecutable(String)
    case cannotRemovePreviousResult(path: String, reason: String)
    case launchFailed(path: String, reason: String)
    case outputReadFailed(String)
    case userCancelled
    case nonZeroExit(status: Int32, output: String)
    case resultFileMissing(String)
    case resultReadFailed(path: String, reason: String)
    case noResults

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            "已有测速任务正在运行"
        case .executableNotFound(let path):
            "未找到 CFST 可执行文件：\(path)"
        case .executableNotExecutable(let path):
            "CFST 文件不可执行：\(path)"
        case .cannotRemovePreviousResult(let path, let reason):
            "无法删除旧测速结果 \(path)：\(reason)"
        case .launchFailed(let path, let reason):
            "无法启动 CFST \(path)：\(reason)"
        case .outputReadFailed(let reason):
            "读取 CFST 输出失败：\(reason)"
        case .userCancelled:
            "测速已取消"
        case .nonZeroExit(let status, let output):
            output.isEmpty
                ? "CFST 异常退出（状态码 \(status)）"
                : "CFST 异常退出（状态码 \(status)）：\(output)"
        case .resultFileMissing(let path):
            "CFST 未生成测速结果：\(path)"
        case .resultReadFailed(let path, let reason):
            "读取测速结果 \(path) 失败：\(reason)"
        case .noResults:
            "没有任何 IP 通过测速"
        }
    }
}

/// Runs one CloudflareSpeedTest process at a time and owns its complete lifetime.
///
/// The executable is placed in its own process group so cancellation also stops
/// any subprocesses it may have created. Standard output and standard error are
/// merged and parsed incrementally in their original pipe order.
public actor CfstRunner {
    public let executableURL: URL
    public let resultURL: URL
    public let workingDirectoryURL: URL

    private struct ActiveRun {
        let id: UUID
        let processGroup: pid_t
        var userCancelled = false
    }

    private var activeRun: ActiveRun?

    public init(
        executableURL: URL,
        resultURL: URL? = nil,
        workingDirectoryURL: URL? = nil
    ) {
        let executableURL = executableURL.standardizedFileURL
        self.executableURL = executableURL
        self.resultURL = (resultURL ?? executableURL.deletingLastPathComponent()
            .appendingPathComponent("result.csv")).standardizedFileURL
        self.workingDirectoryURL = (workingDirectoryURL ?? executableURL.deletingLastPathComponent())
            .standardizedFileURL
    }

    public var isRunning: Bool { activeRun != nil }

    /// Runs CFST and returns the newly generated CSV results.
    ///
    /// `onEvent` is invoked serially as merged process output arrives. This
    /// method does not return until the process has been reaped and the output
    /// pipe has reached EOF.
    public func run(
        parameters: SpeedTestParameters,
        onEvent: @escaping CfstEventHandler = { _ in }
    ) async throws -> [SpeedTestResult] {
        guard activeRun == nil else { throw CfstRunnerError.alreadyRunning }

        let arguments = try parameters.commandLineArguments(resultURL: resultURL)
        try validateExecutable()
        try removePreviousResult()

        let process: SpawnedCfstProcess
        do {
            process = try SpawnedCfstProcess.start(
                executableURL: executableURL,
                arguments: arguments,
                workingDirectoryURL: workingDirectoryURL
            )
        } catch {
            throw CfstRunnerError.launchFailed(
                path: executableURL.path,
                reason: error.localizedDescription
            )
        }

        let runID = UUID()
        activeRun = ActiveRun(id: runID, processGroup: process.processGroup)
        defer { activeRun = nil }

        let outputTask = Task.detached(priority: nil) {
            try await Self.readOutput(from: process.output, onEvent: onEvent)
        }
        let waitTask = Task.detached(priority: nil) {
            Self.waitForProcess(process.pid)
        }

        return try await withTaskCancellationHandler {
            let termination = await waitTask.value
            let outputResult: Result<String, Error>
            do {
                outputResult = .success(try await outputTask.value)
            } catch {
                outputResult = .failure(error)
            }

            let wasCancelled = activeRun?.userCancelled == true || Task.isCancelled
            if wasCancelled {
                throw CfstRunnerError.userCancelled
            }

            let output: String
            switch outputResult {
            case .success(let capturedOutput):
                output = capturedOutput
            case .failure(let error):
                throw CfstRunnerError.outputReadFailed(error.localizedDescription)
            }

            guard termination.status == 0 else {
                throw CfstRunnerError.nonZeroExit(
                    status: termination.status,
                    output: output.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }

            return try loadNewResults()
        } onCancel: {
            Task { await self.cancel(runID: runID) }
        }
    }

    /// Cancels the current run. Calling this while idle has no effect.
    public func cancel() {
        guard let runID = activeRun?.id else { return }
        cancel(runID: runID)
    }

    private func cancel(runID: UUID) {
        guard var run = activeRun, run.id == runID, !run.userCancelled else { return }
        run.userCancelled = true
        activeRun = run

        // The child is its process-group leader. A negative PID signals the
        // whole group, preventing helper subprocesses from being orphaned.
        _ = Darwin.kill(-run.processGroup, SIGKILL)
    }

    private func validateExecutable() throws {
        let path = executableURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw CfstRunnerError.executableNotFound(path)
        }
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw CfstRunnerError.executableNotExecutable(path)
        }
    }

    private func removePreviousResult() throws {
        let path = resultURL.path
        guard FileManager.default.fileExists(atPath: path) else { return }
        do {
            try FileManager.default.removeItem(at: resultURL)
        } catch {
            throw CfstRunnerError.cannotRemovePreviousResult(
                path: path,
                reason: error.localizedDescription
            )
        }
    }

    private func loadNewResults() throws -> [SpeedTestResult] {
        let path = resultURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw CfstRunnerError.resultFileMissing(path)
        }

        let data: Data
        do {
            data = try Data(contentsOf: resultURL)
        } catch {
            throw CfstRunnerError.resultReadFailed(path: path, reason: error.localizedDescription)
        }

        let results: [SpeedTestResult]
        do {
            results = try SpeedTestResultParser.parse(data: data)
        } catch {
            throw CfstRunnerError.resultReadFailed(path: path, reason: error.localizedDescription)
        }
        guard !results.isEmpty else { throw CfstRunnerError.noResults }
        return results
    }

    private nonisolated static func readOutput(
        from output: CfstProcessOutput,
        onEvent: CfstEventHandler
    ) async throws -> String {
        defer { try? output.fileHandle.close() }

        var parser = CfstOutputParser()
        var diagnosticOutput = Data()
        let diagnosticLimit = 64 * 1_024

        while let data = try output.fileHandle.read(upToCount: 4_096), !data.isEmpty {
            if diagnosticOutput.count < diagnosticLimit {
                diagnosticOutput.append(data.prefix(diagnosticLimit - diagnosticOutput.count))
            }
            for event in parser.consume(data) {
                await onEvent(event)
            }
        }
        for event in parser.finish() {
            await onEvent(event)
        }

        return String(decoding: diagnosticOutput, as: UTF8.self)
    }

    private nonisolated static func waitForProcess(_ pid: pid_t) -> CfstProcessTermination {
        var waitStatus: Int32 = 0
        while Darwin.waitpid(pid, &waitStatus, 0) == -1 {
            if errno == EINTR { continue }
            return CfstProcessTermination(status: -1)
        }

        let signal = waitStatus & 0x7f
        if signal == 0 {
            return CfstProcessTermination(status: (waitStatus >> 8) & 0xff)
        }
        return CfstProcessTermination(status: 128 + signal)
    }
}

private struct CfstProcessTermination: Sendable {
    let status: Int32
}

private final class CfstProcessOutput: @unchecked Sendable {
    let fileHandle: FileHandle

    init(fileDescriptor: Int32) {
        fileHandle = FileHandle(fileDescriptor: fileDescriptor, closeOnDealloc: true)
    }
}

private struct SpawnedCfstProcess: Sendable {
    let pid: pid_t
    let processGroup: pid_t
    let output: CfstProcessOutput

    static func start(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL
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

        let strings = [executableURL.path] + arguments
        var argv = strings.map { strdup($0) }
        defer { argv.forEach { free($0) } }
        argv.append(nil)

        var pid: pid_t = 0
        let spawnResult = executableURL.path.withCString { executablePath in
            posix_spawn(
                &pid,
                executablePath,
                &fileActions,
                &spawnAttributes,
                &argv,
                environ
            )
        }
        try check(spawnResult)

        shouldCloseReadDescriptor = false
        return Self(
            pid: pid,
            processGroup: pid,
            output: CfstProcessOutput(fileDescriptor: descriptors[0])
        )
    }

    private static func check(_ status: Int32) throws {
        guard status != 0 else { return }
        throw POSIXError(POSIXErrorCode(rawValue: status) ?? .EIO)
    }
}
