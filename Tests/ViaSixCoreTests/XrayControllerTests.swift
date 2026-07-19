import Darwin
import Foundation
import XCTest
@testable import ViaSixCore

final class XrayControllerTests: XCTestCase {
    func testStartValidatesConfigStreamsLogsAndWaitsForPort() async throws {
        let fixture = try XrayControllerFixture(behavior: "normal")
        defer { fixture.remove() }

        let probe = XrayFixturePortProbe(
            readyFileURL: fixture.readyFileURL,
            processIDsURL: fixture.processIDsURL
        )
        let recorder = XrayEventRecorder()
        let controller = makeController(fixture: fixture) { _, _ in
            await probe.isOpen()
        }

        try await controller.start { event in
            await recorder.append(event)
        }

        let state = await controller.state
        guard case .running(let pid) = state else {
            return XCTFail("Expected running state, got \(state)")
        }
        XCTAssertGreaterThan(pid, 0)

        for _ in 0..<100 {
            let recordedEvents = await recorder.events
            if recordedEvents.contains(.log("runtime stdout")),
               recordedEvents.contains(.log("runtime stderr")) {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let events = await recorder.events
        XCTAssertTrue(events.contains(.stateChanged(.validating)))
        XCTAssertTrue(events.contains(.stateChanged(.starting)))
        XCTAssertTrue(events.contains(.stateChanged(.running(pid: pid))))
        XCTAssertTrue(events.contains(.log("validation stdout")))
        XCTAssertTrue(events.contains(.log("validation stderr")))
        XCTAssertTrue(events.contains(.log("runtime stdout")), "\(events)")
        XCTAssertTrue(events.contains(.log("runtime stderr")), "\(events)")

        let invocations = try String(contentsOf: fixture.invocationsURL, encoding: .utf8)
        XCTAssertTrue(invocations.contains("run -test -config \(fixture.configURL.path)"))
        XCTAssertTrue(invocations.contains("run -config \(fixture.configURL.path)"))

        let processEnvironment = try String(
            contentsOf: fixture.environmentURL,
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(processEnvironment, fixture.assetDirectoryURL.path)
        let processWorkingDirectory = try String(
            contentsOf: fixture.workingDirectoryURL,
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(
            URL(fileURLWithPath: processWorkingDirectory).resolvingSymlinksInPath().path,
            fixture.directoryURL.resolvingSymlinksInPath().path
        )

        await controller.stop()
        let stoppedState = await controller.state
        XCTAssertEqual(stoppedState, .stopped)
        for processID in try fixture.runtimeProcessIDs() {
            try await waitUntilProcessIsGone(processID)
        }
    }

    func testValidationFailureIncludesMergedOutputAndDoesNotStartRuntime() async throws {
        let fixture = try XrayControllerFixture(behavior: "validation-failure")
        defer { fixture.remove() }

        let controller = makeController(fixture: fixture) { _, _ in
            XCTFail("Port must not be probed after failed validation")
            return false
        }

        do {
            try await controller.start()
            XCTFail("Expected validation failure")
        } catch let error as XrayControllerError {
            guard case .validationFailed(let status, let output) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(status, 9)
            XCTAssertTrue(output.contains("invalid stdout"))
            XCTAssertTrue(output.contains("invalid stderr"))
        }

        let stoppedState = await controller.state
        XCTAssertEqual(stoppedState, .stopped)
        let invocations = try String(contentsOf: fixture.invocationsURL, encoding: .utf8)
        XCTAssertEqual(invocations.components(separatedBy: .newlines).filter { !$0.isEmpty }.count, 1)
        XCTAssertTrue(invocations.contains("run -test -config"))
    }

    func testUnexpectedRuntimeExitIsReportedAndClearsRunningState() async throws {
        let fixture = try XrayControllerFixture(behavior: "unexpected-exit")
        defer { fixture.remove() }

        let probe = XrayFixturePortProbe(readyFileURL: fixture.readyFileURL)
        let recorder = XrayEventRecorder()
        let controller = makeController(fixture: fixture) { _, _ in
            await probe.isOpen()
        }

        try await controller.start { event in
            await recorder.append(event)
        }

        for _ in 0..<200 {
            if await recorder.events.contains(where: { event in
                if case .unexpectedExit(status: 7, output: let output) = event {
                    return output.contains("runtime failed")
                }
                return false
            }) {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let events = await recorder.events
        XCTAssertTrue(events.contains(where: { event in
            if case .unexpectedExit(status: 7, output: let output) = event {
                return output.contains("runtime failed")
            }
            return false
        }))
        let stoppedState = await controller.state
        let isRunning = await controller.isRunning
        XCTAssertEqual(stoppedState, .stopped)
        XCTAssertFalse(isRunning)
    }

    func testTaskCancellationKillsOwnedProcessGroupAndReapsLeader() async throws {
        let fixture = try XrayControllerFixture(behavior: "ignore-term")
        defer { fixture.remove() }

        let probe = XrayFixturePortProbe(readyFileURL: nil)
        let controller = makeController(
            fixture: fixture,
            stopTimeout: .milliseconds(50)
        ) { _, _ in
            await probe.isOpen()
        }

        let startTask = Task {
            try await controller.start()
        }
        try await waitUntilFileExists(fixture.processIDsURL)
        let processIDs = try fixture.runtimeProcessIDs()
        XCTAssertEqual(processIDs.count, 2)

        startTask.cancel()
        do {
            try await startTask.value
            XCTFail("Expected cancellation")
        } catch let error as XrayControllerError {
            XCTAssertEqual(error, .cancelled)
        }

        let stoppedState = await controller.state
        XCTAssertEqual(stoppedState, .stopped)
        for processID in processIDs {
            try await waitUntilProcessIsGone(processID)
        }
    }

    func testRestartStopsOwnedProcessAndStartsAValidatedReplacement() async throws {
        let fixture = try XrayControllerFixture(behavior: "normal")
        defer { fixture.remove() }

        let probe = XrayFixturePortProbe(
            readyFileURL: fixture.readyFileURL,
            processIDsURL: fixture.processIDsURL
        )
        let controller = makeController(fixture: fixture) { _, _ in
            await probe.isOpen()
        }

        try await controller.start()
        guard case .running(let firstPID) = await controller.state else {
            return XCTFail("Expected first runtime")
        }

        try await controller.restart()
        guard case .running(let secondPID) = await controller.state else {
            return XCTFail("Expected replacement runtime")
        }
        XCTAssertNotEqual(firstPID, secondPID)

        let invocationLines = try String(contentsOf: fixture.invocationsURL, encoding: .utf8)
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
        XCTAssertEqual(invocationLines.count, 4)
        XCTAssertEqual(invocationLines.filter { $0.contains("-test") }.count, 2)

        await controller.stop()
    }

    func testOccupiedPortPreventsRuntimeLaunch() async throws {
        let fixture = try XrayControllerFixture(behavior: "normal")
        defer { fixture.remove() }

        let controller = makeController(fixture: fixture) { _, _ in true }
        do {
            try await controller.start()
            XCTFail("Expected occupied-port error")
        } catch let error as XrayControllerError {
            XCTAssertEqual(error, .portInUse(host: "127.0.0.1", port: 11_451))
        }

        let invocations = try String(contentsOf: fixture.invocationsURL, encoding: .utf8)
        let lines = invocations.components(separatedBy: .newlines).filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("run -test -config"))
    }

    private func makeController(
        fixture: XrayControllerFixture,
        stopTimeout: Duration = .milliseconds(250),
        portProbe: @escaping XrayPortProbe
    ) -> XrayController {
        XrayController(
            executableURL: fixture.executableURL,
            configURL: fixture.configURL,
            workingDirectoryURL: fixture.directoryURL,
            environment: ["XRAY_LOCATION_ASSET": fixture.assetDirectoryURL.path],
            startupTimeout: .seconds(2),
            probeInterval: .milliseconds(10),
            stopTimeout: stopTimeout,
            portProbe: portProbe
        )
    }

    private func waitUntilFileExists(_ url: URL) async throws {
        for _ in 0..<200 {
            if FileManager.default.fileExists(atPath: url.path) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for \(url.path)")
    }

    private func waitUntilProcessIsGone(_ pid: pid_t) async throws {
        for _ in 0..<200 {
            if Darwin.kill(pid, 0) == -1, errno == ESRCH { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("PID \(pid) is still alive")
    }
}

private actor XrayEventRecorder {
    private(set) var events: [XrayEvent] = []

    func append(_ event: XrayEvent) {
        events.append(event)
    }
}

private actor XrayFixturePortProbe {
    private let readyFileURL: URL?
    private let processIDsURL: URL?
    private var callCount = 0

    init(readyFileURL: URL?, processIDsURL: URL? = nil) {
        self.readyFileURL = readyFileURL
        self.processIDsURL = processIDsURL
    }

    func isOpen() -> Bool {
        callCount += 1
        guard callCount > 1, let readyFileURL else { return false }
        guard FileManager.default.fileExists(atPath: readyFileURL.path) else { return false }
        guard let processIDsURL else { return true }
        guard let contents = try? String(contentsOf: processIDsURL, encoding: .utf8),
              let firstPIDText = contents.split(whereSeparator: \.isWhitespace).first,
              let firstPID = pid_t(firstPIDText) else {
            return false
        }
        return Darwin.kill(firstPID, 0) == 0 || errno == EPERM
    }
}

private final class XrayControllerFixture: @unchecked Sendable {
    let directoryURL: URL
    let executableURL: URL
    let configURL: URL
    let assetDirectoryURL: URL
    let invocationsURL: URL
    let readyFileURL: URL
    let processIDsURL: URL
    let environmentURL: URL
    let workingDirectoryURL: URL

    init(behavior: String) throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViaSix-XrayControllerTests-\(UUID().uuidString)", isDirectory: true)
        executableURL = directoryURL.appendingPathComponent("xray")
        configURL = directoryURL.appendingPathComponent("config.json")
        assetDirectoryURL = directoryURL.appendingPathComponent("assets", isDirectory: true)
        invocationsURL = directoryURL.appendingPathComponent("invocations.txt")
        readyFileURL = directoryURL.appendingPathComponent("ready")
        processIDsURL = directoryURL.appendingPathComponent("pids.txt")
        environmentURL = directoryURL.appendingPathComponent("environment.txt")
        workingDirectoryURL = directoryURL.appendingPathComponent("working-directory.txt")

        try FileManager.default.createDirectory(
            at: assetDirectoryURL,
            withIntermediateDirectories: true
        )
        try "{}".write(to: configURL, atomically: true, encoding: .utf8)
        try behavior.write(
            to: directoryURL.appendingPathComponent("behavior.txt"),
            atomically: true,
            encoding: .utf8
        )
        try Self.script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
    }

    func runtimeProcessIDs() throws -> [pid_t] {
        try String(contentsOf: processIDsURL, encoding: .utf8)
            .split(whereSeparator: \.isWhitespace)
            .compactMap { pid_t($0) }
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private static let script = #"""
    #!/bin/sh
    behavior=$(cat behavior.txt)
    printf '%s\n' "$*" >> invocations.txt
    printf '%s\n' "$PWD" > working-directory.txt
    printf '%s\n' "$XRAY_LOCATION_ASSET" > environment.txt

    if [ "$2" = "-test" ]; then
      if [ "$behavior" = "validation-failure" ]; then
        printf 'invalid stdout\n'
        printf 'invalid stderr\n' >&2
        exit 9
      fi
      printf 'validation stdout\n'
      printf 'validation stderr\n' >&2
      exit 0
    fi

    printf 'runtime stdout\n'
    printf 'runtime stderr\n' >&2
    : > ready

    if [ "$behavior" = "unexpected-exit" ]; then
      sleep 0.2
      printf 'runtime failed\n' >&2
      exit 7
    fi

    if [ "$behavior" = "ignore-term" ]; then
      trap '' TERM
    else
      trap 'rm -f ready; exit 0' TERM
    fi
    sleep 30 &
    child=$!
    printf '%s %s\n' "$$" "$child" > pids.txt
    wait "$child"
    rm -f ready
    """#
}
