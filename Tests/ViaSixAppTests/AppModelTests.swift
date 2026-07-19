import XCTest
@testable import ViaSixApp
import ViaSixCore

@MainActor
final class AppModelTests: XCTestCase {
    func testBootstrapTreatsGeneratedConfigAsTheActiveNode() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let store = PreferencesStore(fileURL: paths.preferences)
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        try await bootstrapper.writeConfig(ip: "2606::2")
        try await store.save(UserPreferences(
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
        try await store.save(UserPreferences(
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

    private func makePaths() -> AppPaths {
        AppPaths(
            root: FileManager.default.temporaryDirectory
                .appendingPathComponent("AppModelTests-\(UUID().uuidString)", isDirectory: true)
        )
    }
}
