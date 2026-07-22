import Darwin
import Foundation

public typealias CfstEventHandler = @Sendable (CfstOutputEvent) async -> Void

public enum CfstRunnerError: Error, Equatable, LocalizedError, Sendable {
    case alreadyRunning
    case executableNotFound(String)
    case executableNotExecutable(String)
    case cannotPromoteResult(path: String, reason: String)
    case launchFailed(path: String, reason: String)
    case outputReadFailed(String)
    case userCancelled
    case activityTimedOut
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
        case .cannotPromoteResult(let path, let reason):
            "无法保存测速结果 \(path)：\(reason)"
        case .launchFailed(let path, let reason):
            "无法启动 CFST \(path)：\(reason)"
        case .outputReadFailed(let reason):
            "读取 CFST 输出失败：\(reason)"
        case .userCancelled:
            "测速已取消"
        case .activityTimedOut:
            "CFST 长时间没有输出进度，已停止测速。"
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

    private let activityTimeoutOverride: Duration?
    private var activeRun: ActiveRun?

    /// Explicit cancellation and the parent-lifetime watchdog cover normal
    /// operation.  This synchronous fallback protects callers that release a
    /// runner without awaiting its task: only the process group created by
    /// this runner is signalled, never an arbitrary process using a port.
    deinit {
        guard let run = activeRun, run.processGroup > 1 else { return }
        run.lifetime.close()
        _ = Darwin.kill(-run.processGroup, SIGKILL)
    }

    public init(
        executableURL: URL,
        resultURL: URL? = nil,
        workingDirectoryURL: URL? = nil,
        activityTimeout: Duration? = nil
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
        self.activityTimeoutOverride = activityTimeout
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

        let temporaryResultURL = makeTemporaryResultURL()
        defer { try? FileManager.default.removeItem(at: temporaryResultURL) }

        let arguments = try parameters.commandLineArguments(resultURL: temporaryResultURL)
        let activityTimeout =
            activityTimeoutOverride ?? Self.defaultActivityTimeout(for: parameters)
        try validateExecutable()
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

        let activity = CfstActivityTracker()
        let terminationBox = CfstTerminationBox()
        let outputTask = Task.detached(priority: nil) {
            try await Self.readOutput(
                from: process.output,
                onEvent: onEvent,
                onActivity: { await activity.mark() }
            )
        }
        let waitTask = Task.detached(priority: nil) {
            let termination = SupervisedProcessControl.waitForProcess(process.pid)
            process.lifetime.close()
            terminationBox.store(termination)
            return termination
        }

        return try await withTaskCancellationHandler {
            let completion = try await waitForCompletion(
                of: process,
                waitTask: waitTask,
                terminationBox: terminationBox,
                activity: activity,
                activityTimeout: activityTimeout
            )

            let termination: SupervisedProcessTermination
            let timedOut: Bool
            switch completion {
            case .terminated(let value):
                termination = value
                timedOut = false
            case .timedOut(let value):
                termination = value
                timedOut = true
            }
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

            if timedOut {
                throw CfstRunnerError.activityTimedOut
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

            let results = try loadNewResults(
                from: temporaryResultURL,
                processOutput: output
            )
            guard activeRun?.userCancelled != true, !Task.isCancelled else {
                throw CfstRunnerError.userCancelled
            }
            try promoteResult(from: temporaryResultURL)
            return results
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

    private func waitForCompletion(
        of process: SupervisedProcess,
        waitTask: Task<SupervisedProcessTermination, Never>,
        terminationBox: CfstTerminationBox,
        activity: CfstActivityTracker,
        activityTimeout: Duration
    ) async throws -> CfstRunOutcome {
        while true {
            if let termination = terminationBox.value {
                return .terminated(termination)
            }
            if await activity.isInactive(for: activityTimeout) {
                if let termination = terminationBox.value {
                    return .terminated(termination)
                }
                process.lifetime.close()
                _ = Darwin.kill(-process.processGroup, SIGKILL)
                return .timedOut(await waitTask.value)
            }

            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                _ = await waitTask.value
                throw CfstRunnerError.userCancelled
            }
        }
    }

    nonisolated static func defaultActivityTimeout(for parameters: SpeedTestParameters) -> Duration {
        let longestExpectedDownload =
            parameters.disableDownload || parameters.downloadCount == 0
            ? 0
            : parameters.downloadTime
        // A single download can legitimately be silent for its configured
        // duration. Keep a five-minute floor for the scan and a two-minute
        // cushion around longer downloads.
        return .seconds(max(300, longestExpectedDownload + 120))
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

    private func makeTemporaryResultURL() -> URL {
        resultURL.deletingLastPathComponent().appendingPathComponent(
            ".\(resultURL.lastPathComponent).\(UUID().uuidString).tmp"
        )
    }

    private func loadNewResults(
        from temporaryResultURL: URL,
        processOutput: String
    ) throws -> [SpeedTestResult] {
        let path = resultURL.path
        guard FileManager.default.fileExists(atPath: temporaryResultURL.path) else {
            if Self.outputIndicatesNoResults(processOutput) {
                throw CfstRunnerError.noResults
            }
            throw CfstRunnerError.resultFileMissing(path)
        }

        let data: Data
        do {
            data = try Data(contentsOf: temporaryResultURL)
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

    private nonisolated static func outputIndicatesNoResults(_ output: String) -> Bool {
        output.contains("延迟测速结果 IP 数量为 0")
            || output.contains("完整测速结果 IP 数量为 0")
    }

    private func promoteResult(from temporaryResultURL: URL) throws {
        let status = temporaryResultURL.path.withCString { temporaryPath in
            resultURL.path.withCString { resultPath in
                Darwin.rename(temporaryPath, resultPath)
            }
        }
        guard status == 0 else {
            throw CfstRunnerError.cannotPromoteResult(
                path: resultURL.path,
                reason: String(cString: strerror(errno))
            )
        }
    }

    private nonisolated static func readOutput(
        from output: SupervisedProcessOutput,
        onEvent: CfstEventHandler,
        onActivity: @escaping @Sendable () async -> Void
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
                await onActivity()
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

private enum CfstRunOutcome: Sendable {
    case terminated(SupervisedProcessTermination)
    case timedOut(SupervisedProcessTermination)
}

private actor CfstActivityTracker {
    private let clock = ContinuousClock()
    private var lastActivity: ContinuousClock.Instant

    init() {
        lastActivity = clock.now
    }

    func mark() {
        lastActivity = clock.now
    }

    func isInactive(for timeout: Duration) -> Bool {
        clock.now >= lastActivity.advanced(by: timeout)
    }
}

private final class CfstTerminationBox: @unchecked Sendable {
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
