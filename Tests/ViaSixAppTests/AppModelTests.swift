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

    func testBootstrapBacksUpCorruptPreferencesAndRecordsWarning() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try paths.prepare()
        let corruptData = Data("not valid preferences json".utf8)
        try corruptData.write(to: paths.preferences, options: .atomic)
        let model = makeModel(paths: paths)

        model.start()
        try await waitUntilReady(model)

        XCTAssertEqual(model.state.preferences.selectedIP, "")
        XCTAssertTrue(
            model.state.logs.contains {
                $0.level == .warning
                    && $0.message.contains("偏好文件无法解析")
                    && $0.message.contains("preferences.corrupt-")
                    && $0.message.contains("本次使用默认设置")
            }
        )
        let backups = try corruptPreferenceBackups(in: paths)
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), corruptData)
        await model.shutdown()
    }

    func testBootstrapFailsOnPreferencesReadErrorWithoutOverwritingOriginal() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try paths.prepare()
        try FileManager.default.createDirectory(
            at: paths.preferences,
            withIntermediateDirectories: false
        )
        let model = makeModel(paths: paths)

        model.start()
        try await waitUntil {
            if case .failed = model.state.launchPhase { return true }
            return false
        }

        guard case .failed(let message) = model.state.launchPhase else {
            return XCTFail("Expected bootstrap to fail")
        }
        XCTAssertTrue(message.contains("无法读取偏好文件"))
        await model.shutdown()

        var isDirectory: ObjCBool = false
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: paths.preferences.path,
                isDirectory: &isDirectory
            )
        )
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertTrue(try corruptPreferenceBackups(in: paths).isEmpty)
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
        XCTAssertTrue(model.isProxyConfigurationReady)
        XCTAssertNil(model.proxyConfigurationIssue)
        await model.shutdown()
    }

    func testBootstrapRebuildsGeneratedConfigWhenTemplateDetailsChanged() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        let firstTemplate = validTemplate(
            host: "127.0.0.2",
            port: 18_080,
            userID: "f4edc501-056c-4572-9da8-ad63a264a698",
            serverName: "first.example.net",
            path: "/first"
        )
        try await bootstrapper.replaceTemplate(with: firstTemplate, selectedIP: "2606::5")
        let secondTemplate = validTemplate(
            host: "127.0.0.3",
            port: 18_081,
            userID: "22de5d8d-17f7-40e8-a83f-567ae87c865a",
            serverName: "second.example.net",
            path: "/second"
        )
        try secondTemplate.write(to: paths.templateConfig, options: .atomic)

        let model = makeModel(paths: paths, bootstrapper: bootstrapper)
        model.start()
        try await waitUntilReady(model)

        let generated = String(
            decoding: try Data(contentsOf: paths.generatedConfig),
            as: UTF8.self
        )
        XCTAssertEqual(model.state.proxyEndpoint, ProxyEndpoint(host: "127.0.0.3", port: 18_081))
        XCTAssertTrue(generated.contains("22de5d8d-17f7-40e8-a83f-567ae87c865a"))
        XCTAssertTrue(generated.contains("second.example.net"))
        XCTAssertTrue(generated.contains("/second"))
        XCTAssertFalse(generated.contains("f4edc501-056c-4572-9da8-ad63a264a698"))
        await model.shutdown()
    }

    func testDefaultConnectionTemplateIsMarkedBeforeStartAndOffersSettingsRecovery() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let store = PreferencesStore(fileURL: paths.preferences)
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()

        let executableURL = paths.root.appendingPathComponent("xray-test")
        let invocationMarkerURL = paths.root.appendingPathComponent("xray-invoked.txt")
        try #"""
        #!/bin/sh
        touch xray-invoked.txt
        exit 0
        """#.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
        try await store.save(
            UserPreferences(
                parameters: .defaults(ipv6File: paths.ipv6List),
                selectedIP: "2606::6",
                xrayPath: executableURL.path
            ))

        let model = makeModel(paths: paths, store: store, bootstrapper: bootstrapper)
        model.start()
        try await waitUntilReady(model)
        XCTAssertTrue(model.hasXrayExecutable)
        XCTAssertEqual(
            model.proxyConfigurationIssue,
            ConfigTemplateError.connectionNotConfigured.localizedDescription
        )
        XCTAssertFalse(model.isProxyConfigurationReady)

        model.startXray()
        XCTAssertEqual(model.state.xrayPhase, .stopped)
        XCTAssertEqual(model.state.notice?.action, .openSettings)
        XCTAssertFalse(FileManager.default.fileExists(atPath: invocationMarkerURL.path))
        XCTAssertTrue(
            model.state.notice?.message.contains(
                ConfigTemplateError.connectionNotConfigured.localizedDescription
            ) == true
        )
        await model.shutdown()
    }

    func testRoutingModeCanSwitchToDirectWithoutServerOrSelectedNode() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        let model = makeModel(paths: paths, bootstrapper: bootstrapper)
        model.start()
        try await waitUntilReady(model)
        XCTAssertFalse(model.isProxyConfigurationReady)

        model.setRoutingMode(.direct)
        try await waitUntil {
            !model.isRoutingModeChanging
                && model.state.localProxyConfiguration.routingMode == .direct
        }

        XCTAssertTrue(model.isProxyConfigurationReady)
        XCTAssertFalse(model.requiresSelectedNodeForProxy)
        let stored = try await bootstrapper.loadLocalProxyConfiguration()
        XCTAssertEqual(stored.routingMode, .direct)
        await model.shutdown()
    }

    func testDirectModeStartsWithoutSelectedNodeAndSystemProxyFollowsLifecycle() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let store = PreferencesStore(fileURL: paths.preferences)
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        _ = try await bootstrapper.replaceLocalProxyConfiguration(
            with: LocalProxyConfiguration(routingMode: .direct),
            selectedIP: nil
        )
        let executableURL = try makeExecutable(in: paths)
        try await store.save(
            UserPreferences(
                parameters: .defaults(ipv6File: paths.ipv6List),
                selectedIP: "",
                xrayPath: executableURL.path
            ))
        let systemProxy = ControlledSystemProxyManager()
        let xray = ControlledXrayController()
        let model = makeModel(
            paths: paths,
            store: store,
            bootstrapper: bootstrapper,
            systemProxyManager: systemProxy,
            xrayControllerFactory: { _ in xray }
        )
        model.start()
        try await waitUntilReady(model)

        model.setSystemProxyEnabled(true)
        try await waitUntil {
            model.state.localProxyConfiguration.systemProxyEnabled
        }
        let activeBeforeStart = await systemProxy.isActive
        let storedBeforeStart = try await bootstrapper.loadLocalProxyConfiguration()
        XCTAssertFalse(activeBeforeStart)
        XCTAssertTrue(storedBeforeStart.systemProxyEnabled)

        model.startXray()
        try await waitUntilAsync {
            let enableCount = await systemProxy.enableCount
            return model.state.xrayPhase == .running
                && model.state.systemProxyPhase == .enabled
                && enableCount == 1
        }

        XCTAssertEqual(model.state.preferences.selectedIP, "")
        XCTAssertNil(ConfigTemplate.address(in: try Data(contentsOf: paths.generatedConfig)))
        let lastEndpoint = await systemProxy.lastEndpoint
        XCTAssertEqual(lastEndpoint, model.state.proxyEndpoint)

        model.stopXray()
        try await waitUntilAsync {
            let disableCount = await systemProxy.disableCount
            return model.state.xrayPhase == .stopped
                && model.state.systemProxyPhase == .disabled
                && disableCount == 1
        }
        let activeAfterStop = await systemProxy.isActive
        XCTAssertFalse(activeAfterStop)
        await model.shutdown()
    }

    func testSystemProxyEnableFailureStopsTheStartedProxy() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let store = PreferencesStore(fileURL: paths.preferences)
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        _ = try await bootstrapper.replaceLocalProxyConfiguration(
            with: LocalProxyConfiguration(
                routingMode: .direct,
                systemProxyEnabled: true
            ),
            selectedIP: nil
        )
        let executableURL = try makeExecutable(in: paths)
        try await store.save(
            UserPreferences(
                parameters: .defaults(ipv6File: paths.ipv6List),
                xrayPath: executableURL.path
            ))
        let systemProxy = ControlledSystemProxyManager(enableFailure: .permissionDenied)
        let xray = ControlledXrayController()
        let model = makeModel(
            paths: paths,
            store: store,
            bootstrapper: bootstrapper,
            systemProxyManager: systemProxy,
            xrayControllerFactory: { _ in xray }
        )
        model.start()
        try await waitUntilReady(model)

        model.startXray()
        try await waitUntil {
            if case .failed = model.state.xrayPhase { return true }
            return false
        }

        let enableCount = await systemProxy.enableCount
        let stopCount = await xray.stopCount
        let xrayIsRunning = await xray.isRunning
        XCTAssertEqual(enableCount, 1)
        XCTAssertEqual(stopCount, 1)
        XCTAssertFalse(xrayIsRunning)
        guard case .failed(let message) = model.state.systemProxyPhase else {
            return XCTFail("Expected the system proxy failure to remain visible")
        }
        XCTAssertTrue(message.contains("权限"))
        await model.shutdown()
    }

    func testUnexpectedProxyExitRestoresSystemProxy() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let store = PreferencesStore(fileURL: paths.preferences)
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        _ = try await bootstrapper.replaceLocalProxyConfiguration(
            with: LocalProxyConfiguration(
                routingMode: .direct,
                systemProxyEnabled: true
            ),
            selectedIP: nil
        )
        let executableURL = try makeExecutable(in: paths)
        try await store.save(
            UserPreferences(
                parameters: .defaults(ipv6File: paths.ipv6List),
                xrayPath: executableURL.path
            ))
        let systemProxy = ControlledSystemProxyManager()
        let xray = ControlledXrayController()
        let model = makeModel(
            paths: paths,
            store: store,
            bootstrapper: bootstrapper,
            systemProxyManager: systemProxy,
            xrayControllerFactory: { _ in xray }
        )
        model.start()
        try await waitUntilReady(model)
        model.startXray()
        try await waitUntilAsync {
            let enableCount = await systemProxy.enableCount
            return model.state.systemProxyPhase == .enabled
                && enableCount == 1
        }

        await xray.exitUnexpectedly()
        try await waitUntilAsync {
            let disableCount = await systemProxy.disableCount
            if case .failed = model.state.xrayPhase {
                return model.state.systemProxyPhase == .disabled
                    && disableCount == 1
            }
            return false
        }

        let activeAfterExit = await systemProxy.isActive
        XCTAssertFalse(activeAfterExit)
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
        XCTAssertTrue(model.isProxyConfigurationReady)
        XCTAssertNil(model.state.templateOperationError)
        await model.shutdown()
    }

    func testFailedTemplateImportPublishesSettingsVisibleError() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        let model = makeModel(paths: paths, bootstrapper: bootstrapper)
        model.start()
        try await waitUntilReady(model)
        let originalTemplate = try Data(contentsOf: paths.templateConfig)
        let importURL = paths.root.appendingPathComponent("invalid-template.json")
        try Data("not json".utf8).write(to: importURL, options: .atomic)

        model.importXrayTemplate(from: importURL)
        try await waitUntil { model.state.templateOperationPhase == .idle }

        XCTAssertEqual(
            model.state.templateOperationError,
            ConfigTemplateError.invalidJSON.localizedDescription
        )
        XCTAssertEqual(try Data(contentsOf: paths.templateConfig), originalTemplate)
        XCTAssertFalse(model.isProxyConfigurationReady)
        await model.shutdown()
    }

    func testTemplateOperationsAreRejectedWhileApplyingSelection() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        let model = makeModel(paths: paths, bootstrapper: bootstrapper)
        let importURL = paths.root.appendingPathComponent("imported-template.json")
        try validTemplate().write(to: importURL, options: .atomic)

        model.selectIP("2606::12")
        model.importXrayTemplate(from: importURL)
        XCTAssertEqual(model.state.templateOperationPhase, .idle)

        do {
            try await model.saveXrayTemplate(validTemplate(port: 11_452))
            XCTFail("Expected saving to be rejected while a selection is being applied")
        } catch {
            XCTAssertEqual(error as? AppModelError, .selectionInProgress)
        }

        try await waitUntil { model.switchingIP == nil }
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

        var configuredParameters = model.parameters
        configuredParameters.httping = false
        configuredParameters.port = 8443
        configuredParameters.url = "https://speed.example.test/file"
        configuredParameters.latencyLowerBound = 900
        configuredParameters.latencyUpperBound = 901
        configuredParameters.lossRateUpperBound = 0
        configuredParameters.speedLowerBound = 999
        configuredParameters.colo = "NRT"
        model.parameters = configuredParameters

        model.startCurrentConfigurationTest()
        try await waitUntil { model.state.configurationTest.result != nil }
        XCTAssertEqual(model.state.configurationTest.result?.ip, "2606::7")
        XCTAssertEqual(model.state.configurationTest.result?.latency, "18.5")
        XCTAssertEqual(model.state.configurationTest.parameters?.httping, model.parameters.httping)
        XCTAssertEqual(model.state.configurationTest.parameters?.port, 8443)
        XCTAssertEqual(model.state.configurationTest.parameters?.url, "https://speed.example.test/file")
        XCTAssertEqual(model.state.configurationTest.parameters?.latencyLowerBound, 0)
        XCTAssertEqual(model.state.configurationTest.parameters?.latencyUpperBound, 999_999)
        XCTAssertEqual(model.state.configurationTest.parameters?.lossRateUpperBound, 1)
        XCTAssertEqual(model.state.configurationTest.parameters?.speedLowerBound, 0)
        XCTAssertEqual(model.state.configurationTest.parameters?.colo, "")
        XCTAssertNotNil(model.state.configurationTest.completedAt)

        model.selectIP("2606::8")
        try await waitUntil {
            model.switchingIP == nil && model.state.preferences.selectedIP == "2606::8"
        }
        XCTAssertNil(model.state.configurationTest.result)
        await model.shutdown()
    }

    func testCurrentConfigurationTestRejectsResultForAnotherIPAndClearsPreviousState() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let model = try await makeSpeedTestModel(
            paths: paths,
            selectedIP: "2606::12",
            script: #"""
                #!/bin/sh
                output=""
                while [ "$#" -gt 0 ]; do
                  case "$1" in
                    -o) output="$2"; shift 2 ;;
                    *) shift ;;
                  esac
                done
                printf 'IP,Sent,Recv,Loss,Latency,Speed,Region\n2606::12,4,4,0,18.5,12.3,SJC\n' > "$output"
                """#
        )

        model.startCurrentConfigurationTest()
        try await waitUntil { model.state.configurationTest.result != nil }
        XCTAssertNotNil(model.state.configurationTest.completedAt)

        let executableURL = URL(fileURLWithPath: model.state.preferences.cfstPath)
        try #"""
        #!/bin/sh
        output=""
        while [ "$#" -gt 0 ]; do
          case "$1" in
            -o) output="$2"; shift 2 ;;
            *) shift ;;
          esac
        done
        printf 'IP,Sent,Recv,Loss,Latency,Speed,Region\n2606::99,4,4,0,18.5,12.3,SJC\n' > "$output"
        """#.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        model.startCurrentConfigurationTest()
        XCTAssertEqual(model.state.configurationTest.phase, .running)
        XCTAssertNil(model.state.configurationTest.result)
        XCTAssertNil(model.state.configurationTest.completedAt)
        try await waitUntil {
            if case .failed = model.state.configurationTest.phase { return true }
            return false
        }

        XCTAssertNil(model.state.configurationTest.result)
        XCTAssertNil(model.state.configurationTest.completedAt)
        XCTAssertTrue(model.state.notice?.message.contains("与当前配置不一致") == true)
        XCTAssertTrue(model.state.logs.contains { $0.message.contains("当前节点测速失败") })
        await model.shutdown()
    }

    func testCurrentConfigurationTestAcceptsEquivalentIPv6AndPreservesSelectedSpelling() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let selectedIP = "2606:0000:0000:0000:0000:0000:0000:0007"
        let model = try await makeSpeedTestModel(
            paths: paths,
            selectedIP: selectedIP,
            script: #"""
                #!/bin/sh
                output=""
                while [ "$#" -gt 0 ]; do
                  if [ "$1" = "-o" ]; then output="$2"; shift 2; else shift; fi
                done
                printf 'IP,Sent,Recv,Loss,Latency,Speed,Region\n2606::7,4,4,0,18.5,12.3,SJC\n' > "$output"
                """#
        )

        model.startCurrentConfigurationTest()
        try await waitUntil { model.state.configurationTest.result != nil }

        XCTAssertEqual(model.state.configurationTest.result?.ip, selectedIP)
        XCTAssertEqual(model.state.configurationTest.result?.latency, "18.5")
        await model.shutdown()
    }

    func testConfigurationTestPresentationOmitsMissingUnits() {
        let result = SpeedTestResult(ip: "2606::13", latency: "", speed: "")
        XCTAssertNil(result.latencyDisplayValue)
        XCTAssertNil(result.speedDisplayValue)
        XCTAssertEqual(result.performanceSummary, "暂无有效测速指标")

        let partial = SpeedTestResult(ip: "2606::13", latency: " 18.5 ", speed: "")
        XCTAssertEqual(partial.latencyDisplayValue, "18.5 ms")
        XCTAssertEqual(partial.performanceSummary, "18.5 ms")
    }

    func testStopCurrentConfigurationTestReturnsToCleanIdleState() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let model = try await makeSpeedTestModel(
            paths: paths,
            selectedIP: "2606::14",
            script: #"""
                #!/bin/sh
                output=""
                while [ "$#" -gt 0 ]; do
                  if [ "$1" = "-o" ]; then output="$2"; shift 2; else shift; fi
                done
                printf 'started\n' > current-test-cancel-started.txt
                sleep 30
                printf 'IP,Sent,Recv,Loss,Latency,Speed,Region\n2606::14,4,4,0,12.5,24.0,SJC\n' > "$output"
                """#
        )

        model.startCurrentConfigurationTest()
        let markerURL = paths.root.appendingPathComponent("current-test-cancel-started.txt")
        try await waitUntil { FileManager.default.fileExists(atPath: markerURL.path) }

        model.stopCurrentConfigurationTest()
        XCTAssertEqual(model.state.configurationTest.phase, .stopping)
        try await waitUntil { model.state.configurationTest.phase == .idle }

        XCTAssertFalse(model.isCfstBusy)
        XCTAssertNil(model.state.configurationTest.result)
        XCTAssertNil(model.state.configurationTest.startedAt)
        XCTAssertNil(model.state.configurationTest.completedAt)
        await model.shutdown()
    }

    func testChangingParametersCancelsCurrentConfigurationTestWithoutLateResult() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let model = try await makeSpeedTestModel(
            paths: paths,
            selectedIP: "2606::15",
            script: #"""
                #!/bin/sh
                output=""
                while [ "$#" -gt 0 ]; do
                  if [ "$1" = "-o" ]; then output="$2"; shift 2; else shift; fi
                done
                printf 'started\n' > current-test-parameter-change-started.txt
                sleep 30
                printf 'IP,Sent,Recv,Loss,Latency,Speed,Region\n2606::15,4,4,0,12.5,24.0,SJC\n' > "$output"
                """#
        )

        model.startCurrentConfigurationTest()
        let markerURL = paths.root.appendingPathComponent(
            "current-test-parameter-change-started.txt"
        )
        try await waitUntil { FileManager.default.fileExists(atPath: markerURL.path) }

        var parameters = model.parameters
        parameters.threads += 1
        model.parameters = parameters

        try await waitUntil { model.state.configurationTest.phase == .idle }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(model.isCfstBusy)
        XCTAssertNil(model.state.configurationTest.result)
        XCTAssertNil(model.state.configurationTest.parameters)
        XCTAssertNil(model.state.configurationTest.completedAt)
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

    func testSpeedTestEntryPointsRejectRequestsBeforeBootstrapIsReady() async {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let model = makeModel(paths: paths)
        model.start()

        model.startSpeedTest()
        XCTAssertEqual(model.state.notice?.message, "应用仍在准备，请稍后再试")
        XCTAssertFalse(model.isCfstBusy)
        XCTAssertEqual(model.state.speedTest.phase, .idle)

        model.startCurrentConfigurationTest()
        XCTAssertEqual(model.state.notice?.message, "应用仍在准备，请稍后再试")
        XCTAssertFalse(model.isCfstBusy)
        XCTAssertEqual(model.state.configurationTest.phase, .idle)

        model.importXrayTemplate(
            from: paths.root.appendingPathComponent("not-ready-template.json")
        )
        XCTAssertEqual(model.state.notice?.message, "应用仍在准备，请稍后再试")

        model.selectIP("2606::9")
        XCTAssertEqual(model.state.notice?.message, "应用仍在准备，请稍后再试")

        do {
            try await model.saveXrayTemplate(Data("{}".utf8))
            XCTFail("Expected template save to be rejected before bootstrap")
        } catch let error as AppModelError {
            XCTAssertEqual(error, .appNotReady)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        await model.shutdown()
    }

    func testInvalidSpeedTestSourceIsReportedBeforeLaunchingCFST() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let model = try await makeSpeedTestModel(
            paths: paths,
            selectedIP: "",
            script: "#!/bin/sh\nexit 0\n"
        )
        var parameters = model.parameters
        parameters.ipFile = ""
        parameters.ipRange = "not-an-ip"
        model.parameters = parameters

        model.startSpeedTest()

        XCTAssertEqual(model.state.notice?.message, "IP 段格式无效：not-an-ip")
        XCTAssertFalse(model.isCfstBusy)
        XCTAssertEqual(model.state.speedTest.phase, .idle)
        await model.shutdown()
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

    func testExitIPDetectionPublishesPrimaryResultBeforeEnrichment() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let primaryInfo = ExitIPInfo(ip: "203.0.113.50")
        let enrichedInfo = ExitIPInfo(
            ip: primaryInfo.ip,
            location: "东京 日本",
            details: "Example ISP · AS64500"
        )
        let detector = ControlledTwoPhaseExitDetector(primaryResults: [primaryInfo])
        let model = makeModel(paths: paths, exitDetector: detector)

        model.detectExitIP()
        try await waitForEnrichmentRequestCount(detector, 1)

        XCTAssertEqual(model.state.exit.info, primaryInfo)
        XCTAssertFalse(model.state.exit.isDetecting)
        XCTAssertTrue(model.state.exit.isEnriching)
        XCTAssertNil(model.state.exit.errorMessage)
        let detectedAt = try XCTUnwrap(model.state.exit.detectedAt)

        let pendingRequestID = await detector.enrichmentRequestID(at: 0)
        let requestID = try XCTUnwrap(pendingRequestID)
        await detector.resolveEnrichment(requestID, with: .success(enrichedInfo))
        try await waitUntil { model.state.exit.info == enrichedInfo }

        XCTAssertEqual(model.state.exit.detectedAt, detectedAt)
        XCTAssertFalse(model.state.exit.isEnriching)
        await model.shutdown()
    }

    func testExitIPEnrichmentFailurePreservesPrimaryResult() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let primaryInfo = ExitIPInfo(ip: "198.51.100.60")
        let detector = ControlledTwoPhaseExitDetector(primaryResults: [primaryInfo])
        let model = makeModel(paths: paths, exitDetector: detector)

        model.detectExitIP()
        try await waitForEnrichmentRequestCount(detector, 1)
        let detectedAt = try XCTUnwrap(model.state.exit.detectedAt)
        let pendingRequestID = await detector.enrichmentRequestID(at: 0)
        let requestID = try XCTUnwrap(pendingRequestID)
        await detector.resolveEnrichment(requestID, with: .failure(.unavailable))
        try await Task.sleep(for: .milliseconds(40))

        XCTAssertEqual(model.state.exit.info, primaryInfo)
        XCTAssertFalse(model.state.exit.isEnriching)
        XCTAssertEqual(model.state.exit.detectedAt, detectedAt)
        XCTAssertNil(model.state.exit.errorMessage)
        await model.shutdown()
    }

    func testExitIPDetectionDropsEnrichmentFromPreviousGeneration() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let firstPrimaryInfo = ExitIPInfo(ip: "192.0.2.70")
        let secondPrimaryInfo = ExitIPInfo(ip: "198.51.100.71")
        let secondEnrichedInfo = ExitIPInfo(
            ip: secondPrimaryInfo.ip,
            location: "新加坡",
            details: "Current ISP"
        )
        let detector = ControlledTwoPhaseExitDetector(
            primaryResults: [firstPrimaryInfo, secondPrimaryInfo]
        )
        let model = makeModel(paths: paths, exitDetector: detector)

        model.detectExitIP()
        try await waitForEnrichmentRequestCount(detector, 1)
        let pendingFirstRequestID = await detector.enrichmentRequestID(at: 0)
        let firstRequestID = try XCTUnwrap(pendingFirstRequestID)

        model.exitIPDetectionMode = .ipv4
        model.detectExitIP()
        try await waitForEnrichmentRequestCount(detector, 2)
        XCTAssertEqual(model.state.exit.info, secondPrimaryInfo)
        XCTAssertEqual(model.state.exit.context?.mode, .ipv4)

        let pendingSecondRequestID = await detector.enrichmentRequestID(at: 1)
        let secondRequestID = try XCTUnwrap(pendingSecondRequestID)
        await detector.resolveEnrichment(secondRequestID, with: .success(secondEnrichedInfo))
        try await waitUntil { model.state.exit.info == secondEnrichedInfo }

        await detector.resolveEnrichment(
            firstRequestID,
            with: .success(
                ExitIPInfo(
                    ip: firstPrimaryInfo.ip,
                    location: "旧位置",
                    details: "Stale ISP"
                )
            )
        )
        try await Task.sleep(for: .milliseconds(40))

        XCTAssertEqual(model.state.exit.info, secondEnrichedInfo)
        XCTAssertEqual(model.state.exit.context?.mode, .ipv4)
        await model.shutdown()
    }

    func testShutdownCancelsAndWaitsForExitIPEnrichment() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let detector = CancellationObservingExitDetector(
            primaryInfo: ExitIPInfo(ip: "203.0.113.80")
        )
        let model = makeModel(paths: paths, exitDetector: detector)

        model.detectExitIP()
        try await waitForEnrichmentStart(detector)

        await model.shutdown()

        let enrichmentWasCancelled = await detector.enrichmentWasCancelled
        XCTAssertTrue(enrichmentWasCancelled)
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

    private func waitUntilAsync(
        _ predicate: @MainActor () async -> Bool
    ) async throws {
        for _ in 0..<100 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for asynchronous condition")
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

    private func waitForEnrichmentRequestCount(
        _ detector: ControlledTwoPhaseExitDetector,
        _ count: Int
    ) async throws {
        for _ in 0..<100 {
            if await detector.enrichmentRequestCount >= count { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for \(count) exit IP enrichment requests")
    }

    private func waitForEnrichmentStart(
        _ detector: CancellationObservingExitDetector
    ) async throws {
        for _ in 0..<100 {
            if await detector.enrichmentStarted { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for exit IP enrichment to start")
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
        templateReplacer: (any XrayTemplateReplacing)? = nil,
        systemProxyManager: (any SystemProxyManaging)? = nil,
        xrayControllerFactory: XrayControllerFactory? = nil
    ) -> AppModel {
        AppModel(
            paths: paths,
            preferencesStore: store ?? PreferencesStore(fileURL: paths.preferences),
            bootstrapper: bootstrapper ?? AppBootstrapper(paths: paths),
            runtimeManager: RuntimeComponentManager(paths: paths),
            exitDetector: exitDetector ?? ExitIPDetector(),
            templateReplacer: templateReplacer,
            systemProxyManager: systemProxyManager,
            xrayControllerFactory: xrayControllerFactory
        )
    }

    private func makeExecutable(in paths: AppPaths) throws -> URL {
        let executableURL = paths.root.appendingPathComponent("xray-test")
        try "#!/bin/sh\nexit 0\n".write(
            to: executableURL,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
        return executableURL
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

    private func corruptPreferenceBackups(in paths: AppPaths) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: paths.preferences.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix("preferences.corrupt-")
                && $0.pathExtension == "json"
        }
    }

    private func validTemplate(
        host: String = "127.0.0.1",
        port: Int = 11_451,
        userID: String = "7b602ceb-cc3f-4274-a79d-c1a38f0fb0da",
        serverName: String = "proxy.example.net",
        path: String = "/viasix"
    ) -> Data {
        Data(
            #"""
            {
              "inbounds": [{"listen": "\#(host)", "port": \#(port), "protocol": "mixed"}],
              "outbounds": [{
                "tag": "proxy",
                "settings": {"vnext": [{
                  "address": "2001:db8::10",
                  "users": [{"id": "\#(userID)"}]
                }]},
                "streamSettings": {
                  "tlsSettings": {"serverName": "\#(serverName)"},
                  "wsSettings": {"host": "\#(serverName)", "path": "\#(path)"}
                }
              }]
            }
            """#.utf8
        )
    }
}

private actor ControlledSystemProxyManager: SystemProxyManaging {
    enum Failure: Error, LocalizedError, Sendable {
        case permissionDenied

        var errorDescription: String? {
            "没有修改系统代理所需的权限"
        }
    }

    private let enableFailure: Failure?
    private(set) var enableCount = 0
    private(set) var disableCount = 0
    private(set) var recoveryCount = 0
    private(set) var lastEndpoint: ProxyEndpoint?
    private(set) var isActive = false

    init(enableFailure: Failure? = nil) {
        self.enableFailure = enableFailure
    }

    func enable(endpoint: ProxyEndpoint) async throws -> SystemProxySnapshot {
        enableCount += 1
        lastEndpoint = endpoint
        if let enableFailure { throw enableFailure }
        isActive = true
        return SystemProxySnapshot(endpoint: endpoint, services: [])
    }

    func disable() async throws -> SystemProxyRestoreReport {
        disableCount += 1
        isActive = false
        return SystemProxyRestoreReport(restoredServiceIDs: ["test-service"])
    }

    func recoverIfNeeded() async throws -> SystemProxyRestoreReport {
        recoveryCount += 1
        isActive = false
        return SystemProxyRestoreReport()
    }

    func isEnabled() async -> Bool {
        isActive
    }
}

private actor ControlledXrayController: XrayControlling {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var restartCount = 0
    private(set) var isRunning = false
    private var eventHandler: XrayEventHandler?

    func start(onEvent: @escaping XrayEventHandler) async throws {
        startCount += 1
        eventHandler = onEvent
        await onEvent(.stateChanged(.validating))
        await onEvent(.stateChanged(.starting))
        isRunning = true
        await onEvent(.stateChanged(.running(pid: 42)))
    }

    func stop() async {
        stopCount += 1
        guard isRunning || eventHandler != nil else { return }
        isRunning = false
        if let eventHandler {
            await eventHandler(.stateChanged(.stopping))
            await eventHandler(.stateChanged(.stopped))
        }
        self.eventHandler = nil
    }

    func restart(onEvent: @escaping XrayEventHandler) async throws {
        restartCount += 1
        await stop()
        try await start(onEvent: onEvent)
    }

    func exitUnexpectedly() async {
        guard let eventHandler else { return }
        isRunning = false
        self.eventHandler = nil
        await eventHandler(.unexpectedExit(status: 9, output: "test exit"))
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

private actor ControlledTwoPhaseExitDetector: ExitIPDetecting {
    enum Resolution: Sendable {
        case success(ExitIPInfo)
        case failure(StubError)
    }

    enum StubError: Error, LocalizedError, Sendable {
        case unavailable

        var errorDescription: String? {
            "位置服务暂不可用"
        }
    }

    private struct EnrichmentRequest: Sendable {
        let id: UUID
        let info: ExitIPInfo
    }

    private var primaryResults: [ExitIPInfo]
    private var enrichmentRequests: [EnrichmentRequest] = []
    private var enrichmentContinuations: [UUID: CheckedContinuation<ExitIPInfo, any Error>] = [:]

    init(primaryResults: [ExitIPInfo]) {
        self.primaryResults = primaryResults
    }

    var enrichmentRequestCount: Int { enrichmentRequests.count }

    func enrichmentRequestID(at index: Int) -> UUID? {
        guard enrichmentRequests.indices.contains(index) else { return nil }
        return enrichmentRequests[index].id
    }

    func detect(
        proxy _: ProxyEndpoint?,
        endpoint _: URL?,
        expectedFamily _: IPAddressFamily?
    ) async throws -> ExitIPInfo {
        guard !primaryResults.isEmpty else { throw StubError.unavailable }
        return primaryResults.removeFirst()
    }

    func enrich(
        _ info: ExitIPInfo,
        proxy _: ProxyEndpoint?
    ) async throws -> ExitIPInfo {
        let id = UUID()
        enrichmentRequests.append(EnrichmentRequest(id: id, info: info))
        return try await withCheckedThrowingContinuation { continuation in
            enrichmentContinuations[id] = continuation
        }
    }

    func resolveEnrichment(_ id: UUID, with resolution: Resolution) {
        guard let continuation = enrichmentContinuations.removeValue(forKey: id) else { return }
        switch resolution {
        case .success(let info):
            continuation.resume(returning: info)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private actor CancellationObservingExitDetector: ExitIPDetecting {
    private let primaryInfo: ExitIPInfo
    private(set) var enrichmentStarted = false
    private(set) var enrichmentWasCancelled = false

    init(primaryInfo: ExitIPInfo) {
        self.primaryInfo = primaryInfo
    }

    func detect(
        proxy _: ProxyEndpoint?,
        endpoint _: URL?,
        expectedFamily _: IPAddressFamily?
    ) async throws -> ExitIPInfo {
        primaryInfo
    }

    func enrich(
        _ info: ExitIPInfo,
        proxy _: ProxyEndpoint?
    ) async throws -> ExitIPInfo {
        enrichmentStarted = true
        do {
            try await Task.sleep(for: .seconds(30))
            return info
        } catch is CancellationError {
            enrichmentWasCancelled = true
            throw CancellationError()
        }
    }
}
