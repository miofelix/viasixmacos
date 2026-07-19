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

    func testSaveXrayTemplateWaitsForSuccessfulWrite() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try paths.prepare()
        let model = makeModel(paths: paths)
        let openedTemplate = validTemplate()
        try openedTemplate.write(to: paths.templateConfig, options: .atomic)
        let template = validTemplate(host: "127.0.0.2", port: 18_081)

        try await model.saveXrayTemplate(template, expectedTemplateData: openedTemplate)

        XCTAssertEqual(try Data(contentsOf: paths.templateConfig), template)
        XCTAssertEqual(model.state.proxyEndpoint, ProxyEndpoint(host: "127.0.0.2", port: 18_081))
        XCTAssertEqual(model.state.templateOperationPhase, .idle)
        XCTAssertTrue(model.state.logs.contains { $0.message == "已保存代理连接模板" })
        await model.shutdown()
    }

    func testSaveXrayTemplateRejectsExternalChangeWithoutOverwritingIt() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        let openedTemplate = try Data(contentsOf: paths.templateConfig)
        let externalTemplate = validTemplate(host: "127.0.0.2", port: 18_082)
        try externalTemplate.write(to: paths.templateConfig, options: .atomic)
        let model = makeModel(paths: paths, bootstrapper: bootstrapper)

        do {
            try await model.saveXrayTemplate(
                validTemplate(host: "127.0.0.3", port: 18_083),
                expectedTemplateData: openedTemplate
            )
            XCTFail("Expected the externally changed template to be preserved")
        } catch {
            XCTAssertEqual(error as? AppModelError, .templateChangedExternally)
        }

        XCTAssertEqual(try Data(contentsOf: paths.templateConfig), externalTemplate)
        XCTAssertEqual(model.state.templateOperationPhase, .idle)
        XCTAssertTrue(model.state.logs.contains { $0.message.contains("已阻止覆盖外部修改") })
        await model.shutdown()
    }

    func testTemplateImportPublishesBusyStateAndBlocksConcurrentSave() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try paths.prepare()
        let importedTemplate = validTemplate(host: "127.0.0.4", port: 18_084)
        let importURL = paths.root.appendingPathComponent("imported-template.json")
        try importedTemplate.write(to: importURL, options: .atomic)
        let model = makeModel(paths: paths)

        model.importXrayTemplate(from: importURL)
        XCTAssertEqual(model.state.templateOperationPhase, .importing)

        do {
            try await model.saveXrayTemplate(validTemplate(port: 11_452))
            XCTFail("Expected saving to be rejected while a template import is running")
        } catch {
            XCTAssertEqual(error as? AppModelError, .templateOperationInProgress)
        }

        try await waitUntil { model.state.templateOperationPhase == .idle }
        XCTAssertEqual(try Data(contentsOf: paths.templateConfig), importedTemplate)
        XCTAssertEqual(model.state.proxyEndpoint, ProxyEndpoint(host: "127.0.0.4", port: 18_084))
        await model.shutdown()
    }

    func testSaveXrayTemplatePropagatesWriteFailure() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let model = makeModel(paths: paths)

        do {
            try await model.saveXrayTemplate(validTemplate())
            XCTFail("Expected the missing application data directory to make the save fail")
        } catch {
            XCTAssertTrue(model.state.logs.contains { $0.message.contains("保存代理配置失败") })
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.templateConfig.path))
        await model.shutdown()
    }

    func testSaveXrayTemplateRejectsOverlapAndShutdownCancelsPendingSave() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let replacer = SuspendedTemplateReplacer()
        let model = makeModel(paths: paths, templateReplacer: replacer)
        let pendingSave = Task {
            try await model.saveXrayTemplate(validTemplate())
        }
        try await waitForTemplateRequest(replacer)
        XCTAssertEqual(model.state.templateOperationPhase, .saving)

        do {
            try await model.saveXrayTemplate(validTemplate(port: 11_452))
            XCTFail("Expected a second template operation to be rejected")
        } catch {
            XCTAssertEqual(error.localizedDescription, "另一项代理配置操作尚未完成")
        }

        await model.shutdown()
        do {
            try await pendingSave.value
            XCTFail("Expected shutdown to cancel the pending template save")
        } catch is CancellationError {
            // Expected: shutdown owns and cancels the underlying save task.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
        let requestCount = await replacer.requestCount
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(model.state.templateOperationPhase, .idle)
        XCTAssertFalse(model.state.logs.contains { $0.message.contains("保存代理配置失败") })
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
        XCTAssertEqual(model.state.configurationTest.parameters?.httping, model.parameters.httping)

        model.selectIP("2606::8")
        try await waitUntil {
            model.switchingIP == nil && model.state.preferences.selectedIP == "2606::8"
        }
        XCTAssertNil(model.state.configurationTest.result)
        await model.shutdown()
    }

    func testBlankExitIPEndpointRestoresDefaultAndTrimsValidValues() async {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let model = makeModel(paths: paths)

        model.exitIPEndpoint = "  https://status.example.test/ip  "
        XCTAssertEqual(model.exitIPEndpoint, "https://status.example.test/ip")

        model.exitIPEndpoint = "   "
        XCTAssertEqual(model.exitIPEndpoint, AppMetadata.defaultExitIPEndpoint)
        await model.shutdown()
    }

    func testShutdownRejectsNewBackgroundWork() async {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let detector = ControlledExitDetector()
        let model = makeModel(paths: paths, exitDetector: detector)

        await model.shutdown()
        model.installRuntime()
        model.startSpeedTest()
        model.startCurrentConfigurationTest()
        model.detectExitIP()

        XCTAssertFalse(model.isCfstBusy)
        XCTAssertFalse(model.state.exit.isDetecting)
        XCTAssertEqual(model.state.runtimePhase, .checking)
        let requestCount = await detector.requestCount
        XCTAssertEqual(requestCount, 0)
    }

    func testStopSpeedTestDoesNotCancelCurrentConfigurationTest() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let model = try await makeSpeedTestModel(
            paths: paths,
            selectedIP: "2606::9",
            script: #"""
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
                printf 'started\n' > current-test-started.txt
                sleep 0.3
                printf 'IP,Sent,Recv,Loss,Latency,Speed,Region\n%s,4,4,0,12.5,24.0,SJC\n' "$selected_ip" > "$output"
                """#
        )

        model.startCurrentConfigurationTest()
        let markerURL = paths.root.appendingPathComponent("current-test-started.txt")
        try await waitUntil { FileManager.default.fileExists(atPath: markerURL.path) }

        model.stopSpeedTest()

        XCTAssertEqual(model.state.speedTest.phase, .idle)
        XCTAssertEqual(model.state.configurationTest.phase, .running)
        try await waitUntil { model.state.configurationTest.result != nil }
        XCTAssertEqual(model.state.configurationTest.result?.ip, "2606::9")
        XCTAssertEqual(model.state.configurationTest.result?.latency, "12.5")
        XCTAssertFalse(model.isCfstBusy)
        await model.shutdown()
    }

    func testStopSpeedTestStillCancelsFullSpeedTest() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let model = try await makeSpeedTestModel(
            paths: paths,
            selectedIP: "2606::10",
            script: #"""
                #!/bin/sh
                output=""
                while [ "$#" -gt 0 ]; do
                  if [ "$1" = "-o" ]; then output="$2"; shift 2; else shift; fi
                done
                printf 'started\n' > full-test-started.txt
                sleep 30
                printf 'IP,Sent,Recv,Loss,Latency,Speed,Region\n2606::10,4,4,0,12.5,24.0,SJC\n' > "$output"
                """#
        )

        model.startSpeedTest()
        let markerURL = paths.root.appendingPathComponent("full-test-started.txt")
        try await waitUntil { FileManager.default.fileExists(atPath: markerURL.path) }

        model.stopSpeedTest()

        XCTAssertEqual(model.state.speedTest.phase, .stopping)
        try await waitUntil { model.state.speedTest.phase == .idle }
        XCTAssertFalse(model.isCfstBusy)
        XCTAssertEqual(model.state.configurationTest.phase, .idle)
        await model.shutdown()
    }

    func testSpeedTestRequiresExplicitSelectionAndTracksParameterSnapshot() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let model = try await makeSpeedTestModel(
            paths: paths,
            selectedIP: "",
            script: #"""
                #!/bin/sh
                output=""
                while [ "$#" -gt 0 ]; do
                  if [ "$1" = "-o" ]; then output="$2"; shift 2; else shift; fi
                done
                printf 'IP,Sent,Recv,Loss,Latency,Speed,Region\n2606::11,4,4,0,10.5,28.0,SJC\n' > "$output"
                """#
        )
        let testedParameters = model.parameters

        model.startSpeedTest()
        try await waitUntil {
            model.state.results.count == 1 && model.state.speedTest.phase == .idle
        }

        XCTAssertEqual(model.state.preferences.selectedIP, "")
        let generatedIP = try await AppBootstrapper(paths: paths).currentConfigIP()
        XCTAssertNil(generatedIP)
        XCTAssertEqual(
            model.state.preferences.lastSuccessfulSpeedTestParameters,
            testedParameters
        )
        XCTAssertTrue(model.state.speedTestResultsAreCurrent)

        var changedParameters = model.parameters
        changedParameters.httping.toggle()
        model.parameters = changedParameters

        XCTAssertEqual(model.state.results.map(\.ip), ["2606::11"])
        XCTAssertFalse(model.state.speedTestResultsAreCurrent)
        XCTAssertNil(model.state.selectedResult)
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

    private func waitForTemplateRequest(_ replacer: SuspendedTemplateReplacer) async throws {
        for _ in 0..<100 {
            if await replacer.requestCount > 0 { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for the template save to start")
    }

    private func makeModel(
        paths: AppPaths,
        store: PreferencesStore? = nil,
        bootstrapper: AppBootstrapper? = nil,
        exitDetector: (any ExitIPDetecting)? = nil,
        templateReplacer: (any XrayTemplateReplacing)? = nil
    ) -> AppModel {
        AppModel(
            paths: paths,
            preferencesStore: store ?? PreferencesStore(fileURL: paths.preferences),
            bootstrapper: bootstrapper ?? AppBootstrapper(paths: paths),
            runtimeManager: RuntimeComponentManager(paths: paths),
            exitDetector: exitDetector ?? ExitIPDetector(),
            templateReplacer: templateReplacer
        )
    }

    private func makeSpeedTestModel(
        paths: AppPaths,
        selectedIP: String,
        script: String
    ) async throws -> AppModel {
        let store = PreferencesStore(fileURL: paths.preferences)
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        if !selectedIP.isEmpty {
            try await bootstrapper.writeConfig(ip: selectedIP)
        }

        let executableURL = paths.root.appendingPathComponent("cfst-test")
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
        try await store.save(
            UserPreferences(
                parameters: .defaults(ipv6File: paths.ipv6List),
                selectedIP: selectedIP,
                cfstPath: executableURL.path
            ))

        let model = makeModel(paths: paths, store: store, bootstrapper: bootstrapper)
        model.start()
        try await waitUntilReady(model)
        return model
    }

    private func makePaths() -> AppPaths {
        AppPaths(
            root: FileManager.default.temporaryDirectory
                .appendingPathComponent("AppModelTests-\(UUID().uuidString)", isDirectory: true)
        )
    }

    private func validTemplate(host: String = "127.0.0.1", port: Int = 11_451) -> Data {
        Data(
            #"""
            {
              "inbounds": [{"listen": "\#(host)", "port": \#(port), "protocol": "mixed"}],
              "outbounds": [{
                "tag": "proxy",
                "settings": {"vnext": [{
                  "address": "2001:db8::10",
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
    }
}

private actor SuspendedTemplateReplacer: XrayTemplateReplacing {
    private(set) var requestCount = 0

    func replaceTemplate(
        with _: Data,
        selectedIP _: String?,
        expectedTemplateData _: Data?
    ) async throws -> ProxyEndpoint {
        requestCount += 1
        try await Task.sleep(for: .seconds(30))
        return ProxyEndpoint()
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
