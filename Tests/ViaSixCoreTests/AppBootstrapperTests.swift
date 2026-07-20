import XCTest

@testable import ViaSixCore

final class AppBootstrapperTests: XCTestCase {
    func testPrepareDefaultsInstallsFirstLaunchResources() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)

        try await bootstrapper.prepareDefaults()

        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.ipv4List.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.ipv6List.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.templateConfig.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.runtime.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.logs.path))

        let ipv4Ranges = try String(contentsOf: paths.ipv4List, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        XCTAssertEqual(ipv4Ranges.count, 25)
        XCTAssertEqual(ipv4Ranges.last, "131.0.72.0/22")
    }

    func testPrepareDefaultsInstallsNeutralConnectionTemplate() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)

        try await bootstrapper.prepareDefaults()

        let template = try Data(contentsOf: paths.templateConfig)
        let templateText = String(decoding: template, as: UTF8.self)
        XCTAssertTrue(templateText.contains(ConfigTemplate.placeholderUserID))
        XCTAssertTrue(templateText.contains(ConfigTemplate.placeholderServerName))
        XCTAssertEqual(ConfigTemplate.address(in: template), "2001:db8::1")
        XCTAssertNoThrow(try ConfigTemplate.validateTemplate(template))
    }

    func testLaunchReadinessCheckRejectsPlaceholderWithoutWritingGeneratedConfig() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()

        do {
            _ = try await bootstrapper.validateTemplateForLaunch(selectedIP: "2606::10")
            XCTFail("Expected the neutral connection template to require setup")
        } catch {
            XCTAssertEqual(error as? ConfigTemplateError, .connectionNotConfigured)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.generatedConfig.path))
    }

    func testLaunchReadinessCheckAcceptsConfiguredTemplateWithoutWritingGeneratedConfig() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        let template = try TestConfigFixtures.connectionTemplate(
            userID: "f4edc501-056c-4572-9da8-ad63a264a698",
            serverName: "proxy.example.net",
            path: "/viasix",
            listen: "127.0.0.2",
            port: 18_080
        )
        try await bootstrapper.replaceTemplate(with: template)
        try? FileManager.default.removeItem(at: paths.generatedConfig)

        let endpoint = try await bootstrapper.validateTemplateForLaunch()

        XCTAssertEqual(endpoint, ProxyEndpoint(host: "127.0.0.2", port: 18_080))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.generatedConfig.path))
    }

    func testPrepareDefaultsRemovesOnlyStaleSpeedTestResultsFromDataDirectory() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try paths.prepare()

        let runID = UUID().uuidString
        let temporaryID = UUID().uuidString
        let staleResult = paths.data.appendingPathComponent(
            ".result.csv.\(temporaryID).tmp"
        )
        let staleCurrentResult = paths.data.appendingPathComponent(
            ".current-test-\(runID).csv"
        )
        let staleCurrentTemporaryResult = paths.data.appendingPathComponent(
            "..current-test-\(runID).csv.\(temporaryID).tmp"
        )
        for url in [staleResult, staleCurrentResult, staleCurrentTemporaryResult] {
            try Data("temporary".utf8).write(to: url)
        }

        let persistentResult = paths.resultCSV
        let similarNames = [
            paths.data.appendingPathComponent(".result.csv.not-a-uuid.tmp"),
            paths.data.appendingPathComponent(".result.csv.\(temporaryID).tmp.backup"),
            paths.data.appendingPathComponent(".current-test-not-a-uuid.csv"),
            paths.data.appendingPathComponent(".current-test-\(runID).csv.backup"),
        ]
        for url in [persistentResult] + similarNames {
            try Data("keep".utf8).write(to: url)
        }

        let matchingDirectory = paths.data.appendingPathComponent(
            ".current-test-\(UUID().uuidString).csv",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: matchingDirectory,
            withIntermediateDirectories: false
        )
        let matchingFileOutsideData = paths.root.appendingPathComponent(
            ".result.csv.\(UUID().uuidString).tmp"
        )
        try Data("outside".utf8).write(to: matchingFileOutsideData)

        try await bootstrapper.prepareDefaults()

        for url in [staleResult, staleCurrentResult, staleCurrentTemporaryResult] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), url.path)
        }
        for url in [persistentResult] + similarNames + [matchingDirectory, matchingFileOutsideData] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), url.path)
        }
        XCTAssertEqual(try String(contentsOf: persistentResult, encoding: .utf8), "keep")
    }

    func testPrepareDefaultsMigratesOnlyThePreviouslyShippedIPv4List() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try paths.prepare()
        let legacyIPv4List = """
            173.245.48.0/20
            103.21.244.0/22
            103.22.200.0/22
            103.31.4.0/22
            141.101.64.0/18
            108.162.192.0/18
            190.93.240.0/20
            188.114.96.0/20
            197.234.240.0/22
            198.41.128.0/17
            162.158.0.0/15
            104.16.0.0/12
            """ + "\n\n"
        try Data(legacyIPv4List.utf8).write(to: paths.ipv4List)

        try await bootstrapper.prepareDefaults()

        let migrated = try String(contentsOf: paths.ipv4List, encoding: .utf8)
        XCTAssertTrue(migrated.contains("172.67.0.0/16"))
        XCTAssertTrue(migrated.contains("131.0.72.0/22"))

        let customized = migrated + "203.0.113.0/24\n"
        try Data(customized.utf8).write(to: paths.ipv4List, options: .atomic)
        try await bootstrapper.prepareDefaults()
        XCTAssertEqual(
            try String(contentsOf: paths.ipv4List, encoding: .utf8),
            customized
        )
    }

    func testLoadResultsReturnsEmptyWhenMissingAndThrowsForMalformedCSV() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)

        let missingResults = try await bootstrapper.loadResults()
        XCTAssertEqual(missingResults, [])

        try paths.prepare()
        try Data("IP,Sent,Recv,Loss,Latency,Speed,Region\n\"unterminated".utf8)
            .write(to: paths.resultCSV, options: .atomic)

        do {
            _ = try await bootstrapper.loadResults()
            XCTFail("Expected malformed CSV to throw")
        } catch {
            XCTAssertEqual(error as? CSVError, .unclosedQuote)
        }
    }

    func testLoadResultsParsesEveryValidRow() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try paths.prepare()
        let csv = """
            IP,Sent,Recv,Loss,Latency,Speed,Region
            2606::1,4,4,0.00,18.2,10.5,SJC
            2606::2,4,4,0.00,22.8,8.1,LAX
            """
        try Data(csv.utf8).write(to: paths.resultCSV, options: .atomic)

        let results = try await bootstrapper.loadResults()

        XCTAssertEqual(results.map(\.ip), ["2606::1", "2606::2"])
        XCTAssertEqual(results[1].region, "LAX")
    }

    func testSelectedResultCanBeNonFirstRowAndFallsBackToCurrentConfig() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        let csv = """
            IP,Sent,Recv,Loss,Latency,Speed,Region
            2606::1,4,4,0.00,18.2,10.5,SJC
            2606::2,4,4,0.00,22.8,8.1,LAX
            """
        try Data(csv.utf8).write(to: paths.resultCSV, options: .atomic)

        let explicitSelection = try await bootstrapper.resultForSelectedIP(" 2606::2 ")
        XCTAssertEqual(explicitSelection?.ip, "2606::2")

        try await bootstrapper.writeConfig(ip: "2606::2")
        let currentSelection = try await bootstrapper.resultForSelectedIP()
        XCTAssertEqual(currentSelection?.ip, "2606::2")
    }

    func testWriteConfigAtomicallyGeneratesConfigAndReadsCurrentIP() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()

        let missingIP = try await bootstrapper.currentConfigIP()
        XCTAssertNil(missingIP)

        try await bootstrapper.writeConfig(ip: " 2606::99 ")

        let currentIP = try await bootstrapper.currentConfigIP()
        XCTAssertEqual(currentIP, "2606::99")
        let generated = try Data(contentsOf: paths.generatedConfig)
        XCTAssertEqual(ConfigTemplate.address(in: generated), "2606::99")
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: generated))
    }

    func testEnsureConfigValidatesTemplateEvenWhenIPMatchesAndRepairsMismatch() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        try await bootstrapper.writeConfig(ip: "2606::1")

        try Data("not json".utf8).write(to: paths.templateConfig, options: .atomic)
        do {
            _ = try await bootstrapper.ensureConfig(ip: " 2606::1 ")
            XCTFail("Expected the corrupt template to be rejected even when the IP matches")
        } catch {
            XCTAssertEqual(error as? ConfigTemplateError, .invalidJSON)
        }

        do {
            _ = try await bootstrapper.ensureConfig(ip: "2606::2")
            XCTFail("Expected the mismatched config to be regenerated from the template")
        } catch {
            XCTAssertEqual(error as? ConfigTemplateError, .invalidJSON)
        }

        try FileManager.default.removeItem(at: paths.templateConfig)
        try DefaultResourceInstaller.install(into: paths)
        let repaired = try await bootstrapper.ensureConfig(ip: "2606::2")
        let currentIP = try await bootstrapper.currentConfigIP()
        XCTAssertTrue(repaired)
        XCTAssertEqual(currentIP, "2606::2")
    }

    func testEnsureConfigRebuildsConnectionDetailsWhenIPIsUnchanged() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        let firstTemplate = try TestConfigFixtures.connectionTemplate(
            userID: "f4edc501-056c-4572-9da8-ad63a264a698",
            serverName: "first.example.net",
            path: "/first"
        )
        try await bootstrapper.replaceTemplate(with: firstTemplate, selectedIP: "2606::8")

        let secondTemplate = try TestConfigFixtures.connectionTemplate(
            userID: "22de5d8d-17f7-40e8-a83f-567ae87c865a",
            serverName: "second.example.net",
            path: "/second"
        )
        try secondTemplate.write(to: paths.templateConfig, options: .atomic)

        let firstRepair = try await bootstrapper.ensureConfig(ip: "2606::8")
        let secondRepair = try await bootstrapper.ensureConfig(ip: "2606::8")
        XCTAssertTrue(firstRepair)
        XCTAssertFalse(secondRepair)
        let generated = String(
            decoding: try Data(contentsOf: paths.generatedConfig),
            as: UTF8.self
        )
        XCTAssertTrue(generated.contains("22de5d8d-17f7-40e8-a83f-567ae87c865a"))
        XCTAssertTrue(generated.contains("second.example.net"))
        XCTAssertTrue(generated.contains("/second"))
    }

    func testTemplateReplacementRollsBackBothFilesWhenCommitFails() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        let originalTemplate = try TestConfigFixtures.connectionTemplate(
            userID: "f4edc501-056c-4572-9da8-ad63a264a698",
            serverName: "first.example.net",
            path: "/first"
        )
        try await bootstrapper.replaceTemplate(with: originalTemplate, selectedIP: "2606::8")
        let originalGenerated = try Data(contentsOf: paths.generatedConfig)

        let writer = FailingConfigurationWriter(failingCall: 2)
        let failingBootstrapper = AppBootstrapper(
            paths: paths,
            configurationFileWriter: writer.write
        )
        let replacement = try TestConfigFixtures.connectionTemplate(
            userID: "22de5d8d-17f7-40e8-a83f-567ae87c865a",
            serverName: "second.example.net",
            path: "/second"
        )

        do {
            _ = try await failingBootstrapper.replaceTemplate(
                with: replacement,
                selectedIP: "2606::9"
            )
            XCTFail("Expected the injected template write failure")
        } catch {
            XCTAssertEqual(error as? ConfigurationWriterTestError, .injected)
        }

        XCTAssertEqual(try Data(contentsOf: paths.templateConfig), originalTemplate)
        XCTAssertEqual(try Data(contentsOf: paths.generatedConfig), originalGenerated)
        XCTAssertEqual(writer.callCount, 2)
    }

    func testPrepareDefaultsRecoversPreparedConfigurationTransaction() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        let originalTemplate = try TestConfigFixtures.connectionTemplate(
            userID: "f4edc501-056c-4572-9da8-ad63a264a698",
            serverName: "first.example.net",
            path: "/first"
        )
        try await bootstrapper.replaceTemplate(with: originalTemplate, selectedIP: "2606::8")
        let originalGenerated = try Data(contentsOf: paths.generatedConfig)

        try writePreparedConfigurationTransaction(
            paths: paths,
            templateBackup: originalTemplate,
            generatedBackup: originalGenerated
        )
        let replacement = try TestConfigFixtures.connectionTemplate(
            userID: "22de5d8d-17f7-40e8-a83f-567ae87c865a",
            serverName: "second.example.net",
            path: "/second"
        )
        try replacement.write(to: paths.templateConfig, options: .atomic)
        try ConfigTemplate.replacingAddress(in: replacement, with: "2606::9")
            .write(to: paths.generatedConfig, options: .atomic)

        try await AppBootstrapper(paths: paths).prepareDefaults()

        XCTAssertEqual(try Data(contentsOf: paths.templateConfig), originalTemplate)
        XCTAssertEqual(try Data(contentsOf: paths.generatedConfig), originalGenerated)
        XCTAssertEqual(try permissions(of: paths.templateConfig), 0o600)
        XCTAssertEqual(try permissions(of: paths.generatedConfig), 0o600)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: paths.data.appendingPathComponent(".configuration-transaction").path
            )
        )
    }

    func testRecoveryRestoresOriginallyMissingGeneratedConfiguration() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        let originalTemplate = try Data(contentsOf: paths.templateConfig)
        try writePreparedConfigurationTransaction(
            paths: paths,
            templateBackup: originalTemplate,
            generatedBackup: nil
        )
        let replacement = try TestConfigFixtures.connectionTemplate(
            userID: "22de5d8d-17f7-40e8-a83f-567ae87c865a",
            serverName: "second.example.net",
            path: "/second"
        )
        try replacement.write(to: paths.templateConfig, options: .atomic)
        try ConfigTemplate.replacingAddress(in: replacement, with: "2606::9")
            .write(to: paths.generatedConfig, options: .atomic)

        try await AppBootstrapper(paths: paths).prepareDefaults()

        XCTAssertEqual(try Data(contentsOf: paths.templateConfig), originalTemplate)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.generatedConfig.path))
    }

    func testRecoveryRejectsSymbolicLinkedTransactionDirectory() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()

        let externalDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "AppBootstrapperExternalTransaction-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: externalDirectory) }
        try FileManager.default.createDirectory(
            at: externalDirectory,
            withIntermediateDirectories: false
        )
        let sentinel = externalDirectory.appendingPathComponent("sentinel")
        try Data("keep".utf8).write(to: sentinel)
        let transactionDirectory = paths.data.appendingPathComponent(
            ".configuration-transaction",
            isDirectory: true
        )
        try FileManager.default.createSymbolicLink(
            at: transactionDirectory,
            withDestinationURL: externalDirectory
        )

        do {
            try await bootstrapper.prepareDefaults()
            XCTFail("Expected a symbolic-linked transaction directory to be rejected")
        } catch let error as AppBootstrapperError {
            guard case .configurationRecoveryFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep".utf8))
    }

    func testRecoveryRejectsSymbolicLinkedManifest() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()

        let transactionDirectory = paths.data.appendingPathComponent(
            ".configuration-transaction",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: transactionDirectory,
            withIntermediateDirectories: false
        )
        let externalManifest = paths.root.appendingPathComponent("external-manifest.json")
        try Data(#"{"state":"committed","templateExisted":true,"generatedExisted":false}"#.utf8)
            .write(to: externalManifest)
        try FileManager.default.createSymbolicLink(
            at: transactionDirectory.appendingPathComponent("manifest.json"),
            withDestinationURL: externalManifest
        )

        do {
            try await bootstrapper.prepareDefaults()
            XCTFail("Expected a symbolic-linked transaction manifest to be rejected")
        } catch let error as AppBootstrapperError {
            guard case .configurationRecoveryFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalManifest.path))
    }

    func testEnsureConfigRepairsPermissionsAndRejectsSymbolicLinks() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        try await bootstrapper.writeConfig(ip: "2606::8")
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o644)],
            ofItemAtPath: paths.generatedConfig.path
        )

        let rewritten = try await bootstrapper.ensureConfig(ip: "2606::8")
        XCTAssertFalse(rewritten)
        XCTAssertEqual(try permissions(of: paths.generatedConfig), 0o600)

        try FileManager.default.removeItem(at: paths.generatedConfig)
        try FileManager.default.createSymbolicLink(
            at: paths.generatedConfig,
            withDestinationURL: paths.templateConfig
        )
        do {
            _ = try await bootstrapper.ensureConfig(ip: "2606::8")
            XCTFail("Expected a generated-config symbolic link to be rejected")
        } catch let error as AppBootstrapperError {
            XCTAssertEqual(error, .invalidConfigurationFile(paths.generatedConfig))
        }
    }

    func testPrepareConfigForLaunchRebuildsConnectionDetailsWhenIPIsUnchanged() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        let firstTemplate = try TestConfigFixtures.connectionTemplate(
            userID: "f4edc501-056c-4572-9da8-ad63a264a698",
            serverName: "first.example.net",
            path: "/first"
        )
        try await bootstrapper.replaceTemplate(with: firstTemplate)
        let endpoint = try await bootstrapper.prepareConfigForLaunch(ip: "2606::8")
        XCTAssertEqual(endpoint, ProxyEndpoint())

        let secondTemplate = try TestConfigFixtures.connectionTemplate(
            userID: "22de5d8d-17f7-40e8-a83f-567ae87c865a",
            serverName: "second.example.net",
            path: "/second"
        )
        try secondTemplate.write(to: paths.templateConfig, options: .atomic)

        try await bootstrapper.prepareConfigForLaunch(ip: "2606::8")

        let generated = String(
            decoding: try Data(contentsOf: paths.generatedConfig),
            as: UTF8.self
        )
        XCTAssertTrue(generated.contains("22de5d8d-17f7-40e8-a83f-567ae87c865a"))
        XCTAssertTrue(generated.contains("second.example.net"))
        XCTAssertTrue(generated.contains("/second"))
        XCTAssertFalse(generated.contains("f4edc501-056c-4572-9da8-ad63a264a698"))
        XCTAssertFalse(generated.contains("first.example.net"))
        XCTAssertFalse(generated.contains("/first"))
        XCTAssertEqual(ConfigTemplate.address(in: Data(generated.utf8)), "2606::8")
    }

    func testPrepareConfigForLaunchBuildsFromSplitServerAndLocalSettings() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()

        let splitServer = try ConfigTemplate.serverConfiguration(
            from: TestConfigFixtures.connectionTemplate(
                userID: "75bc54ec-d578-445a-9608-aec3f1b91c25",
                serverName: "split.example.net",
                path: "/split"
            )
        )
        let splitLocal = LocalProxyConfiguration(
            listenAddress: "127.0.0.2",
            port: 18_080,
            bypassPrivateNetworks: false,
            routingMode: .global
        )
        try splitServer.write(to: paths.serverConfig, options: .atomic)
        try JSONEncoder.pretty.encode(splitLocal).write(
            to: paths.localProxyConfig,
            options: .atomic
        )

        let endpoint = try await bootstrapper.prepareConfigForLaunch(ip: "2606::80")

        XCTAssertEqual(endpoint, splitLocal.endpoint)
        let generated = try Data(contentsOf: paths.generatedConfig)
        let generatedText = String(decoding: generated, as: UTF8.self)
        XCTAssertTrue(generatedText.contains("75bc54ec-d578-445a-9608-aec3f1b91c25"))
        XCTAssertTrue(generatedText.contains("split.example.net"))
        XCTAssertTrue(generatedText.contains("/split"))
        XCTAssertEqual(ConfigTemplate.address(in: generated), "2606::80")
        XCTAssertEqual(
            try ConfigTemplate.localConfiguration(from: generated),
            splitLocal
        )
    }

    func testDirectModeLaunchesWithoutServerOrSelectedIP() async throws {
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
        try FileManager.default.removeItem(at: paths.serverConfig)

        let endpoint = try await bootstrapper.prepareConfigForLaunch()

        XCTAssertEqual(endpoint, direct.endpoint)
        let generated = try Data(contentsOf: paths.generatedConfig)
        XCTAssertNil(ConfigTemplate.address(in: generated))
        XCTAssertNoThrow(try ConfigTemplate.validateForLaunch(generated))
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: generated) as? [String: Any]
        )
        let outbounds = try XCTUnwrap(object["outbounds"] as? [[String: Any]])
        XCTAssertEqual(outbounds.compactMap { $0["tag"] as? String }, ["direct", "block"])
    }

    func testSynchronizeDirectModeDoesNotRequireServerOrSelectedIP() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        let direct = LocalProxyConfiguration(routingMode: .direct)
        _ = try await bootstrapper.replaceLocalProxyConfiguration(with: direct)
        try FileManager.default.removeItem(at: paths.serverConfig)
        try? FileManager.default.removeItem(at: paths.generatedConfig)

        let configuration = try await bootstrapper.synchronizeConfiguration(selectedIP: nil)

        XCTAssertEqual(configuration.local, direct)
        XCTAssertEqual(configuration.endpoint, direct.endpoint)
        XCTAssertNil(configuration.effectiveIP)
        XCTAssertNil(configuration.launchIssue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.generatedConfig.path))
    }

    func testSaveLocalProxyPreferenceDoesNotRewriteRuntimeConfiguration() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        try await bootstrapper.writeConfig(ip: "2606::9")
        let templateBefore = try Data(contentsOf: paths.templateConfig)
        let generatedBefore = try Data(contentsOf: paths.generatedConfig)
        var local = try await bootstrapper.loadLocalProxyConfiguration()
        local.systemProxyEnabled = true

        try await bootstrapper.saveLocalProxyPreference(local)

        let savedLocal = try await bootstrapper.loadLocalProxyConfiguration()
        XCTAssertTrue(savedLocal.systemProxyEnabled)
        XCTAssertEqual(try Data(contentsOf: paths.templateConfig), templateBefore)
        XCTAssertEqual(try Data(contentsOf: paths.generatedConfig), generatedBefore)
    }

    private func makePaths() -> AppPaths {
        AppPaths(
            root: FileManager.default.temporaryDirectory
                .appendingPathComponent("AppBootstrapperTests-\(UUID().uuidString)", isDirectory: true)
        )
    }

    private func writePreparedConfigurationTransaction(
        paths: AppPaths,
        templateBackup: Data,
        generatedBackup: Data?
    ) throws {
        let directory = paths.data.appendingPathComponent(
            ".configuration-transaction",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try templateBackup.write(
            to: directory.appendingPathComponent("template.backup.json"),
            options: .atomic
        )
        if let generatedBackup {
            try generatedBackup.write(
                to: directory.appendingPathComponent("config.backup.json"),
                options: .atomic
            )
        }
        let manifest = try JSONSerialization.data(withJSONObject: [
            "state": "prepared",
            "templateExisted": true,
            "generatedExisted": generatedBackup != nil,
        ])
        try manifest.write(
            to: directory.appendingPathComponent("manifest.json"),
            options: .atomic
        )
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

    var callCount: Int {
        lock.withLock { calls }
    }

    func write(_ data: Data, to url: URL) throws {
        try lock.withLock {
            calls += 1
            if calls == failingCall {
                throw ConfigurationWriterTestError.injected
            }
        }
        try data.write(to: url, options: .atomic)
        try FilePermissions.restrictFile(url)
    }
}
