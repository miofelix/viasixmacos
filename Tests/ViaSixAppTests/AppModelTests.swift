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

    private func makeModel(
        paths: AppPaths,
        store: PreferencesStore? = nil,
        bootstrapper: AppBootstrapper? = nil
    ) -> AppModel {
        AppModel(
            paths: paths,
            preferencesStore: store ?? PreferencesStore(fileURL: paths.preferences),
            bootstrapper: bootstrapper ?? AppBootstrapper(paths: paths),
            runtimeManager: RuntimeComponentManager(paths: paths),
            exitDetector: ExitIPDetector()
        )
    }

    private func makePaths() -> AppPaths {
        AppPaths(
            root: FileManager.default.temporaryDirectory
                .appendingPathComponent("AppModelTests-\(UUID().uuidString)", isDirectory: true)
        )
    }
}
