import Darwin
import Foundation
import XCTest

@testable import ViaSixCore

final class SupervisedCommandTests: XCTestCase {
    func testTimeoutKillsTheCommandProcessGroup() async throws {
        let fixture = try CommandFixture(script: #"""
            #!/bin/sh
            sleep 30 &
            child=$!
            printf '%s %s\n' "$$" "$child" > pids.txt
            wait "$child"
            """#)
        defer { fixture.remove() }

        do {
            _ = try await SupervisedCommand.run(
                executableURL: fixture.executableURL,
                arguments: [],
                workingDirectoryURL: fixture.directoryURL,
                timeout: .milliseconds(500)
            )
            XCTFail("Expected the command to time out")
        } catch let error as SupervisedCommandError {
            XCTAssertEqual(error, .timedOut)
        }

        try await waitUntilFileExists(fixture.processIDsURL)
        let processIDs = try fixture.processIDs()
        XCTAssertEqual(processIDs.count, 2)
        for processID in processIDs {
            try await waitUntilProcessIsGone(processID)
        }
    }

    func testTaskCancellationKillsTheCommandProcessGroup() async throws {
        let fixture = try CommandFixture(script: #"""
            #!/bin/sh
            sleep 30 &
            child=$!
            printf '%s %s\n' "$$" "$child" > pids.txt
            wait "$child"
            """#)
        defer { fixture.remove() }

        let task = Task {
            try await SupervisedCommand.run(
                executableURL: fixture.executableURL,
                arguments: [],
                workingDirectoryURL: fixture.directoryURL,
                timeout: .seconds(30)
            )
        }
        try await waitUntilFileExists(fixture.processIDsURL)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }

        let processIDs = try fixture.processIDs()
        XCTAssertEqual(processIDs.count, 2)
        for processID in processIDs {
            try await waitUntilProcessIsGone(processID)
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
        for _ in 0..<150 {
            if Darwin.kill(pid, 0) == -1, errno == ESRCH { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("PID \(pid) is still alive")
    }
}

private final class CommandFixture: @unchecked Sendable {
    let directoryURL: URL
    let executableURL: URL
    let processIDsURL: URL

    init(script: String) throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViaSix-SupervisedCommandTests-\(UUID().uuidString)", isDirectory: true)
        executableURL = directoryURL.appendingPathComponent("command")
        processIDsURL = directoryURL.appendingPathComponent("pids.txt")

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
    }

    func processIDs() throws -> [pid_t] {
        try String(contentsOf: processIDsURL, encoding: .utf8)
            .split(whereSeparator: \.isWhitespace)
            .compactMap { pid_t($0) }
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
