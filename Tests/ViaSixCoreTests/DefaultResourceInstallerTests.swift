import XCTest

@testable import ViaSixCore

final class DefaultResourceInstallerTests: XCTestCase {
    func testInstallCreatesOnlyLocalDefaultsAndNetworkData() throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }

        try DefaultResourceInstaller.install(into: paths)

        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.ipv4List.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.ipv6List.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.localProxyConfig.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.profileConfig.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.legacyServerConfig.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.legacyTemplateConfig.path))

        let local = try JSONDecoder().decode(
            LocalProxyConfiguration.self,
            from: Data(contentsOf: paths.localProxyConfig)
        )
        XCTAssertEqual(local.networkAccessMode, .virtualInterface)
        XCTAssertEqual(local.logLevel, .warning)
    }

    func testInstallPreservesLegacyLocalConfigurationWithoutMigratingIt() throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try paths.prepare()
        let legacy = Data(
            """
            {
              "listenAddress": "127.0.0.1",
              "port": 11451,
              "udpEnabled": true,
              "sniffingEnabled": true,
              "bypassPrivateNetworks": true,
              "logLevel": "none",
              "routingMode": "rule",
              "systemProxyEnabled": true
            }
            """.utf8
        )
        try legacy.write(to: paths.localProxyConfig)

        try DefaultResourceInstaller.install(
            into: paths,
            legacyDigests: .init(
                ipv4: "not-installed"
            )
        )

        let installed = try Data(contentsOf: paths.localProxyConfig)
        XCTAssertEqual(installed, legacy)
        XCTAssertThrowsError(
            try JSONDecoder().decode(LocalProxyConfiguration.self, from: installed)
        )
    }

    func testInstallPreservesCustomizedLocalConfigurationAndLegacyInputs() throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try paths.prepare()
        let customized = try JSONEncoder.pretty.encode(
            LocalProxyConfiguration(
                port: 20_280,
                logLevel: .debug,
                routingMode: .global,
                networkAccessMode: .localProxy,
                systemProxyEnabled: true
            )
        )
        let legacyServer = Data("custom legacy server".utf8)
        try customized.write(to: paths.localProxyConfig)
        try legacyServer.write(to: paths.legacyServerConfig)

        try DefaultResourceInstaller.install(into: paths)

        XCTAssertEqual(try Data(contentsOf: paths.localProxyConfig), customized)
        XCTAssertEqual(try Data(contentsOf: paths.legacyServerConfig), legacyServer)
    }

    func testReplaceIfMatchingLegacyReplacesContentAndRemovesDerivedFiles() throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try paths.prepare()
        let legacy = Data("legacy".utf8)
        let replacement = Data("replacement".utf8)
        try legacy.write(to: paths.localProxyConfig)
        try Data("derived".utf8).write(to: paths.generatedConfig)

        let replaced = try DefaultResourceInstaller.replaceIfMatchingLegacy(
            at: paths.localProxyConfig,
            expectedSHA256: RuntimeSHA256.hexDigest(of: legacy),
            replacement: replacement,
            removingDerivedFiles: [paths.generatedConfig]
        )

        XCTAssertTrue(replaced)
        XCTAssertEqual(try Data(contentsOf: paths.localProxyConfig), replacement)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.generatedConfig.path))
    }

    func testReplaceIfMatchingLegacyPreservesMismatchedContentAndDerivedFiles() throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try paths.prepare()
        let customized = Data("customized".utf8)
        let generated = Data("derived".utf8)
        try customized.write(to: paths.localProxyConfig)
        try generated.write(to: paths.generatedConfig)

        let replaced = try DefaultResourceInstaller.replaceIfMatchingLegacy(
            at: paths.localProxyConfig,
            expectedSHA256: RuntimeSHA256.hexDigest(of: Data("different".utf8)),
            replacement: Data("replacement".utf8),
            removingDerivedFiles: [paths.generatedConfig]
        )

        XCTAssertFalse(replaced)
        XCTAssertEqual(try Data(contentsOf: paths.localProxyConfig), customized)
        XCTAssertEqual(try Data(contentsOf: paths.generatedConfig), generated)
    }

    func testInstallRejectsSymbolicLinkResourceDestinationsWithoutFollowingTarget() throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try paths.prepare()

        let outside = paths.data.appendingPathComponent("outside-ip.txt")
        let planted = Data("attacker-controlled-list\n".utf8)
        try planted.write(to: outside)
        try FileManager.default.createSymbolicLink(at: paths.ipv4List, withDestinationURL: outside)

        do {
            try DefaultResourceInstaller.install(into: paths)
            XCTFail("Expected symbolic-link resource destination to be rejected")
        } catch let error as ResourceError {
            guard case .unsafeDestination(let url, let reason) = error else {
                return XCTFail("Unexpected ResourceError: \(error)")
            }
            XCTAssertEqual(url, paths.ipv4List)
            XCTAssertTrue(reason.contains("符号链接"))
        }

        XCTAssertEqual(try Data(contentsOf: outside), planted)
    }

    private func makePaths() -> AppPaths {
        AppPaths(
            root: FileManager.default.temporaryDirectory.appendingPathComponent(
                "DefaultResourceInstallerTests-\(UUID().uuidString)",
                isDirectory: true
            )
        )
    }
}
