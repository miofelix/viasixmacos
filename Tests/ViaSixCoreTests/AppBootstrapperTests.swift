import XCTest

@testable import ViaSixCore

final class AppBootstrapperTests: XCTestCase {
    func testFirstLaunchCreatesMihomoHomeWithoutInventingServerProfile() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)

        try await bootstrapper.prepareDefaults()

        for directory in [
            paths.root,
            paths.data,
            paths.runtime,
            paths.logs,
            paths.mihomoHome,
            paths.mihomoProviders,
            paths.mihomoRules,
        ] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path), directory.path)
            XCTAssertEqual(try permissions(of: directory), 0o700)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.localProxyConfig.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.profileConfig.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.generatedConfig.path))

        let synchronized = try await bootstrapper.synchronizeConfiguration(selectedIP: "2606::1")
        XCTAssertEqual(synchronized.launchIssue, .missingProxySource)
        XCTAssertNil(synchronized.effectiveIP)
        XCTAssertFalse(synchronized.supportsNodeSelection)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.generatedConfig.path))
    }

    func testMigrationPrefersLegacyServerAndPreservesEveryLegacyFile() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try paths.prepare()
        let serverTemplate = try legacyTemplate(
            address: "server-priority.example",
            credential: "11111111-1111-4111-8111-111111111111",
            serverName: "server-priority.example"
        )
        let server = try ConfigTemplate.serverConfiguration(from: serverTemplate)
        let template = try legacyTemplate(
            address: "template-fallback.example",
            credential: "22222222-2222-4222-8222-222222222222",
            serverName: "template-fallback.example"
        )
        try server.write(to: paths.legacyServerConfig)
        try template.write(to: paths.legacyTemplateConfig)

        try await AppBootstrapper(paths: paths).prepareDefaults()

        XCTAssertEqual(try Data(contentsOf: paths.legacyServerConfig), server)
        XCTAssertEqual(try Data(contentsOf: paths.legacyTemplateConfig), template)
        let profile = String(decoding: try Data(contentsOf: paths.profileConfig), as: UTF8.self)
        let generated = String(decoding: try Data(contentsOf: paths.generatedConfig), as: UTF8.self)
        XCTAssertTrue(profile.contains("server-priority.example"))
        XCTAssertTrue(profile.contains("11111111-1111-4111-8111-111111111111"))
        XCTAssertFalse(profile.contains("template-fallback.example"))
        XCTAssertTrue(generated.contains("server-priority.example"))
    }

    func testMigrationFallsBackToTemplateOnlyWhenServerFileIsMissing() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try paths.prepare()
        let template = try legacyTemplate(
            address: "fallback.example",
            credential: "33333333-3333-4333-8333-333333333333",
            serverName: "fallback.example",
            listen: "127.0.0.2",
            port: 20_280
        )
        try template.write(to: paths.legacyTemplateConfig)

        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()

        let profile = String(decoding: try Data(contentsOf: paths.profileConfig), as: UTF8.self)
        XCTAssertTrue(profile.contains("fallback.example"))
        let local = try await bootstrapper.loadLocalProxyConfiguration()
        XCTAssertEqual(local.endpoint, ProxyEndpoint(host: "127.0.0.2", port: 20_280))
        XCTAssertEqual(try Data(contentsOf: paths.legacyTemplateConfig), template)
    }

    func testPlaceholderLegacyServerDoesNotCreateProfileOrFallBackToTemplate() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try paths.prepare()
        let placeholder = try legacyTemplate(
            address: "2001:db8::1",
            credential: "00000000-0000-0000-0000-000000000000",
            serverName: "example.com"
        )
        let validTemplate = try legacyTemplate(
            address: "must-not-win.example",
            credential: "44444444-4444-4444-8444-444444444444",
            serverName: "must-not-win.example"
        )
        try ConfigTemplate.serverConfiguration(from: placeholder).write(
            to: paths.legacyServerConfig
        )
        try validTemplate.write(to: paths.legacyTemplateConfig)

        try await AppBootstrapper(paths: paths).prepareDefaults()

        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.profileConfig.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.generatedConfig.path))
    }

    func testExistingNativeProfileIsPreservedByPreparation() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try paths.prepare()
        let native = validProfile(address: "native.example", comment: "keep this formatting")
        let legacy = try legacyTemplate(
            address: "legacy.example",
            credential: "55555555-5555-4555-8555-555555555555",
            serverName: "legacy.example"
        )
        try native.write(to: paths.profileConfig)
        try legacy.write(to: paths.legacyTemplateConfig)

        try await AppBootstrapper(paths: paths).prepareDefaults()

        XCTAssertEqual(try Data(contentsOf: paths.profileConfig), native)
    }

    func testImportedFullMihomoDocumentPersistsOnlyServerFields() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        let imported = Data(
            """
            mixed-port: 9999
            bind-address: 0.0.0.0
            allow-lan: true
            mode: global
            external-controller: 0.0.0.0:9090
            secret: unsafe
            tun: {enable: true}
            dns: {enable: true}
            proxies:
              - name: edge
                type: ss
                server: origin.example
                port: 8388
                cipher: aes-128-gcm
                password: secret
            """.utf8
        )

        let endpoint = try await bootstrapper.replaceProfile(
            with: imported,
            selectedIP: "2606::8"
        )

        XCTAssertEqual(endpoint, ProxyEndpoint())
        let stored = String(decoding: try Data(contentsOf: paths.profileConfig), as: UTF8.self)
        XCTAssertTrue(stored.contains("proxies:"))
        for localKey in [
            "mixed-port", "bind-address", "allow-lan", "mode:",
            "external-controller", "secret:", "tun:", "dns:",
        ] {
            XCTAssertFalse(stored.contains(localKey), localKey)
        }
        let generated = String(decoding: try Data(contentsOf: paths.generatedConfig), as: UTF8.self)
        XCTAssertTrue(generated.contains("mixed-port: 11451"))
        XCTAssertTrue(generated.contains("2606::8"))
        XCTAssertFalse(generated.contains("9999"))
    }

    func testProviderOnlyProfilesLaunchInRuleAndGlobalModesAndIgnoreSelectedIP() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        try await bootstrapper.replaceProfile(
            with: providerOnlyProfile(),
            selectedIP: "203.0.113.10"
        )

        var synchronized = try await bootstrapper.synchronizeConfiguration(
            selectedIP: "203.0.113.11"
        )
        XCTAssertNil(synchronized.launchIssue)
        XCTAssertNil(synchronized.effectiveIP)
        XCTAssertFalse(synchronized.supportsNodeSelection)
        let providerSelectionApplied = try await bootstrapper.writeConfig(ip: "203.0.113.99")
        XCTAssertFalse(providerSelectionApplied)
        var generated = String(decoding: try Data(contentsOf: paths.generatedConfig), as: UTF8.self)
        XCTAssertTrue(generated.contains("mode: rule"))
        XCTAssertTrue(generated.contains("proxy-providers:"))
        XCTAssertFalse(generated.contains("203.0.113."))

        var local = synchronized.local
        local.routingMode = .global
        _ = try await bootstrapper.replaceLocalProxyConfiguration(
            with: local,
            selectedIP: "203.0.113.12"
        )
        synchronized = try await bootstrapper.synchronizeConfiguration(
            selectedIP: "203.0.113.13"
        )
        XCTAssertNil(synchronized.effectiveIP)
        generated = String(decoding: try Data(contentsOf: paths.generatedConfig), as: UTF8.self)
        XCTAssertTrue(generated.contains("mode: global"))
        XCTAssertFalse(generated.contains("203.0.113."))
    }

    func testDirectModeNeedsNoProfileAndRuntimeContainsNoRemoteSources() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        let direct = LocalProxyConfiguration(
            listenAddress: "127.0.0.3",
            port: 19_090,
            routingMode: .direct
        )

        _ = try await bootstrapper.replaceLocalProxyConfiguration(with: direct)
        let synchronized = try await bootstrapper.synchronizeConfiguration(selectedIP: "2606::1")

        XCTAssertNil(synchronized.launchIssue)
        XCTAssertNil(synchronized.effectiveIP)
        XCTAssertFalse(synchronized.supportsNodeSelection)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.profileConfig.path))
        let generated = String(decoding: try Data(contentsOf: paths.generatedConfig), as: UTF8.self)
        XCTAssertTrue(generated.contains("mode: direct"))
        XCTAssertTrue(generated.contains("MATCH,DIRECT"))
        XCTAssertFalse(generated.contains("proxies:"))
        XCTAssertFalse(generated.contains("proxy-providers:"))
    }

    func testDirectModeDropsExistingInlineAndProviderConfiguration() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        try await bootstrapper.replaceProfile(with: validProfile(address: "inline.example"))
        var local = try await bootstrapper.loadLocalProxyConfiguration()
        local.routingMode = .direct
        _ = try await bootstrapper.replaceLocalProxyConfiguration(with: local)

        let generated = String(decoding: try Data(contentsOf: paths.generatedConfig), as: UTF8.self)
        XCTAssertFalse(generated.contains("inline.example"))
        XCTAssertFalse(generated.contains("proxies:"))
        XCTAssertFalse(generated.contains("proxy-providers:"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.profileConfig.path))
    }

    func testOriginalInlineServerDoesNotBecomeAnImplicitSelectedIP() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        try await bootstrapper.replaceProfile(
            with: validProfile(address: "origin.example"),
            selectedIP: nil
        )

        let synchronized = try await bootstrapper.synchronizeConfiguration(selectedIP: nil)

        XCTAssertTrue(synchronized.supportsNodeSelection)
        XCTAssertNil(synchronized.effectiveIP)
        let currentIP = try await bootstrapper.currentConfigIP()
        XCTAssertEqual(currentIP, "origin.example")
    }

    func testInlineProfileAppliesSelectedIPButKeepsIdentityFields() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()

        try await bootstrapper.replaceProfile(
            with: validProfile(address: "origin.example"),
            selectedIP: "2606:4700::8"
        )

        let currentIP = try await bootstrapper.currentConfigIP()
        XCTAssertEqual(currentIP, "2606:4700::8")
        let stored = String(decoding: try Data(contentsOf: paths.profileConfig), as: UTF8.self)
        let generated = String(decoding: try Data(contentsOf: paths.generatedConfig), as: UTF8.self)
        XCTAssertTrue(stored.contains("origin.example"))
        XCTAssertFalse(stored.contains("2606:4700::8"))
        XCTAssertTrue(generated.contains("2606:4700::8"))
        XCTAssertTrue(generated.contains("servername: origin.example"))
    }

    func testVirtualInterfaceProjectionFailsClosedInUserWritableRuntime() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        try await bootstrapper.replaceProfile(with: validProfile())
        let originalLocal = try await bootstrapper.loadLocalProxyConfiguration()
        let originalConfig = try Data(contentsOf: paths.generatedConfig)
        var tunnel = originalLocal
        tunnel.networkAccessMode = .virtualInterface

        do {
            _ = try await bootstrapper.replaceLocalProxyConfiguration(with: tunnel)
            XCTFail("The unprivileged runtime must not generate an enabled TUN config")
        } catch {
            XCTAssertEqual(
                error as? AppBootstrapperError,
                .virtualInterfaceRequiresPrivilegedService
            )
        }

        let persistedLocal = try await bootstrapper.loadLocalProxyConfiguration()
        XCTAssertEqual(persistedLocal, originalLocal)
        XCTAssertEqual(try Data(contentsOf: paths.generatedConfig), originalConfig)
    }

    func testProfileReplacementPublishesProfileLocalAndRuntimeWithOwnerOnlyPermissions() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()

        try await bootstrapper.replaceProfile(with: validProfile(), selectedIP: "2606::80")

        for file in [paths.profileConfig, paths.localProxyConfig, paths.generatedConfig] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
            XCTAssertEqual(try permissions(of: file), 0o600)
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: paths.data.appendingPathComponent(".configuration-transaction").path
            )
        )
    }

    func testStagingFailureLeavesAllPublishedConfigurationUntouched() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        try await bootstrapper.replaceProfile(with: validProfile(address: "first.example"))
        let oldProfile = try Data(contentsOf: paths.profileConfig)
        let oldLocal = try Data(contentsOf: paths.localProxyConfig)
        let oldConfig = try Data(contentsOf: paths.generatedConfig)
        let writer = FailingConfigurationWriter(failingCall: 2)
        let failing = AppBootstrapper(paths: paths, configurationFileWriter: writer.write)

        do {
            _ = try await failing.replaceProfile(with: validProfile(address: "second.example"))
            XCTFail("Expected injected staging failure")
        } catch {
            XCTAssertEqual(error as? ConfigurationWriterTestError, .injected)
        }

        XCTAssertEqual(try Data(contentsOf: paths.profileConfig), oldProfile)
        XCTAssertEqual(try Data(contentsOf: paths.localProxyConfig), oldLocal)
        XCTAssertEqual(try Data(contentsOf: paths.generatedConfig), oldConfig)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: paths.data.appendingPathComponent(".configuration-transaction").path
            )
        )
    }

    func testPreparedMihomoTransactionRecoversAllThreeFiles() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        try await bootstrapper.replaceProfile(with: validProfile(address: "stable.example"))
        let oldProfile = try Data(contentsOf: paths.profileConfig)
        let oldLocal = try Data(contentsOf: paths.localProxyConfig)
        let oldConfig = try Data(contentsOf: paths.generatedConfig)
        try writePreparedMihomoTransaction(
            paths: paths,
            profileBackup: oldProfile,
            configBackup: oldConfig,
            localBackup: oldLocal
        )
        try validProfile(address: "partial.example").write(to: paths.profileConfig)
        try Data("partial config".utf8).write(to: paths.generatedConfig)
        try Data("partial local".utf8).write(to: paths.localProxyConfig)

        try await AppBootstrapper(paths: paths).prepareDefaults()

        XCTAssertEqual(try Data(contentsOf: paths.profileConfig), oldProfile)
        XCTAssertEqual(try Data(contentsOf: paths.localProxyConfig), oldLocal)
        XCTAssertEqual(try Data(contentsOf: paths.generatedConfig), oldConfig)
    }

    func testPreparedLegacyTransactionStillRestoresOldDestinations() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try paths.prepare()
        let oldTemplate = try legacyTemplate(
            address: "restored.example",
            credential: "66666666-6666-4666-8666-666666666666",
            serverName: "restored.example"
        )
        let oldServer = try ConfigTemplate.serverConfiguration(from: oldTemplate)
        let oldGenerated = Data("old generated Xray document".utf8)
        let oldLocal = try JSONEncoder.pretty.encode(LocalProxyConfiguration())
        try writePreparedLegacyTransaction(
            paths: paths,
            templateBackup: oldTemplate,
            generatedBackup: oldGenerated,
            serverBackup: oldServer,
            localBackup: oldLocal
        )
        try Data("partial".utf8).write(to: paths.legacyTemplateConfig)
        try Data("partial".utf8).write(to: paths.legacyServerConfig)
        try Data("partial".utf8).write(to: paths.legacyGeneratedConfig)
        try Data("partial".utf8).write(to: paths.localProxyConfig)

        try await AppBootstrapper(paths: paths).prepareDefaults()

        XCTAssertEqual(try Data(contentsOf: paths.legacyTemplateConfig), oldTemplate)
        XCTAssertEqual(try Data(contentsOf: paths.legacyServerConfig), oldServer)
        XCTAssertEqual(try Data(contentsOf: paths.legacyGeneratedConfig), oldGenerated)
        XCTAssertEqual(try Data(contentsOf: paths.localProxyConfig), oldLocal)
    }

    func testOptimisticProfileReplacementRejectsExternalEdit() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        try await bootstrapper.replaceProfile(with: validProfile(address: "first.example"))
        let opened = try Data(contentsOf: paths.profileConfig)
        let external = validProfile(address: "external.example")
        try external.write(to: paths.profileConfig)

        do {
            _ = try await bootstrapper.replaceProfileIfUnchanged(
                with: validProfile(address: "editor.example"),
                selectedIP: nil,
                expectedProfileData: opened
            )
            XCTFail("Expected external edit conflict")
        } catch {
            XCTAssertEqual(error as? AppBootstrapperError, .profileChangedExternally)
        }
        XCTAssertEqual(try Data(contentsOf: paths.profileConfig), external)
    }

    func testPrepareDefaultsRemovesOnlyStrictlyNamedSpeedTestTemporaryFiles() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try paths.prepare()
        let runID = UUID().uuidString
        let temporaryID = UUID().uuidString
        let stale = [
            paths.data.appendingPathComponent(".result.csv.\(temporaryID).tmp"),
            paths.data.appendingPathComponent(".current-test-\(runID).csv"),
            paths.data.appendingPathComponent("..current-test-\(runID).csv.\(temporaryID).tmp"),
        ]
        let kept = [
            paths.resultCSV,
            paths.data.appendingPathComponent(".result.csv.not-a-uuid.tmp"),
            paths.data.appendingPathComponent(".current-test-\(runID).csv.backup"),
        ]
        for url in stale { try Data("temporary".utf8).write(to: url) }
        for url in kept { try Data("keep".utf8).write(to: url) }

        try await AppBootstrapper(paths: paths).prepareDefaults()

        for url in stale { XCTAssertFalse(FileManager.default.fileExists(atPath: url.path)) }
        for url in kept { XCTAssertTrue(FileManager.default.fileExists(atPath: url.path)) }
    }

    func testLoadResultsAndSelectedResultUseGeneratedMihomoAddress() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        try await bootstrapper.replaceProfile(
            with: validProfile(),
            selectedIP: "2606::2"
        )
        let csv = """
            IP,Sent,Recv,Loss,Latency,Speed,Region
            2606::1,4,4,0.00,18.2,10.5,SJC
            2606::2,4,4,0.00,22.8,8.1,LAX
            """
        try Data(csv.utf8).write(to: paths.resultCSV)

        let results = try await bootstrapper.loadResults()
        let generatedSelection = try await bootstrapper.resultForSelectedIP()
        let explicitSelection = try await bootstrapper.resultForSelectedIP("2606::1")
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(generatedSelection?.region, "LAX")
        XCTAssertEqual(explicitSelection?.region, "SJC")
    }

    private func makePaths() -> AppPaths {
        AppPaths(
            root: FileManager.default.temporaryDirectory.appendingPathComponent(
                "AppBootstrapperTests-\(UUID().uuidString)",
                isDirectory: true
            )
        )
    }

    private func validProfile(
        address: String = "origin.example",
        comment: String? = nil
    ) -> Data {
        let prefix = comment.map { "# \($0)\n" } ?? ""
        return Data(
            """
            \(prefix)proxies:
              - name: edge
                type: vless
                server: \(address)
                port: 443
                uuid: 77777777-7777-4777-8777-777777777777
                network: ws
                tls: true
                servername: origin.example
                ws-opts:
                  path: /viasix
                  headers:
                    Host: origin.example
            """.utf8
        )
    }

    private func providerOnlyProfile() -> Data {
        Data(
            """
            proxy-providers:
              remote:
                type: http
                url: https://subscription.example/profile.yaml
                path: ../../outside.yaml
                interval: 3600
            proxy-groups:
              - name: PROXY
                type: select
                use: [remote]
            rules:
              - MATCH,PROXY
            """.utf8
        )
    }

    private func legacyTemplate(
        address: String,
        credential: String,
        serverName: String,
        listen: String = "127.0.0.1",
        port: Int = 11_451
    ) throws -> Data {
        try TestConfigFixtures.connectionTemplate(
            address: address,
            userID: credential,
            serverName: serverName,
            path: "/viasix",
            listen: listen,
            port: port
        )
    }

    private func writePreparedMihomoTransaction(
        paths: AppPaths,
        profileBackup: Data,
        configBackup: Data,
        localBackup: Data
    ) throws {
        let directory = paths.data.appendingPathComponent(
            ".configuration-transaction",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try profileBackup.write(to: directory.appendingPathComponent("profile.backup.yaml"))
        try configBackup.write(to: directory.appendingPathComponent("config.backup.yaml"))
        try localBackup.write(to: directory.appendingPathComponent("local-proxy.backup.json"))
        let manifest = try JSONSerialization.data(withJSONObject: [
            "version": 2,
            "state": "prepared",
            "profileExisted": true,
            "configExisted": true,
            "localExisted": true,
        ])
        try manifest.write(to: directory.appendingPathComponent("manifest.json"))
    }

    private func writePreparedLegacyTransaction(
        paths: AppPaths,
        templateBackup: Data,
        generatedBackup: Data,
        serverBackup: Data,
        localBackup: Data
    ) throws {
        let directory = paths.data.appendingPathComponent(
            ".configuration-transaction",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try templateBackup.write(to: directory.appendingPathComponent("template.backup.json"))
        try generatedBackup.write(to: directory.appendingPathComponent("config.backup.json"))
        try serverBackup.write(to: directory.appendingPathComponent("server.backup.json"))
        try localBackup.write(to: directory.appendingPathComponent("local-proxy.backup.json"))
        let manifest = try JSONSerialization.data(withJSONObject: [
            "state": "prepared",
            "templateExisted": true,
            "generatedExisted": true,
            "serverExisted": true,
            "localExisted": true,
        ])
        try manifest.write(to: directory.appendingPathComponent("manifest.json"))
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue & 0o777
    }
}

private enum ConfigurationWriterTestError: Error {
    case injected
}

private final class FailingConfigurationWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let failingCall: Int
    private var calls = 0

    init(failingCall: Int) {
        self.failingCall = failingCall
    }

    func write(_ data: Data, to url: URL) throws {
        try lock.withLock {
            calls += 1
            if calls == failingCall { throw ConfigurationWriterTestError.injected }
        }
        try data.write(to: url, options: .atomic)
    }
}
