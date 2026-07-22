import ViaSixMihomoConfig
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

    func testPreparationIgnoresLegacyConfigurationFiles() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try paths.prepare()
        let native = validProfile(address: "native.example", comment: "keep this formatting")
        let legacy = Data(#"{"outbounds":[{"protocol":"vless"}]}"#.utf8)
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

    func testViaSixYAMLOnlyRequestsSelectedIPAndPreservesLocalSettings() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        try await bootstrapper.replaceProfile(
            with: validProfile(),
            selectedIP: "2606:4700::1"
        )

        let existing = LocalProxyConfiguration(
            listenAddress: "127.0.0.7",
            port: 20_451,
            controllerPort: 20_452,
            udpEnabled: true,
            sniffingEnabled: false,
            bypassPrivateNetworks: false,
            logLevel: .debug,
            routingMode: .global,
            networkAccessMode: .virtualInterface,
            systemProxyEnabled: true,
            tunStack: .system,
            tunMTU: 1_420,
            tunStrictRoute: true
        )
        _ = try await bootstrapper.replaceLocalProxyConfiguration(
            with: existing,
            selectedIP: "2606:4700::1"
        )

        let imported = Data(
            """
            x-viasix:
              version: 1
              primary-server: selected-ip
            proxies:
              - name: edge
                type: vless
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

        _ = try await bootstrapper.replaceProfile(
            with: imported,
            selectedIP: "2606:4700::7"
        )

        let local = try await bootstrapper.loadLocalProxyConfiguration()
        XCTAssertEqual(local.listenAddress, existing.listenAddress)
        XCTAssertEqual(local.port, existing.port)
        XCTAssertEqual(local.controllerPort, existing.controllerPort)
        XCTAssertEqual(local.networkAccessMode, existing.networkAccessMode)
        XCTAssertEqual(local.systemProxyEnabled, existing.systemProxyEnabled)
        XCTAssertEqual(local.tunStack, existing.tunStack)
        XCTAssertEqual(local.tunMTU, existing.tunMTU)
        XCTAssertEqual(local.tunStrictRoute, existing.tunStrictRoute)
        XCTAssertEqual(local.routingMode, existing.routingMode)
        XCTAssertEqual(local.udpEnabled, existing.udpEnabled)
        XCTAssertEqual(local.logLevel, existing.logLevel)
        XCTAssertEqual(local.sniffingEnabled, existing.sniffingEnabled)
        XCTAssertEqual(local.bypassPrivateNetworks, existing.bypassPrivateNetworks)

        let stored = String(decoding: try Data(contentsOf: paths.profileConfig), as: UTF8.self)
        XCTAssertTrue(stored.contains("primary-server: selected-ip"))
        XCTAssertFalse(stored.contains("server: 2606:4700::7"))

        let generated = String(decoding: try Data(contentsOf: paths.generatedConfig), as: UTF8.self)
        XCTAssertTrue(generated.contains("server: 2606:4700::7"))
        XCTAssertTrue(generated.contains("mode: global"))
        XCTAssertTrue(generated.contains("log-level: debug"))
        XCTAssertTrue(generated.contains("udp: true"))
        XCTAssertFalse(generated.contains("x-viasix:"))
    }

    func testViaSixSelectedIPTemplateRequiresCurrentSelectionWithoutChangingFiles() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        let originalLocal = try Data(contentsOf: paths.localProxyConfig)

        do {
            _ = try await bootstrapper.replaceProfile(
                with: Data(
                    """
                    x-viasix:
                      version: 1
                      primary-server: selected-ip
                    proxies:
                      - name: edge
                        type: vless
                        port: 443
                        uuid: 77777777-7777-4777-8777-777777777777
                        tls: true
                        servername: origin.example
                    """.utf8
                )
            )
            XCTFail("Expected the selected node requirement to reject the import")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "IPv6 模式需要选择有效的 IPv6 节点"
            )
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.profileConfig.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.generatedConfig.path))
        XCTAssertEqual(try Data(contentsOf: paths.localProxyConfig), originalLocal)
    }

    func testProviderOnlyProfilesAreRejectedWithoutChangingPublishedFiles() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()

        do {
            try await bootstrapper.replaceProfile(
                with: providerOnlyProfile(),
                selectedIP: "2606:4700::10"
            )
            XCTFail("Provider-only profiles must not enter the IPv6 runtime")
        } catch {
            XCTAssertEqual(error as? MihomoConfigurationError, .ipv6ManagedProfileRequired)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.profileConfig.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.generatedConfig.path))
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
        try await bootstrapper.replaceProfile(
            with: validProfile(address: "inline.example"),
            selectedIP: "2606:4700::20"
        )
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
        try validProfile(address: "origin.example").write(to: paths.profileConfig)

        let synchronized = try await bootstrapper.synchronizeConfiguration(selectedIP: nil)

        XCTAssertTrue(synchronized.supportsNodeSelection)
        XCTAssertNil(synchronized.effectiveIP)
        XCTAssertEqual(synchronized.launchIssue, .selectedNodeMustBeIPv6)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.generatedConfig.path))
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

    func testVirtualInterfaceUsesPrivilegedProjectionWithoutPublishingEnabledTun() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        try await bootstrapper.replaceProfile(
            with: validProfile(),
            selectedIP: "2606:4700::30"
        )
        var tunnel = try await bootstrapper.loadLocalProxyConfiguration()
        tunnel.networkAccessMode = .virtualInterface

        _ = try await bootstrapper.replaceLocalProxyConfiguration(
            with: tunnel,
            selectedIP: "2606:4700::30"
        )

        let persistedLocal = try await bootstrapper.loadLocalProxyConfiguration()
        XCTAssertEqual(persistedLocal, tunnel)

        let userConfiguration = try Data(contentsOf: paths.generatedConfig)
        let userText = String(decoding: userConfiguration, as: UTF8.self)
        XCTAssertTrue(userText.contains("tun:"))
        XCTAssertTrue(userText.contains("enable: false"))
        XCTAssertFalse(userText.contains("auto-route: true"))

        let privileged = try await bootstrapper.privilegedTunConfiguration(
            selectedIP: "2606:4700::30"
        )
        let privilegedText = String(decoding: privileged, as: UTF8.self)
        XCTAssertTrue(privilegedText.contains("enable: true"))
        XCTAssertTrue(privilegedText.contains("auto-route: true"))
        XCTAssertTrue(privilegedText.contains("auto-detect-interface: true"))
        XCTAssertTrue(privilegedText.contains("dns-hijack:"))
        XCTAssertTrue(privilegedText.contains("enhanced-mode: fake-ip"))
        XCTAssertTrue(privilegedText.contains("proxies:"))
        XCTAssertFalse(privilegedText.contains("proxy-groups:"))
        XCTAssertTrue(privilegedText.contains("rules:"))
        XCTAssertEqual(try Data(contentsOf: paths.generatedConfig), userConfiguration)

        let envelope = try await bootstrapper.privilegedTunConfigurationEnvelope(
            selectedIP: "2606:4700::88"
        )
        XCTAssertTrue(envelope.starts(with: Data("bplist00".utf8)))
        let envelopeRoot = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: envelope, format: nil)
                as? [String: Any]
        )
        let envelopeServer = try XCTUnwrap(envelopeRoot["server"] as? [String: Any])
        let envelopeProxies = try XCTUnwrap(
            envelopeServer["proxies"] as? [[String: Any]]
        )
        XCTAssertEqual(envelopeProxies.first?["server"] as? String, "2606:4700::88")
        XCTAssertEqual(try Data(contentsOf: paths.generatedConfig), userConfiguration)
    }

    func testPrivilegedTunProjectionRejectsNonVirtualInterfaceModes() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        try await bootstrapper.replaceProfile(
            with: validProfile(),
            selectedIP: "2606:4700::40"
        )

        for mode in [NetworkAccessMode.localProxy] {
            var local = try await bootstrapper.loadLocalProxyConfiguration()
            local.networkAccessMode = mode
            _ = try await bootstrapper.replaceLocalProxyConfiguration(
                with: local,
                selectedIP: "2606:4700::40"
            )

            do {
                _ = try await bootstrapper.privilegedTunConfiguration()
                XCTFail("Only virtual-interface mode may request privileged TUN configuration")
            } catch {
                XCTAssertEqual(
                    error as? AppBootstrapperError,
                    .virtualInterfaceRequiresPrivilegedService
                )
            }

            do {
                _ = try await bootstrapper.privilegedTunConfigurationEnvelope()
                XCTFail("Only virtual-interface mode may request a privileged TUN envelope")
            } catch {
                XCTAssertEqual(
                    error as? AppBootstrapperError,
                    .virtualInterfaceRequiresPrivilegedService
                )
            }
        }
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
        try await bootstrapper.replaceProfile(
            with: validProfile(address: "first.example"),
            selectedIP: "2606:4700::50"
        )
        let oldProfile = try Data(contentsOf: paths.profileConfig)
        let oldLocal = try Data(contentsOf: paths.localProxyConfig)
        let oldConfig = try Data(contentsOf: paths.generatedConfig)
        let writer = FailingConfigurationWriter(failingCall: 2)
        let failing = AppBootstrapper(paths: paths, configurationFileWriter: writer.write)

        do {
            _ = try await failing.replaceProfile(
                with: validProfile(address: "second.example"),
                selectedIP: "2606:4700::51"
            )
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
        try await bootstrapper.replaceProfile(
            with: validProfile(address: "stable.example"),
            selectedIP: "2606:4700::60"
        )
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

    func testOptimisticProfileReplacementRejectsExternalEdit() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        try await bootstrapper.replaceProfile(
            with: validProfile(address: "first.example"),
            selectedIP: "2606:4700::70"
        )
        let opened = try Data(contentsOf: paths.profileConfig)
        let external = validProfile(address: "external.example")
        try external.write(to: paths.profileConfig)

        do {
            _ = try await bootstrapper.replaceProfileIfUnchanged(
                with: validProfile(address: "editor.example"),
                selectedIP: "2606:4700::71",
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
