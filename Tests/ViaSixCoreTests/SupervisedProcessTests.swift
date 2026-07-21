import Darwin
import Foundation
import XCTest

@testable import ViaSixCore

final class SupervisedProcessTests: XCTestCase {
    func testClosingParentLifetimePipeStopsProcessGroupAndClosesOutput() async throws {
        let fixture = try SupervisedProcessFixture(behavior: "sleep")
        defer { fixture.remove() }
        let spawned = try start(fixture)
        defer { cleanUp(spawned) }

        let processIDs = try await waitUntilProcessIDs(fixture)
        XCTAssertEqual(processIDs.count, 2)

        // Models a crash or force-quit: the kernel closes the app-owned write
        // descriptor, and the supervisor must clean up without an app signal.
        spawned.lifetime.close()
        try await waitUntilProcessIsReaped(spawned.pid)

        for processID in processIDs {
            try await waitUntilProcessIsGone(processID)
        }
        try await waitUntilOutputPipeCloses(spawned.output.fileDescriptor)
    }

    func testClosingParentLifetimePipeReleasesRealTCPListener() async throws {
        let port = try unusedLoopbackPort()
        let fixture = try SupervisedProcessFixture(behavior: "real-listener", port: port)
        defer { fixture.remove() }
        let spawned = try start(fixture)
        defer { cleanUp(spawned) }

        let processIDs = try await waitUntilProcessIDs(fixture)
        XCTAssertEqual(processIDs.count, 2)
        try await waitUntilPortIsOpen(port)

        spawned.lifetime.close()
        try await waitUntilProcessIsReaped(spawned.pid)
        try await waitUntilPortIsClosed(port)

        for processID in processIDs {
            try await waitUntilProcessIsGone(processID)
        }
        try await waitUntilOutputPipeCloses(spawned.output.fileDescriptor)
    }

    private func start(_ fixture: SupervisedProcessFixture) throws -> SupervisedProcess {
        try SupervisedProcess.start(
            executableURL: fixture.executableURL,
            arguments: [],
            workingDirectoryURL: fixture.directoryURL,
            environmentOverrides: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"],
            inheritParentEnvironment: false
        )
    }

    private func cleanUp(_ process: SupervisedProcess) {
        process.lifetime.close()
        _ = Darwin.kill(-process.processGroup, SIGKILL)
        var waitStatus: Int32 = 0
        while Darwin.waitpid(process.pid, &waitStatus, 0) == -1, errno == EINTR {}
        Darwin.close(process.output.fileDescriptor)
    }

    private func waitUntilProcessIDs(
        _ fixture: SupervisedProcessFixture
    ) async throws -> [pid_t] {
        for _ in 0..<200 {
            if let processIDs = try? fixture.processIDs(), processIDs.count == 2 {
                return processIDs
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for both supervised process IDs")
        return []
    }

    private func waitUntilProcessIsGone(_ pid: pid_t) async throws {
        for _ in 0..<250 {
            if Darwin.kill(pid, 0) == -1, errno == ESRCH { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("PID \(pid) is still alive")
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

    private func waitUntilPortIsOpen(_ port: UInt16) async throws {
        for _ in 0..<200 {
            if MihomoController.probeTCPPort(host: "127.0.0.1", port: port) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for TCP port \(port) to open")
    }

    private func waitUntilPortIsClosed(_ port: UInt16) async throws {
        for _ in 0..<300 {
            if !MihomoController.probeTCPPort(host: "127.0.0.1", port: port) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("TCP port \(port) remained open after supervised group exit")
    }

    private func unusedLoopbackPort() throws -> UInt16 {
        let listener = try SupervisedLoopbackTCPListener()
        return listener.port
    }
}

private final class SupervisedProcessFixture: @unchecked Sendable {
    let directoryURL: URL
    let executableURL: URL
    let processIDsURL: URL

    init(behavior: String, port: UInt16? = nil) throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ViaSix-SupervisedProcessTests-\(UUID().uuidString)",
                isDirectory: true
            )
        executableURL = directoryURL.appendingPathComponent("runtime")
        processIDsURL = directoryURL.appendingPathComponent("pids.txt")

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try behavior.write(
            to: directoryURL.appendingPathComponent("behavior.txt"),
            atomically: true,
            encoding: .utf8
        )
        if let port {
            try String(port).write(
                to: directoryURL.appendingPathComponent("port.txt"),
                atomically: true,
                encoding: .utf8
            )
        }
        try Self.script.write(to: executableURL, atomically: true, encoding: .utf8)
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

    private static let script = #"""
        #!/bin/sh
        behavior=$(/bin/cat behavior.txt)

        if [ "$behavior" = "real-listener" ]; then
          port=$(/bin/cat port.txt)
          /usr/bin/nc -lk 127.0.0.1 "$port" >/dev/null 2>&1 &
        else
          /bin/sleep 30 &
        fi

        child=$!
        printf '%s %s\n' "$$" "$child" > pids.txt
        wait "$child"
        """#
}

private final class SupervisedLoopbackTCPListener {
    let port: UInt16

    private let fileDescriptor: Int32

    init() throws {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw Self.lastPOSIXError() }

        do {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            guard
                "127.0.0.1".withCString({ inet_pton(AF_INET, $0, &address.sin_addr) }) == 1
            else {
                throw Self.lastPOSIXError()
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
            guard bindStatus == 0 else { throw Self.lastPOSIXError() }
            guard Darwin.listen(descriptor, 4) == 0 else { throw Self.lastPOSIXError() }

            var addressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let nameStatus = withUnsafeMutablePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.getsockname(descriptor, $0, &addressLength)
                }
            }
            guard nameStatus == 0 else { throw Self.lastPOSIXError() }

            fileDescriptor = descriptor
            port = UInt16(bigEndian: address.sin_port)
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    deinit {
        Darwin.close(fileDescriptor)
    }

    private static func lastPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
