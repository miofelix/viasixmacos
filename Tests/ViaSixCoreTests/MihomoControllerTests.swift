import Darwin
import Foundation
import XCTest

@testable import ViaSixCore

final class MihomoControllerTests: XCTestCase {
    func testStartUsesNativeArgumentsHomeAndEnvironmentThenStopsOwnedProcesses() async throws {
        let fixture = try MihomoControllerFixture(behavior: "normal")
        defer { fixture.remove() }

        let probe = MihomoFixturePortProbe(
            readyFileURL: fixture.readyFileURL,
            processIDsURL: fixture.processIDsURL
        )
        let recorder = MihomoEventRecorder()
        let controller = makeController(fixture: fixture) { _, _ in
            await probe.isOpen()
        }

        try await controller.start { event in
            await recorder.append(event)
        }

        guard case .running(let pid) = await controller.state else {
            return XCTFail("Expected running state")
        }
        XCTAssertGreaterThan(pid, 0)

        let invocations = try fixture.invocations()
        XCTAssertEqual(
            invocations,
            [
                "-t -d \(fixture.homeURL.path) -f \(fixture.configURL.path)",
                "-d \(fixture.homeURL.path) -f \(fixture.configURL.path)",
            ]
        )
        let workingDirectory = try fixture.contents(of: fixture.workingDirectoryURL)
        XCTAssertEqual(
            URL(fileURLWithPath: workingDirectory).resolvingSymlinksInPath().path,
            URL(fileURLWithPath: fixture.homeURL.path).resolvingSymlinksInPath().path
        )
        XCTAssertEqual(try fixture.contents(of: fixture.environmentURL), "UTC")
        XCTAssertEqual(try fixture.contents(of: fixture.dangerousEnvironmentURL), "|||")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.shellHookMarkerURL.path))

        let events = await recorder.events
        XCTAssertTrue(events.contains(.stateChanged(.validating)))
        XCTAssertTrue(events.contains(.stateChanged(.starting)))
        XCTAssertTrue(events.contains(.stateChanged(.running(pid: pid))))
        XCTAssertTrue(events.contains(.log("configuration is valid")))
        XCTAssertTrue(events.contains(.log("runtime stdout")))
        XCTAssertTrue(events.contains(.log("runtime stderr")))

        let processIDs = try fixture.runtimeProcessIDs()
        XCTAssertEqual(processIDs.count, 2)
        await controller.stop()
        let stoppedState = await controller.state
        XCTAssertEqual(stoppedState, .stopped)
        for processID in processIDs {
            try await waitUntilProcessIsGone(processID)
        }
    }

    func testVersionUsesNativeVersionArgument() async throws {
        let fixture = try MihomoControllerFixture(behavior: "normal")
        defer { fixture.remove() }
        let controller = makeController(fixture: fixture) { _, _ in false }

        let output = try await controller.version(timeout: .seconds(1))

        XCTAssertEqual(
            output,
            """
            Mihomo Meta v1.19.29 darwin arm64 with go1.26.5 Sat Jul 18 12:19:57 UTC 2026
            Use tags: with_gvisor
            """
        )
        XCTAssertEqual(try fixture.invocations(), ["-v"])
    }

    func testEnvironmentSanitizerDropsMihomoControlVariablesAndUsesSafePath() {
        let sanitized = MihomoController.sanitizedEnvironment(
            parent: [
                "PATH": "/tmp/attacker",
                "TMPDIR": "/private/tmp/safe",
                "CLASH_CONFIG_STRING": "untrusted",
                "BASH_ENV": "/tmp/parent-hook",
                "ENV": "/tmp/parent-env",
                "SHELLOPTS": "xtrace",
                "SSL_CERT_FILE": "/tmp/untrusted-ca.pem",
                "SSL_CERT_DIR": "/tmp/untrusted-certs",
            ],
            overrides: [
                "PATH": "/tmp/override",
                "CLASH_POST_UP": "touch /tmp/owned",
                "BASH_ENV": "/tmp/override-hook",
                "ENV": "/tmp/override-env",
                "BASHOPTS": "extdebug",
                "PS4": "$(touch /tmp/owned)",
                "SSL_CERT_FILE": "/tmp/override-ca.pem",
                "SSL_CERT_DIR": "/tmp/override-certs",
                "TZ": "UTC",
            ]
        )

        XCTAssertEqual(sanitized["PATH"], "/usr/bin:/bin:/usr/sbin:/sbin")
        XCTAssertEqual(sanitized["TMPDIR"], "/private/tmp/safe")
        XCTAssertEqual(sanitized["TZ"], "UTC")
        XCTAssertNil(sanitized["CLASH_CONFIG_STRING"])
        XCTAssertNil(sanitized["CLASH_POST_UP"])
        XCTAssertNil(sanitized["BASH_ENV"])
        XCTAssertNil(sanitized["ENV"])
        XCTAssertNil(sanitized["SHELLOPTS"])
        XCTAssertNil(sanitized["BASHOPTS"])
        XCTAssertNil(sanitized["PS4"])
        XCTAssertNil(sanitized["SSL_CERT_FILE"])
        XCTAssertNil(sanitized["SSL_CERT_DIR"])
    }

    func testNonzeroValidationFailureIncludesMergedOutput() async throws {
        let fixture = try MihomoControllerFixture(behavior: "validation-failure")
        defer { fixture.remove() }
        let controller = makeController(fixture: fixture) { _, _ in
            XCTFail("Port must not be probed after failed validation")
            return false
        }

        do {
            try await controller.start()
            XCTFail("Expected validation failure")
        } catch let error as MihomoControllerError {
            guard case .validationFailed(let status, let output) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(status, 9)
            XCTAssertTrue(output.contains("invalid stdout"))
            XCTAssertTrue(output.contains("invalid stderr"))
        }

        let stoppedState = await controller.state
        XCTAssertEqual(stoppedState, .stopped)
        XCTAssertEqual(try fixture.invocations().count, 1)
    }

    func testZeroExitValidationFailsClosedForMihomoFatalDiagnostics() async throws {
        let diagnostics = [
            "[FATA] invalid configuration",
            "fatal: invalid configuration",
            "Parse config error: invalid field",
            "time=now level=fatal msg=invalid",
        ]

        for diagnostic in diagnostics {
            let fixture = try MihomoControllerFixture(
                behavior: "validation-fatal-zero",
                validationDiagnostic: diagnostic
            )
            defer { fixture.remove() }
            let controller = makeController(fixture: fixture) { _, _ in
                XCTFail("Port must not be probed after fatal validation output")
                return false
            }

            do {
                try await controller.start()
                XCTFail("Expected fatal diagnostic to fail validation: \(diagnostic)")
            } catch let error as MihomoControllerError {
                guard case .validationFailed(let status, let output) = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
                XCTAssertEqual(status, 0)
                XCTAssertTrue(output.contains(diagnostic))
            }
        }
    }

    func testBenignWordContainingFatalDoesNotCauseFalsePositive() async throws {
        let fixture = try MihomoControllerFixture(
            behavior: "validation-benign-zero",
            validationDiagnostic: "nonfatal compatibility note"
        )
        defer { fixture.remove() }
        let probe = MihomoFixturePortProbe(
            readyFileURL: fixture.readyFileURL,
            processIDsURL: fixture.processIDsURL
        )
        let controller = makeController(fixture: fixture) { _, _ in
            await probe.isOpen()
        }

        try await controller.start()
        let isRunning = await controller.isRunning
        XCTAssertTrue(isRunning)
        await controller.stop()
    }

    func testMissingHomeIsRejectedBeforeLaunch() async throws {
        let fixture = try MihomoControllerFixture(behavior: "normal")
        defer { fixture.remove() }
        let missingURL = fixture.directoryURL.appendingPathComponent("missing", isDirectory: true)
        let controller = makeController(fixture: fixture, homeURL: missingURL) { _, _ in false }

        do {
            try await controller.start()
            XCTFail("Expected missing home error")
        } catch let error as MihomoControllerError {
            XCTAssertEqual(error, .homeNotFound(missingURL.path))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.invocationsURL.path))
    }

    func testSymbolicLinkHomeIsRejectedBeforeLaunch() async throws {
        let fixture = try MihomoControllerFixture(behavior: "normal")
        defer { fixture.remove() }
        let linkURL = fixture.directoryURL.appendingPathComponent("home-link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: fixture.homeURL)
        let controller = makeController(fixture: fixture, homeURL: linkURL) { _, _ in false }

        do {
            try await controller.start()
            XCTFail("Expected symbolic-link home error")
        } catch let error as MihomoControllerError {
            XCTAssertEqual(error, .homeIsSymbolicLink(linkURL.path))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.invocationsURL.path))
    }

    func testRegularFileHomeIsRejectedBeforeLaunch() async throws {
        let fixture = try MihomoControllerFixture(behavior: "normal")
        defer { fixture.remove() }
        let fileURL = fixture.directoryURL.appendingPathComponent("not-a-directory")
        try Data().write(to: fileURL)
        let controller = makeController(fixture: fixture, homeURL: fileURL) { _, _ in false }

        do {
            try await controller.start()
            XCTFail("Expected non-directory home error")
        } catch let error as MihomoControllerError {
            XCTAssertEqual(error, .homeNotDirectory(fileURL.path))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.invocationsURL.path))
    }

    func testUnwritableHomeIsRejectedBeforeLaunch() async throws {
        let fixture = try MihomoControllerFixture(behavior: "normal")
        defer { fixture.remove() }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: fixture.homeURL.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: fixture.homeURL.path
            )
        }
        guard access(fixture.homeURL.path, W_OK) != 0 else {
            throw XCTSkip("Current test process can write a mode-0555 directory")
        }
        let controller = makeController(fixture: fixture) { _, _ in false }

        do {
            try await controller.start()
            XCTFail("Expected unwritable home error")
        } catch let error as MihomoControllerError {
            XCTAssertEqual(error, .homeNotWritable(fixture.homeURL.path))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.invocationsURL.path))
    }

    func testValidationTimeoutKillsOwnedProcessGroup() async throws {
        let fixture = try MihomoControllerFixture(behavior: "validation-timeout")
        defer { fixture.remove() }
        let controller = makeController(
            fixture: fixture,
            validationTimeout: .milliseconds(300),
            stopTimeout: .milliseconds(50)
        ) { _, _ in false }

        let startTask = Task { try await controller.start() }
        try await waitUntilFileExists(fixture.processIDsURL)
        let processIDs = try fixture.runtimeProcessIDs()

        do {
            try await startTask.value
            XCTFail("Expected validation timeout")
        } catch let error as MihomoControllerError {
            XCTAssertEqual(error, .validationTimedOut)
        }
        let stoppedState = await controller.state
        XCTAssertEqual(stoppedState, .stopped)
        for processID in processIDs {
            try await waitUntilProcessIsGone(processID)
        }
    }

    func testTaskCancellationKillsRuntimeProcessGroup() async throws {
        let fixture = try MihomoControllerFixture(behavior: "ignore-term")
        defer { fixture.remove() }
        let controller = makeController(
            fixture: fixture,
            stopTimeout: .milliseconds(50)
        ) { _, _ in false }

        let startTask = Task { try await controller.start() }
        try await waitUntilFileExists(fixture.processIDsURL)
        let processIDs = try fixture.runtimeProcessIDs()
        startTask.cancel()

        do {
            try await startTask.value
            XCTFail("Expected cancellation")
        } catch let error as MihomoControllerError {
            XCTAssertEqual(error, .cancelled)
        }
        let stoppedState = await controller.state
        XCTAssertEqual(stoppedState, .stopped)
        for processID in processIDs {
            try await waitUntilProcessIsGone(processID)
        }
    }

    func testUnexpectedExitClearsRunningStateAndEmitsEvent() async throws {
        let fixture = try MihomoControllerFixture(behavior: "unexpected-exit")
        defer { fixture.remove() }
        let probe = MihomoFixturePortProbe(readyFileURL: fixture.readyFileURL)
        let recorder = MihomoEventRecorder()
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
        XCTAssertTrue(
            events.contains(where: { event in
                if case .unexpectedExit(status: 7, output: let output) = event {
                    return output.contains("runtime failed")
                }
                return false
            })
        )
        let stoppedState = await controller.state
        let isRunning = await controller.isRunning
        XCTAssertEqual(stoppedState, .stopped)
        XCTAssertFalse(isRunning)
    }

    func testRestartStopsOwnedRuntimeAndStartsValidatedReplacement() async throws {
        let fixture = try MihomoControllerFixture(behavior: "normal")
        defer { fixture.remove() }
        let probe = MihomoFixturePortProbe(
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
        let invocations = try fixture.invocations()
        XCTAssertEqual(invocations.count, 4)
        XCTAssertEqual(invocations.filter { $0.hasPrefix("-t ") }.count, 2)
        await controller.stop()
    }

    func testReleasingControllerKillsItsOwnedRealTCPListener() async throws {
        let port = try unusedLoopbackPort()
        let fixture = try MihomoControllerFixture(behavior: "real-listener", runtimePort: port)
        defer { fixture.remove() }
        var controller: MihomoController? = makeController(
            fixture: fixture,
            port: port,
            stopTimeout: .milliseconds(100)
        ) { host, port in
            MihomoController.probeTCPPort(host: host, port: port)
        }

        try await controller?.start()
        try await waitUntilFileExists(fixture.processIDsURL)
        let processIDs = try fixture.runtimeProcessIDs()
        XCTAssertEqual(processIDs.count, 2)
        XCTAssertTrue(MihomoController.probeTCPPort(host: "127.0.0.1", port: port))

        controller = nil
        try await waitUntilPortIsClosed(port)
        for processID in processIDs {
            try await waitUntilProcessIsGone(processID)
        }
    }

    func testOccupiedPortPreventsRuntimeLaunch() async throws {
        let fixture = try MihomoControllerFixture(behavior: "normal")
        defer { fixture.remove() }
        let controller = makeController(fixture: fixture) { _, _ in true }

        do {
            try await controller.start()
            XCTFail("Expected occupied-port error")
        } catch let error as MihomoControllerError {
            XCTAssertEqual(error, .portInUse(host: "127.0.0.1", port: 11_451))
        }

        XCTAssertEqual(try fixture.invocations().count, 1)
        XCTAssertTrue(try fixture.invocations()[0].hasPrefix("-t "))
    }

    func testRuntimeExitDuringReadinessReportsPortConflict() async throws {
        let fixture = try MihomoControllerFixture(behavior: "unexpected-exit")
        defer { fixture.remove() }
        let probe = SequencedMihomoPortProbe(values: [false, true, true])
        let controller = makeController(
            fixture: fixture,
            readinessStability: .seconds(1),
            probeInterval: .milliseconds(20)
        ) { _, _ in
            await probe.next()
        }

        do {
            try await controller.start()
            XCTFail("Expected a port conflict when Mihomo exits during readiness")
        } catch let error as MihomoControllerError {
            XCTAssertEqual(error, .portInUse(host: "127.0.0.1", port: 11_451))
        }

        let state = await controller.state
        XCTAssertEqual(state, .stopped)
    }

    func testDefaultPortProbeSupportsIPv4AndLocalhost() throws {
        let listener = try LoopbackTCPListener(family: AF_INET)

        XCTAssertTrue(MihomoController.probeTCPPort(host: "127.0.0.1", port: listener.port))
        XCTAssertTrue(MihomoController.probeTCPPort(host: "localhost", port: listener.port))
    }

    func testDefaultPortProbeSupportsIPv6() throws {
        let listener = try LoopbackTCPListener(family: AF_INET6)

        XCTAssertTrue(MihomoController.probeTCPPort(host: "::1", port: listener.port))
    }

    private func makeController(
        fixture: MihomoControllerFixture,
        homeURL: URL? = nil,
        host: String = "127.0.0.1",
        port: UInt16 = 11_451,
        validationTimeout: Duration = .seconds(1),
        startupTimeout: Duration = .seconds(2),
        readinessStability: Duration = .milliseconds(20),
        probeInterval: Duration = .milliseconds(10),
        stopTimeout: Duration = .milliseconds(250),
        portProbe: @escaping MihomoPortProbe
    ) -> MihomoController {
        MihomoController(
            executableURL: fixture.executableURL,
            configURL: fixture.configURL,
            homeURL: homeURL ?? fixture.homeURL,
            environment: [
                "CLASH_CONFIG_STRING": "untrusted",
                "CLASH_POST_UP": "touch /tmp/owned",
                "BASH_ENV": fixture.shellHookURL.path,
                "ENV": fixture.shellHookURL.path,
                "SHELLOPTS": "xtrace",
                "BASHOPTS": "extdebug",
                "PS4": "$(touch /tmp/owned)",
                "TZ": "UTC",
            ],
            host: host,
            port: port,
            validationTimeout: validationTimeout,
            startupTimeout: startupTimeout,
            readinessStability: readinessStability,
            probeInterval: probeInterval,
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
        for _ in 0..<250 {
            if Darwin.kill(pid, 0) == -1, errno == ESRCH { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("PID \(pid) is still alive")
    }

    private func waitUntilPortIsClosed(_ port: UInt16) async throws {
        for _ in 0..<300 {
            if !MihomoController.probeTCPPort(host: "127.0.0.1", port: port) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("TCP port \(port) remained open after supervised group exit")
    }

    private func unusedLoopbackPort() throws -> UInt16 {
        let listener = try LoopbackTCPListener(family: AF_INET)
        return listener.port
    }
}

private actor MihomoEventRecorder {
    private(set) var events: [MihomoEvent] = []

    func append(_ event: MihomoEvent) {
        events.append(event)
    }
}

private actor MihomoFixturePortProbe {
    private let readyFileURL: URL
    private let processIDsURL: URL?
    private var callCount = 0

    init(readyFileURL: URL, processIDsURL: URL? = nil) {
        self.readyFileURL = readyFileURL
        self.processIDsURL = processIDsURL
    }

    func isOpen() -> Bool {
        callCount += 1
        guard callCount > 1 else { return false }
        guard FileManager.default.fileExists(atPath: readyFileURL.path) else { return false }
        guard let processIDsURL else { return true }
        guard let contents = try? String(contentsOf: processIDsURL, encoding: .utf8),
            let firstPIDText = contents.split(whereSeparator: \.isWhitespace).first,
            let firstPID = pid_t(firstPIDText)
        else {
            return false
        }
        return Darwin.kill(firstPID, 0) == 0 || errno == EPERM
    }
}

private actor SequencedMihomoPortProbe {
    private var values: [Bool]

    init(values: [Bool]) {
        self.values = values
    }

    func next() -> Bool {
        if values.count > 1 {
            return values.removeFirst()
        }
        return values.first ?? false
    }
}

private final class MihomoControllerFixture: @unchecked Sendable {
    let directoryURL: URL
    let executableURL: URL
    let configURL: URL
    let homeURL: URL
    let invocationsURL: URL
    let readyFileURL: URL
    let processIDsURL: URL
    let environmentURL: URL
    let dangerousEnvironmentURL: URL
    let shellHookURL: URL
    let shellHookMarkerURL: URL
    let workingDirectoryURL: URL

    init(
        behavior: String,
        validationDiagnostic: String? = nil,
        runtimePort: UInt16? = nil
    ) throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ViaSix-MihomoControllerTests-\(UUID().uuidString)",
                isDirectory: true
            )
        executableURL = directoryURL.appendingPathComponent("mihomo")
        configURL = directoryURL.appendingPathComponent("config.yaml")
        homeURL = directoryURL.appendingPathComponent("home", isDirectory: true)
        invocationsURL = homeURL.appendingPathComponent("invocations.txt")
        readyFileURL = homeURL.appendingPathComponent("ready")
        processIDsURL = homeURL.appendingPathComponent("pids.txt")
        environmentURL = homeURL.appendingPathComponent("environment.txt")
        dangerousEnvironmentURL = homeURL.appendingPathComponent("dangerous-environment.txt")
        shellHookURL = homeURL.appendingPathComponent("shell-hook.sh")
        shellHookMarkerURL = homeURL.appendingPathComponent("shell-hook-ran")
        workingDirectoryURL = homeURL.appendingPathComponent("working-directory.txt")

        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        try "mode: rule\n".write(to: configURL, atomically: true, encoding: .utf8)
        try behavior.write(
            to: homeURL.appendingPathComponent("behavior.txt"),
            atomically: true,
            encoding: .utf8
        )
        if let validationDiagnostic {
            try validationDiagnostic.write(
                to: homeURL.appendingPathComponent("validation-diagnostic.txt"),
                atomically: true,
                encoding: .utf8
            )
        }
        if let runtimePort {
            try String(runtimePort).write(
                to: homeURL.appendingPathComponent("port.txt"),
                atomically: true,
                encoding: .utf8
            )
        }
        try "#!/bin/sh\n/usr/bin/touch '\(shellHookMarkerURL.path)'\n".write(
            to: shellHookURL,
            atomically: true,
            encoding: .utf8
        )
        try Self.script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
    }

    func invocations() throws -> [String] {
        try String(contentsOf: invocationsURL, encoding: .utf8)
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
    }

    func runtimeProcessIDs() throws -> [pid_t] {
        try String(contentsOf: processIDsURL, encoding: .utf8)
            .split(whereSeparator: \.isWhitespace)
            .compactMap { pid_t($0) }
    }

    func contents(of url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private static let script = #"""
        #!/bin/sh
        behavior=$(cat behavior.txt)
        printf '%s\n' "$*" >> invocations.txt
        printf '%s\n' "$PWD" > working-directory.txt
        printf '%s\n' "$TZ" > environment.txt
        printf '%s|%s|%s|%s\n' \
          "$CLASH_CONFIG_STRING" "$CLASH_POST_UP" "$BASH_ENV" "$ENV" \
          > dangerous-environment.txt

        if [ "$1" = "-v" ]; then
          printf 'Mihomo Meta v1.19.29 darwin arm64 with go1.26.5 Sat Jul 18 12:19:57 UTC 2026\n'
          printf 'Use tags: with_gvisor\n'
          exit 0
        fi

        if [ "$1" = "-t" ]; then
          if [ "$behavior" = "validation-failure" ]; then
            printf 'invalid stdout\n'
            printf 'invalid stderr\n' >&2
            exit 9
          fi
          if [ "$behavior" = "validation-timeout" ]; then
            trap '' TERM
            (trap '' TERM; sleep 30) &
            child=$!
            printf '%s %s\n' "$$" "$child" > pids.txt
            wait "$child"
            exit 0
          fi
          if [ "$behavior" = "validation-fatal-zero" ] ||
             [ "$behavior" = "validation-benign-zero" ]; then
            cat validation-diagnostic.txt
            exit 0
          fi
          printf 'configuration is valid\n'
          exit 0
        fi

        printf 'runtime stdout\n'
        printf 'runtime stderr\n' >&2
        : > ready

        if [ "$behavior" = "unexpected-exit" ]; then
          sleep 0.15
          printf 'runtime failed\n' >&2
          exit 7
        fi

        if [ "$behavior" = "real-listener" ]; then
          port=$(cat port.txt)
          /usr/bin/nc -lk 127.0.0.1 "$port" >/dev/null 2>&1 &
          child=$!
          printf '%s %s\n' "$$" "$child" > pids.txt
          wait "$child"
          exit $?
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

private final class LoopbackTCPListener {
    let port: UInt16

    private let fileDescriptor: Int32

    init(family: Int32) throws {
        let descriptor = Darwin.socket(family, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw Self.lastPOSIXError() }

        do {
            port = try Self.bindLoopback(descriptor, family: family)
            guard Darwin.listen(descriptor, 4) == 0 else {
                throw Self.lastPOSIXError()
            }
            fileDescriptor = descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    deinit {
        Darwin.close(fileDescriptor)
    }

    private static func bindLoopback(_ descriptor: Int32, family: Int32) throws -> UInt16 {
        switch family {
        case AF_INET:
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            guard
                "127.0.0.1".withCString({ inet_pton(AF_INET, $0, &address.sin_addr) }) == 1
            else {
                throw lastPOSIXError()
            }
            let bindStatus = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(
                        descriptor,
                        $0,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
            guard bindStatus == 0 else { throw lastPOSIXError() }

            var addressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let nameStatus = withUnsafeMutablePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.getsockname(descriptor, $0, &addressLength)
                }
            }
            guard nameStatus == 0 else { throw lastPOSIXError() }
            return UInt16(bigEndian: address.sin_port)

        case AF_INET6:
            var address = sockaddr_in6()
            address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            address.sin6_family = sa_family_t(AF_INET6)
            guard
                "::1".withCString({ inet_pton(AF_INET6, $0, &address.sin6_addr) }) == 1
            else {
                throw lastPOSIXError()
            }
            let bindStatus = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(
                        descriptor,
                        $0,
                        socklen_t(MemoryLayout<sockaddr_in6>.size)
                    )
                }
            }
            guard bindStatus == 0 else { throw lastPOSIXError() }

            var addressLength = socklen_t(MemoryLayout<sockaddr_in6>.size)
            let nameStatus = withUnsafeMutablePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.getsockname(descriptor, $0, &addressLength)
                }
            }
            guard nameStatus == 0 else { throw lastPOSIXError() }
            return UInt16(bigEndian: address.sin6_port)

        default:
            throw POSIXError(.EAFNOSUPPORT)
        }
    }

    private static func lastPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
