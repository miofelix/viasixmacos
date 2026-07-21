import Foundation
import XCTest

@testable import ViaSixCore

final class RuntimeNetworkTests: XCTestCase {
    func testLiveRuntimeNetworkPolicyHasFiniteDeadlines() {
        XCTAssertEqual(RuntimeNetworkPolicy.downloadRequestTimeout, 30)
        XCTAssertEqual(RuntimeNetworkPolicy.downloadResourceTimeout, 600)

        let session = RuntimeNetworkPolicy.makeSession(
            requestTimeout: RuntimeNetworkPolicy.downloadRequestTimeout,
            resourceTimeout: RuntimeNetworkPolicy.downloadResourceTimeout
        )
        defer { session.invalidateAndCancel() }
        XCTAssertEqual(session.configuration.timeoutIntervalForRequest, 30)
        XCTAssertEqual(session.configuration.timeoutIntervalForResource, 600)
        XCTAssertFalse(session.configuration.waitsForConnectivity)
    }

    func testCancellingRuntimeArchiveDownloadStopsTheUnderlyingRequest() async throws {
        let session = makeStallingSession(requestTimeout: 30, resourceTimeout: 30)
        defer { session.invalidateAndCancel() }
        StallingURLProtocol.recorder.reset()

        let task = Task {
            try await RuntimeComponentManager.downloadUsingURLSession(
                URL(string: "https://example.invalid/archive.zip")!,
                using: session
            )
        }
        try await waitUntil { StallingURLProtocol.recorder.hasStarted }
        let clock = ContinuousClock()
        let startedAt = clock.now
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            let isCancelled =
                error is CancellationError
                || (error as? URLError)?.code == .cancelled
            XCTAssertTrue(isCancelled, "Unexpected cancellation error: \(error)")
        }
        XCTAssertLessThan(startedAt.duration(to: clock.now), .seconds(2))
        try await waitUntil { StallingURLProtocol.recorder.hasStopped }
    }

    func testRuntimeArchiveUsesTheConfiguredResourceDeadline() async throws {
        let session = makeStallingSession(requestTimeout: 30, resourceTimeout: 0.15)
        defer { session.invalidateAndCancel() }
        StallingURLProtocol.recorder.reset()

        let clock = ContinuousClock()
        let startedAt = clock.now
        do {
            _ = try await RuntimeComponentManager.downloadUsingURLSession(
                URL(string: "https://example.invalid/archive.zip")!,
                using: session
            )
            XCTFail("Expected the stalled archive download to time out")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        }

        XCTAssertLessThan(startedAt.duration(to: clock.now), .seconds(2))
        try await waitUntil { StallingURLProtocol.recorder.hasStopped }
    }

    private func makeStallingSession(
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval
    ) -> URLSession {
        RuntimeNetworkPolicy.makeSession(
            requestTimeout: requestTimeout,
            resourceTimeout: resourceTimeout,
            protocolClasses: [StallingURLProtocol.self]
        )
    }

    private func waitUntil(
        _ predicate: @escaping @Sendable () -> Bool
    ) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for network protocol state")
    }
}

private final class StallingURLProtocol: URLProtocol {
    static let recorder = ProtocolRecorder()

    override class func canInit(with _: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.recorder.markStarted()
        guard let url = request.url,
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/octet-stream"]
            )
        else {
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // Deliberately never send data or finish. URLSession's resource
        // timeout or task cancellation must close this request.
    }

    override func stopLoading() {
        Self.recorder.markStopped()
    }
}

private final class ProtocolRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    private var stopped = false

    var hasStarted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return started
    }

    var hasStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    func markStarted() {
        lock.lock()
        started = true
        lock.unlock()
    }

    func markStopped() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    func reset() {
        lock.lock()
        started = false
        stopped = false
        lock.unlock()
    }
}
