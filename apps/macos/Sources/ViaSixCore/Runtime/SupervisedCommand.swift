import Darwin
import Foundation

struct SupervisedCommandResult: Sendable {
    let status: Int32
    let output: String
    let outputReadError: String?
}

enum SupervisedCommandError: Error, Equatable, Sendable {
    case timedOut
}

/// Runs a bounded one-shot command in the same supervised process model used
/// by the long-lived runtimes. The parent-owned lifetime descriptor makes an
/// abrupt app exit terminate the complete command group, while task
/// cancellation and the deadline stop it explicitly.
enum SupervisedCommand {
    static func run(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        environmentOverrides: [String: String] = [:],
        inheritParentEnvironment: Bool = true,
        timeout: Duration
    ) async throws -> SupervisedCommandResult {
        try Task.checkCancellation()

        let process = try SupervisedProcess.start(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectoryURL: workingDirectoryURL,
            environmentOverrides: environmentOverrides,
            inheritParentEnvironment: inheritParentEnvironment
        )
        let waitTask = Task.detached {
            let termination = SupervisedProcessControl.waitForProcess(process.pid)
            process.lifetime.close()
            return termination
        }
        let outputTask = Task.detached {
            readOutput(from: process.output)
        }

        let outcome: WaitOutcome
        do {
            outcome = try await withTaskCancellationHandler {
                try await withThrowingTaskGroup(of: WaitOutcome.self) { group in
                    group.addTask {
                        .exited(await waitTask.value)
                    }
                    // Only signal the deadline here. Killing and reaping must
                    // happen after this branch wins, otherwise the exit task
                    // can race ahead and report a normal completion for a
                    // process we intentionally timed out.
                    group.addTask {
                        try await Task.sleep(for: timeout)
                        return .timedOut
                    }

                    guard let first = try await group.next() else {
                        throw CancellationError()
                    }
                    group.cancelAll()

                    switch first {
                    case .timedOut:
                        terminateImmediately(process)
                        _ = await waitTask.value
                        return .timedOut
                    case .exited:
                        return first
                    }
                }
            } onCancel: {
                terminateImmediately(process)
            }
        } catch {
            terminateImmediately(process)
            _ = await waitTask.value
            SupervisedProcessControl.killRemainingGroupIfNeeded(process.processGroup)
            _ = await outputTask.value
            if Task.isCancelled {
                throw CancellationError()
            }
            throw error
        }

        SupervisedProcessControl.killRemainingGroupIfNeeded(process.processGroup)
        let output = await outputTask.value
        try Task.checkCancellation()

        switch outcome {
        case .exited(let termination):
            return SupervisedCommandResult(
                status: termination.status,
                output: output.output,
                outputReadError: output.readError
            )
        case .timedOut:
            throw SupervisedCommandError.timedOut
        }
    }

    private static func terminateImmediately(_ process: SupervisedProcess) {
        process.lifetime.close()
        if SupervisedProcessControl.processGroupExists(process.processGroup) {
            _ = Darwin.kill(-process.processGroup, SIGKILL)
        }
    }

    private static func readOutput(
        from output: SupervisedProcessOutput
    ) -> OutputCapture {
        defer { Darwin.close(output.fileDescriptor) }

        var captured = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        let captureLimit = 64 * 1_024

        while true {
            let byteCount = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(output.fileDescriptor, bytes.baseAddress, bytes.count)
            }
            if byteCount > 0 {
                if captured.count < captureLimit {
                    captured.append(
                        contentsOf: buffer.prefix(
                            min(byteCount, captureLimit - captured.count)
                        )
                    )
                }
                continue
            }
            if byteCount == -1, errno == EINTR {
                continue
            }
            if byteCount == -1 {
                return OutputCapture(
                    output: String(decoding: captured, as: UTF8.self),
                    readError: String(cString: strerror(errno))
                )
            }
            return OutputCapture(
                output: String(decoding: captured, as: UTF8.self),
                readError: nil
            )
        }
    }

    private enum WaitOutcome: Sendable {
        case exited(SupervisedProcessTermination)
        case timedOut
    }

    private struct OutputCapture: Sendable {
        let output: String
        let readError: String?
    }
}
