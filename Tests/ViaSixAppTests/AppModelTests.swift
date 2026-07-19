import ViaSixCore
import XCTest

@testable import ViaSixApp

@MainActor
final class AppModelTests: XCTestCase {
    func testBootstrapTreatsGeneratedConfigAsTheActiveNode() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let store = PreferencesStore(fileURL: paths.preferences)
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        try await bootstrapper.writeConfig(ip: "2606::2")
        try await store.save(
            UserPreferences(
                parameters: .defaults(ipv6File: paths.ipv6List),
                selectedIP: "2606::1"
            ))

        let model = AppModel(
            paths: paths,
            preferencesStore: store,
            bootstrapper: bootstrapper,
            runtimeManager: RuntimeComponentManager(paths: paths),
            exitDetector: ExitIPDetector()
        )
        model.start()
        try await waitUntilReady(model)

        XCTAssertEqual(model.state.preferences.selectedIP, "2606::2")
        await model.shutdown()
    }

    func testBootstrapRegeneratesMissingConfigFromPersistedSelection() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let store = PreferencesStore(fileURL: paths.preferences)
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        try await store.save(
            UserPreferences(
                parameters: .defaults(ipv6File: paths.ipv6List),
                selectedIP: "2606::3"
            ))

        let model = AppModel(
            paths: paths,
            preferencesStore: store,
            bootstrapper: bootstrapper,
            runtimeManager: RuntimeComponentManager(paths: paths),
            exitDetector: ExitIPDetector()
        )
        model.start()
        try await waitUntilReady(model)

        let currentIP = try await bootstrapper.currentConfigIP()
        XCTAssertEqual(currentIP, "2606::3")
        await model.shutdown()
    }

    func testBootstrapIgnoresCorruptCachedResults() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        try Data("IP,Sent,Recv\n\"unterminated".utf8).write(to: paths.resultCSV)

        let model = makeModel(paths: paths, bootstrapper: bootstrapper)
        model.start()
        try await waitUntilReady(model)

        XCTAssertTrue(model.state.results.isEmpty)
        XCTAssertTrue(model.state.logs.contains { $0.message.contains("损坏的历史测速结果") })
        await model.shutdown()
    }

    func testBootstrapAllowsRepairingCorruptProxyTemplate() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let store = PreferencesStore(fileURL: paths.preferences)
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        try Data("not json".utf8).write(to: paths.templateConfig, options: .atomic)
        try await store.save(
            UserPreferences(
                parameters: .defaults(ipv6File: paths.ipv6List),
                selectedIP: "2606::4"
            ))

        let model = makeModel(paths: paths, store: store, bootstrapper: bootstrapper)
        model.start()
        try await waitUntilReady(model)

        XCTAssertEqual(model.state.preferences.selectedIP, "2606::4")
        XCTAssertTrue(model.state.logs.contains { $0.message.contains("代理配置需要修复") })
        await model.shutdown()
    }

    func testBootstrapUsesProxyEndpointFromTemplate() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        let template = Data(
            #"""
            {
              "inbounds": [{"listen": "127.0.0.2", "port": 18080, "protocol": "mixed"}],
              "outbounds": [{
                "tag": "proxy",
                "settings": {"vnext": [{
                  "address": "2606::5",
                  "users": [{"id": "7b602ceb-cc3f-4274-a79d-c1a38f0fb0da"}]
                }]},
                "streamSettings": {
                  "tlsSettings": {"serverName": "proxy.example.net"},
                  "wsSettings": {"host": "proxy.example.net", "path": "/viasix"}
                }
              }]
            }
            """#.utf8
        )
        try await bootstrapper.replaceTemplate(with: template)

        let model = makeModel(paths: paths, bootstrapper: bootstrapper)
        model.start()
        try await waitUntilReady(model)

        XCTAssertEqual(model.state.proxyEndpoint, ProxyEndpoint(host: "127.0.0.2", port: 18_080))
        await model.shutdown()
    }

    func testCurrentConfigurationTestUsesSelectedIPAndExpiresAfterSelectionChanges() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let store = PreferencesStore(fileURL: paths.preferences)
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        try await bootstrapper.writeConfig(ip: "2606::7")

        let executableURL = paths.root.appendingPathComponent("cfst-test")
        try #"""
        #!/bin/sh
        output=""
        selected_ip=""
        while [ "$#" -gt 0 ]; do
          case "$1" in
            -o) output="$2"; shift 2 ;;
            -ip) selected_ip="$2"; shift 2 ;;
            *) shift ;;
          esac
        done
        printf 'IP,Sent,Recv,Loss,Latency,Speed,Region\n%s,4,4,0.00,18.5,12.3,SJC\n' "$selected_ip" > "$output"
        """#.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
        try await store.save(
            UserPreferences(
                parameters: .defaults(ipv6File: paths.ipv6List),
                selectedIP: "2606::7",
                cfstPath: executableURL.path
            ))

        let model = makeModel(paths: paths, store: store, bootstrapper: bootstrapper)
        model.start()
        try await waitUntilReady(model)

        model.startCurrentConfigurationTest()
        try await waitUntil { model.state.configurationTest.result != nil }
        XCTAssertEqual(model.state.configurationTest.result?.ip, "2606::7")
        XCTAssertEqual(model.state.configurationTest.result?.latency, "18.5")

        model.selectIP("2606::8")
        try await waitUntil {
            model.switchingIP == nil && model.state.preferences.selectedIP == "2606::8"
        }
        XCTAssertNil(model.state.configurationTest.result)
        await model.shutdown()
    }

    func testExitIPDetectionStoresDirectContextAndPreservesResultWhenModeChanges() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let detector = ControlledExitDetector()
        let model = makeModel(paths: paths, exitDetector: detector)

        model.detectExitIP()
        try await waitForRequestCount(detector, 1)
        let pendingRequestID = await detector.requestID(at: 0)
        let requestID = try XCTUnwrap(pendingRequestID)
        await detector.resolve(
            requestID,
            with: .success(ExitIPInfo(ip: "203.0.113.10", location: "东京 日本", details: "Example ISP · AS64500"))
        )
        try await waitUntil {
            model.state.exit.info?.ip == "203.0.113.10" && !model.state.exit.isDetecting
        }

        XCTAssertEqual(model.exitIPRouteDescription, "直连")
        XCTAssertFalse(model.exitIPResultIsStale)
        XCTAssertEqual(model.state.exit.context?.mode, .automatic)
        XCTAssertNotNil(model.state.exit.detectedAt)

        model.exitIPDetectionMode = .ipv4
        XCTAssertEqual(model.state.exit.info?.ip, "203.0.113.10")
        XCTAssertTrue(model.exitIPResultIsStale)
        await model.shutdown()
    }

    func testExitIPDetectionDropsCancelledGeneration() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let detector = ControlledExitDetector()
        let model = makeModel(paths: paths, exitDetector: detector)

        model.detectExitIP()
        try await waitForRequestCount(detector, 1)
        let pendingFirstID = await detector.requestID(at: 0)
        let firstID = try XCTUnwrap(pendingFirstID)

        model.exitIPDetectionMode = .ipv4
        model.detectExitIP()
        try await waitForRequestCount(detector, 2)
        let pendingSecondID = await detector.requestID(at: 1)
        let secondID = try XCTUnwrap(pendingSecondID)
        await detector.resolve(
            secondID,
            with: .success(ExitIPInfo(ip: "198.51.100.20", location: "新加坡", details: "Example ISP"))
        )
        try await waitUntil {
            model.state.exit.info?.ip == "198.51.100.20" && !model.state.exit.isDetecting
        }

        // The first detector intentionally ignores cancellation. Its late
        // response must not replace the result from the current generation.
        await detector.resolve(
            firstID,
            with: .success(ExitIPInfo(ip: "198.51.100.30", location: "旧结果"))
        )
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(model.state.exit.info?.ip, "198.51.100.20")
        XCTAssertEqual(model.state.exit.context?.mode, .ipv4)
        await model.shutdown()
    }

    func testExitIPDetectionFailureKeepsLastSuccessfulSnapshot() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let detector = ControlledExitDetector()
        let model = makeModel(paths: paths, exitDetector: detector)

        model.detectExitIP()
        try await waitForRequestCount(detector, 1)
        let pendingFirstID = await detector.requestID(at: 0)
        let firstID = try XCTUnwrap(pendingFirstID)
        await detector.resolve(
            firstID,
            with: .success(ExitIPInfo(ip: "192.0.2.40", location: "大阪 日本", details: "Example ISP"))
        )
        try await waitUntil {
            model.state.exit.info?.ip == "192.0.2.40" && !model.state.exit.isDetecting
        }
        let detectedAt = try XCTUnwrap(model.state.exit.detectedAt)

        model.detectExitIP()
        try await waitForRequestCount(detector, 2)
        let pendingSecondID = await detector.requestID(at: 1)
        let secondID = try XCTUnwrap(pendingSecondID)
        await detector.resolve(secondID, with: .failure(.unavailable))
        try await waitUntil {
            model.state.exit.errorMessage != nil && !model.state.exit.isDetecting
        }

        XCTAssertEqual(model.state.exit.info?.ip, "192.0.2.40")
        XCTAssertEqual(model.state.exit.detectedAt, detectedAt)
        await model.shutdown()
    }

    private func waitUntilReady(_ model: AppModel) async throws {
        for _ in 0..<100 {
            if model.state.launchPhase == .ready { return }
            if case .failed(let message) = model.state.launchPhase {
                XCTFail("Bootstrap failed: \(message)")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for bootstrap")
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for condition")
    }

    private func waitForRequestCount(
        _ detector: ControlledExitDetector,
        _ count: Int
    ) async throws {
        for _ in 0..<100 {
            if await detector.requestCount >= count { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for \(count) exit IP requests")
    }

    private func makeModel(
        paths: AppPaths,
        store: PreferencesStore? = nil,
        bootstrapper: AppBootstrapper? = nil,
        exitDetector: (any ExitIPDetecting)? = nil
    ) -> AppModel {
        AppModel(
            paths: paths,
            preferencesStore: store ?? PreferencesStore(fileURL: paths.preferences),
            bootstrapper: bootstrapper ?? AppBootstrapper(paths: paths),
            runtimeManager: RuntimeComponentManager(paths: paths),
            exitDetector: exitDetector ?? ExitIPDetector()
        )
    }

    private func makePaths() -> AppPaths {
        AppPaths(
            root: FileManager.default.temporaryDirectory
                .appendingPathComponent("AppModelTests-\(UUID().uuidString)", isDirectory: true)
        )
    }
}

private actor ControlledExitDetector: ExitIPDetecting {
    enum Resolution: Sendable {
        case success(ExitIPInfo)
        case failure(StubError)
    }

    enum StubError: Error, LocalizedError, Sendable {
        case unavailable

        var errorDescription: String? {
            "检测服务暂不可用"
        }
    }

    private struct Request: Sendable {
        let id: UUID
    }

    private var requests: [Request] = []
    private var continuations: [UUID: CheckedContinuation<ExitIPInfo, any Error>] = [:]

    var requestCount: Int { requests.count }

    func requestID(at index: Int) -> UUID? {
        guard requests.indices.contains(index) else { return nil }
        return requests[index].id
    }

    func detect(
        proxy: ProxyEndpoint?,
        endpoint: URL?,
        expectedFamily: IPAddressFamily?
    ) async throws -> ExitIPInfo {
        let id = UUID()
        requests.append(Request(id: id))
        return try await withCheckedThrowingContinuation { continuation in
            continuations[id] = continuation
        }
    }

    func resolve(_ id: UUID, with resolution: Resolution) {
        guard let continuation = continuations.removeValue(forKey: id) else { return }
        switch resolution {
        case .success(let info):
            continuation.resume(returning: info)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
