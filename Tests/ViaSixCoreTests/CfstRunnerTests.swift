import Darwin
import Foundation
import XCTest

@testable import ViaSixCore

final class CfstRunnerTests: XCTestCase {
    func testSuccessfulRunStreamsMergedOutputAndLoadsResults() async throws {
        let fixture = try CfstRunnerFixture(
            script: #"""
                #!/bin/sh
                output=""
                while [ "$#" -gt 0 ]; do
                  if [ "$1" = "-o" ]; then output="$2"; shift 2; else shift; fi
                done
                printf 'starting\n'
                printf '1 / 2 [==\r' >&2
                printf '\nfinished\n'
                printf 'IP,Sent,Recv,Loss,Latency,Speed,Region\n2606:4700::1,4,4,0.00,18.5,12.3,SJC\n' > "$output"
                """#)
        defer { fixture.remove() }

        let recorder = CfstEventRecorder()
        let runner = CfstRunner(executableURL: fixture.executableURL)
        let results = try await runner.run(parameters: .init(ipRange: "2606:4700::/32")) { event in
            await recorder.append(event)
        }
        let events = await recorder.events

        XCTAssertEqual(results.map(\.ip), ["2606:4700::1"])
        XCTAssertEqual(results.first?.speedValue, 12.3)
        XCTAssertTrue(events.contains(.line("starting")))
        XCTAssertTrue(events.contains(.line("finished")))
        XCTAssertTrue(events.contains(.progress(current: 1, total: 2)))
        XCTAssertTrue(
            events.contains { event in
                if case .heartbeat(let bytes) = event { return bytes > 0 }
                return false
            })
        let isRunning = await runner.isRunning
        XCTAssertFalse(isRunning)
    }

    func testNonZeroExitIncludesMergedDiagnosticOutput() async throws {
        let fixture = try CfstRunnerFixture(
            script: #"""
                #!/bin/sh
                printf 'stdout detail\n'
                printf 'stderr detail\n' >&2
                exit 7
                """#)
        defer { fixture.remove() }

        let runner = CfstRunner(executableURL: fixture.executableURL)
        do {
            _ = try await runner.run(parameters: .init(ipRange: "2606:4700::/32"))
            XCTFail("Expected non-zero exit")
        } catch let error as CfstRunnerError {
            guard case .nonZeroExit(let status, let output) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(status, 7)
            XCTAssertTrue(output.contains("stdout detail"))
            XCTAssertTrue(output.contains("stderr detail"))
        }
    }

    func testCancelKillsProcessGroupAndMapsToUserCancelled() async throws {
        let fixture = try CfstRunnerFixture(
            script: #"""
                #!/bin/sh
                sleep 30 &
                child=$!
                printf '%s %s\n' "$$" "$child" > pids.txt
                printf 'ready\n'
                wait "$child"
                """#)
        defer { fixture.remove() }

        let recorder = CfstEventRecorder()
        let runner = CfstRunner(executableURL: fixture.executableURL)
        let runTask = Task {
            try await runner.run(parameters: .init(ipRange: "2606:4700::/32")) { event in
                await recorder.append(event)
            }
        }

        let pidFile = fixture.directoryURL.appendingPathComponent("pids.txt")
        try await waitUntilFileExists(pidFile)
        let pids = try String(contentsOf: pidFile, encoding: .utf8)
            .split(whereSeparator: \.isWhitespace)
            .compactMap { pid_t($0) }
        XCTAssertEqual(pids.count, 2)

        await runner.cancel()
        do {
            _ = try await runTask.value
            XCTFail("Expected cancellation")
        } catch let error as CfstRunnerError {
            XCTAssertEqual(error, .userCancelled)
        }

        for pid in pids {
            try await waitUntilProcessIsGone(pid)
        }
        let isRunning = await runner.isRunning
        XCTAssertFalse(isRunning)
    }

    func testClosingParentLifetimePipeStopsCFSTGroupAndClosesOutput() async throws {
        let fixture = try CfstRunnerFixture(
            script: #"""
                #!/bin/sh
                sleep 30 &
                child=$!
                printf '%s %s\n' "$$" "$child" > pids.txt
                printf 'running\n'
                wait "$child"
                """#
        )
        defer { fixture.remove() }

        let spawned = try SupervisedProcess.start(
            executableURL: fixture.executableURL,
            arguments: [],
            workingDirectoryURL: fixture.directoryURL
        )
        defer {
            spawned.lifetime.close()
            _ = Darwin.kill(-spawned.processGroup, SIGKILL)
            var waitStatus: Int32 = 0
            while Darwin.waitpid(spawned.pid, &waitStatus, 0) == -1, errno == EINTR {}
            Darwin.close(spawned.output.fileDescriptor)
        }

        try await waitUntilFileExists(fixture.processIDsURL)
        let processIDs = try String(contentsOf: fixture.processIDsURL, encoding: .utf8)
            .split(whereSeparator: \.isWhitespace)
            .compactMap { pid_t($0) }
        XCTAssertEqual(processIDs.count, 2)

        // Closing the parent-owned descriptor models a crash/force-quit. The
        // test deliberately sends no signal to the supervised process group.
        spawned.lifetime.close()
        try await waitUntilProcessIsReaped(spawned.pid)

        for processID in processIDs {
            try await waitUntilProcessIsGone(processID)
        }
        try await waitUntilOutputPipeCloses(spawned.output.fileDescriptor)
    }

    func testLeaderExitCleansUpBackgroundChildrenBeforeReadingEOF() async throws {
        let fixture = try CfstRunnerFixture(
            script: #"""
                #!/bin/sh
                sleep 30 &
                child=$!
                printf '%s\n' "$child" > child-pid.txt
                printf 'leader exiting\n'
                exit 7
                """#)
        defer { fixture.remove() }

        let runner = CfstRunner(executableURL: fixture.executableURL)
        let clock = ContinuousClock()
        let startedAt = clock.now
        do {
            _ = try await runner.run(parameters: .init(ipRange: "2606:4700::/32"))
            XCTFail("Expected non-zero exit")
        } catch let error as CfstRunnerError {
            guard case .nonZeroExit(let status, let output) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(status, 7)
            XCTAssertTrue(output.contains("leader exiting"))
        }

        XCTAssertLessThan(startedAt.duration(to: clock.now), .seconds(3))
        let childPIDText = try String(
            contentsOf: fixture.directoryURL.appendingPathComponent("child-pid.txt"),
            encoding: .utf8
        )
        let childPID = try XCTUnwrap(pid_t(childPIDText.trimmingCharacters(in: .whitespacesAndNewlines)))
        try await waitUntilProcessIsGone(childPID)
    }

    func testOldResultIsDeletedAndNeverReused() async throws {
        let fixture = try CfstRunnerFixture(
            script: #"""
                #!/bin/sh
                printf 'completed without csv\n'
                exit 0
                """#)
        defer { fixture.remove() }

        let staleCSV = "IP,Sent,Recv,Loss,Latency,Speed,Region\nold-ip,4,4,0,1,99,OLD\n"
        try staleCSV.write(to: fixture.resultURL, atomically: true, encoding: .utf8)

        let runner = CfstRunner(executableURL: fixture.executableURL)
        do {
            _ = try await runner.run(parameters: .init(ipRange: "2606:4700::/32"))
            XCTFail("Expected missing result error")
        } catch let error as CfstRunnerError {
            XCTAssertEqual(error, .resultFileMissing(fixture.resultURL.path))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.resultURL.path))
    }

    func testHeaderOnlyCSVReportsNoResults() async throws {
        let fixture = try CfstRunnerFixture(
            script: #"""
                #!/bin/sh
                output=""
                while [ "$#" -gt 0 ]; do
                  if [ "$1" = "-o" ]; then output="$2"; shift 2; else shift; fi
                done
                printf 'IP,Sent,Recv,Loss,Latency,Speed,Region\n' > "$output"
                """#)
        defer { fixture.remove() }

        let runner = CfstRunner(executableURL: fixture.executableURL)
        do {
            _ = try await runner.run(parameters: .init(ipRange: "2606:4700::/32"))
            XCTFail("Expected no-results error")
        } catch let error as CfstRunnerError {
            XCTAssertEqual(error, .noResults)
        }
    }

    private func waitUntilFileExists(_ url: URL) async throws {
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: url.path) { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for \(url.path)")
    }

    private func waitUntilProcessIsGone(_ pid: pid_t) async throws {
        for _ in 0..<100 {
            if Darwin.kill(pid, 0) == -1, errno == ESRCH { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("PID \(pid) still exists after cancellation")
    }

    private func waitUntilProcessIsReaped(_ pid: pid_t) async throws {
        for _ in 0..<400 {
            var waitStatus: Int32 = 0
            let result = Darwin.waitpid(pid, &waitStatus, WNOHANG)
            if result == pid { return }
            if result == -1 {
                if errno == EINTR { continue }
                if errno == ECHILD { return }
                return XCTFail("waitpid failed for PID \(pid): \(String(cString: strerror(errno)))")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting to reap PID \(pid)")
    }

    private func waitUntilOutputPipeCloses(_ fileDescriptor: Int32) async throws {
        for _ in 0..<200 {
            var descriptor = pollfd(
                fd: fileDescriptor,
                events: Int16(POLLIN | POLLHUP),
                revents: 0
            )
            if Darwin.poll(&descriptor, 1, 10) > 0,
                descriptor.revents & Int16(POLLHUP) != 0
            {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Output pipe remained open after the supervised group exited")
    }
}

private actor CfstEventRecorder {
    private(set) var events: [CfstOutputEvent] = []

    func append(_ event: CfstOutputEvent) {
        events.append(event)
    }
}

private final class CfstRunnerFixture: @unchecked Sendable {
    let directoryURL: URL
    let executableURL: URL
    let resultURL: URL
    let processIDsURL: URL

    init(script: String) throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViaSix-CfstRunnerTests-\(UUID().uuidString)", isDirectory: true)
        executableURL = directoryURL.appendingPathComponent("cfst")
        resultURL = directoryURL.appendingPathComponent("result.csv")
        processIDsURL = directoryURL.appendingPathComponent("pids.txt")

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
