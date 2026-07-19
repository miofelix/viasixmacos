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
/// The executable is supervised in an owned process group so cancellation and
/// an abrupt parent-app exit also stop any subprocesses it may have created.
/// Standard output and standard error are merged and parsed incrementally in
/// their original pipe order.
public actor CfstRunner {
    public let executableURL: URL
    public let resultURL: URL
    public let workingDirectoryURL: URL

    private struct ActiveRun {
        let id: UUID
        let processGroup: pid_t
        let lifetime: ProcessLifetime
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
        self.resultURL =
            (resultURL
            ?? executableURL.deletingLastPathComponent()
            .appendingPathComponent("result.csv")).standardizedFileURL
        self.workingDirectoryURL =
            (workingDirectoryURL ?? executableURL.deletingLastPathComponent())
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
        guard !Task.isCancelled else { throw CfstRunnerError.userCancelled }

        let arguments = try parameters.commandLineArguments(resultURL: resultURL)
        try validateExecutable()
        try removePreviousResult()
        guard !Task.isCancelled else { throw CfstRunnerError.userCancelled }

        let process: SupervisedProcess
        do {
            process = try SupervisedProcess.start(
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
        activeRun = ActiveRun(
            id: runID,
            processGroup: process.processGroup,
            lifetime: process.lifetime
        )
        defer { activeRun = nil }

        let outputTask = Task.detached(priority: nil) {
            try await Self.readOutput(from: process.output, onEvent: onEvent)
        }
        let waitTask = Task.detached(priority: nil) {
            let termination = SupervisedProcessControl.waitForProcess(process.pid)
            process.lifetime.close()
            return termination
        }

        return try await withTaskCancellationHandler {
            let termination = await waitTask.value
            SupervisedProcessControl.killRemainingGroupIfNeeded(process.processGroup)
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

        // The supervisor is the process-group leader. A negative PID signals
        // the whole group, preventing helper subprocesses from being orphaned.
        run.lifetime.close()
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
        from output: SupervisedProcessOutput,
        onEvent: CfstEventHandler
    ) async throws -> String {
        defer { Darwin.close(output.fileDescriptor) }

        var parser = CfstOutputParser()
        var diagnosticOutput = Data()
        let diagnosticLimit = 64 * 1_024
        var buffer = [UInt8](repeating: 0, count: 4_096)

        while true {
            let byteCount = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(output.fileDescriptor, bytes.baseAddress, bytes.count)
            }
            if byteCount > 0 {
                let data = Data(buffer.prefix(byteCount))
                if diagnosticOutput.count < diagnosticLimit {
                    diagnosticOutput.append(data.prefix(diagnosticLimit - diagnosticOutput.count))
                }
                for event in parser.consume(data) {
                    await onEvent(event)
                }
                continue
            }
            if byteCount == -1, errno == EINTR {
                continue
            }
            if byteCount == -1 {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            break
        }

        for event in parser.finish() {
            await onEvent(event)
        }

        return String(decoding: diagnosticOutput, as: UTF8.self)
    }
}
