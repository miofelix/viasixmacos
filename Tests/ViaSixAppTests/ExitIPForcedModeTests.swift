import ViaSixCore
import XCTest

@testable import ViaSixApp

@MainActor
final class ExitIPForcedModeTests: XCTestCase {
    func testForcedIPv4AndIPv6ModesBothPublishDetailedGeolocation() async throws {
        let paths = AppPaths(
            root: FileManager.default.temporaryDirectory
                .appendingPathComponent("ExitIPForcedModeTests-\(UUID().uuidString)", isDirectory: true)
        )
        defer { try? FileManager.default.removeItem(at: paths.root) }

        let detector = ForcedModeExitDetector()
        let model = AppModel(
            paths: paths,
            preferencesStore: PreferencesStore(fileURL: paths.preferences),
            bootstrapper: AppBootstrapper(paths: paths),
            runtimeManager: RuntimeComponentManager(paths: paths),
            exitDetector: detector
        )

        model.exitIPDetectionMode = .ipv4
        model.detectExitIP()
        try await waitUntil {
            model.state.exit.context?.mode == .ipv4
                && model.state.exit.info?.location == "澳大利亚 · 昆士兰州 · 布里斯班"
                && !model.state.exit.isEnriching
        }
        XCTAssertEqual(
            model.state.exit.info?.details,
            "Example IPv4 Network · AS64504 · Australia/Brisbane"
        )

        model.exitIPDetectionMode = .ipv6
        model.detectExitIP()
        try await waitUntil {
            model.state.exit.context?.mode == .ipv6
                && model.state.exit.info?.location == "美国 · 加利福尼亚州 · 圣何塞"
                && !model.state.exit.isEnriching
        }

        let requests = await detector.snapshot()
        XCTAssertEqual(
            requests.detectionEndpoints,
            [AppMetadata.ipv4ExitIPEndpoint, AppMetadata.ipv6ExitIPEndpoint]
        )
        XCTAssertEqual(requests.expectedFamilies, [.ipv4, .ipv6])
        XCTAssertEqual(requests.enrichedIPs, ["198.51.100.4", "2001:db8::6"])
        XCTAssertTrue(requests.detectionProxies.allSatisfy { $0 == nil })
        XCTAssertTrue(requests.enrichmentProxies.allSatisfy { $0 == nil })
        XCTAssertEqual(
            model.state.exit.info?.details,
            "Example IPv6 Network · AS64506 · America/Los_Angeles"
        )
        XCTAssertNil(model.state.exit.errorMessage)

        await model.shutdown()
    }

    func testAutomaticIPv6ResultAlsoReceivesDetailedGeolocation() async throws {
        let paths = AppPaths(
            root: FileManager.default.temporaryDirectory
                .appendingPathComponent("ExitIPAutomaticIPv6Tests-\(UUID().uuidString)", isDirectory: true)
        )
        defer { try? FileManager.default.removeItem(at: paths.root) }

        let primary = ExitIPInfo(ip: "2001:db8::42")
        let enriched = ExitIPInfo(
            ip: primary.ip,
            location: "日本 · 东京都 · 东京 · 邮编 100-0001",
            details: "Example IPv6 Network · AS64506 · Asia/Tokyo"
        )
        let detector = ControlledAutomaticExitDetector(primary: primary)
        let model = AppModel(
            paths: paths,
            preferencesStore: PreferencesStore(fileURL: paths.preferences),
            bootstrapper: AppBootstrapper(paths: paths),
            runtimeManager: RuntimeComponentManager(paths: paths),
            exitDetector: detector
        )

        model.detectExitIP()
        try await waitUntil { model.state.exit.isEnriching }
        let pendingRequestID = await detector.enrichmentRequestID()
        let requestID = try XCTUnwrap(pendingRequestID)
        await detector.resolve(requestID, with: enriched)
        try await waitUntil {
            model.state.exit.context?.mode == .automatic
                && model.state.exit.info == enriched
                && !model.state.exit.isEnriching
        }

        let snapshot = await detector.snapshot()
        XCTAssertNil(snapshot.expectedFamily)
        XCTAssertEqual(snapshot.enrichedIP, primary.ip)
        await model.shutdown()
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for forced-mode exit IP enrichment")
        throw ExitIPForcedModeTestError.timedOut
    }
}

private actor ForcedModeExitDetector: ExitIPDetecting {
    struct Snapshot: Sendable {
        let detectionEndpoints: [String]
        let expectedFamilies: [IPAddressFamily]
        let enrichedIPs: [String]
        let detectionProxies: [ProxyEndpoint?]
        let enrichmentProxies: [ProxyEndpoint?]
    }

    private var detectionEndpoints: [String] = []
    private var expectedFamilies: [IPAddressFamily] = []
    private var enrichedIPs: [String] = []
    private var detectionProxies: [ProxyEndpoint?] = []
    private var enrichmentProxies: [ProxyEndpoint?] = []

    func detect(
        proxy: ProxyEndpoint?,
        endpoint: URL?,
        expectedFamily: IPAddressFamily?
    ) async throws -> ExitIPInfo {
        detectionProxies.append(proxy)
        detectionEndpoints.append(endpoint?.absoluteString ?? "")
        guard let expectedFamily else {
            throw ExitIPForcedModeTestError.missingExpectedFamily
        }
        expectedFamilies.append(expectedFamily)

        switch expectedFamily {
        case .ipv4:
            return ExitIPInfo(ip: "198.51.100.4")
        case .ipv6:
            return ExitIPInfo(ip: "2001:db8::6")
        }
    }

    func enrich(_ info: ExitIPInfo, proxy: ProxyEndpoint?) async throws -> ExitIPInfo {
        enrichmentProxies.append(proxy)
        enrichedIPs.append(info.ip)
        switch info.addressFamily {
        case .ipv4:
            return ExitIPInfo(
                ip: info.ip,
                location: "澳大利亚 · 昆士兰州 · 布里斯班",
                details: "Example IPv4 Network · AS64504 · Australia/Brisbane"
            )
        case .ipv6:
            return ExitIPInfo(
                ip: info.ip,
                location: "美国 · 加利福尼亚州 · 圣何塞",
                details: "Example IPv6 Network · AS64506 · America/Los_Angeles"
            )
        case nil:
            throw ExitIPForcedModeTestError.invalidIPAddress
        }
    }

    func snapshot() -> Snapshot {
        Snapshot(
            detectionEndpoints: detectionEndpoints,
            expectedFamilies: expectedFamilies,
            enrichedIPs: enrichedIPs,
            detectionProxies: detectionProxies,
            enrichmentProxies: enrichmentProxies
        )
    }
}

private actor ControlledAutomaticExitDetector: ExitIPDetecting {
    struct Snapshot: Sendable {
        let expectedFamily: IPAddressFamily?
        let enrichedIP: String?
    }

    private let primary: ExitIPInfo
    private var expectedFamily: IPAddressFamily?
    private var enrichedIP: String?
    private var enrichmentID: UUID?
    private var enrichmentContinuation: CheckedContinuation<ExitIPInfo, any Error>?

    init(primary: ExitIPInfo) {
        self.primary = primary
    }

    func detect(
        proxy _: ProxyEndpoint?,
        endpoint _: URL?,
        expectedFamily: IPAddressFamily?
    ) async throws -> ExitIPInfo {
        self.expectedFamily = expectedFamily
        return primary
    }

    func enrich(_ info: ExitIPInfo, proxy _: ProxyEndpoint?) async throws -> ExitIPInfo {
        let id = UUID()
        enrichedIP = info.ip
        enrichmentID = id
        return try await withCheckedThrowingContinuation { continuation in
            enrichmentContinuation = continuation
        }
    }

    func enrichmentRequestID() -> UUID? {
        enrichmentID
    }

    func resolve(_ id: UUID, with info: ExitIPInfo) {
        guard id == enrichmentID, let continuation = enrichmentContinuation else { return }
        enrichmentContinuation = nil
        continuation.resume(returning: info)
    }

    func snapshot() -> Snapshot {
        Snapshot(expectedFamily: expectedFamily, enrichedIP: enrichedIP)
    }
}

private enum ExitIPForcedModeTestError: Error {
    case timedOut
    case missingExpectedFamily
    case invalidIPAddress
}
