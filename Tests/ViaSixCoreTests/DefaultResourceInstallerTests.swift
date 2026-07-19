import XCTest
@testable import ViaSixCore

final class DefaultResourceInstallerTests: XCTestCase {
    func testInstallMigratesExactLegacyTemplateAndRemovesGeneratedConfig() throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try paths.prepare()
        try TestConfigFixtures.legacyBundledTemplate.write(to: paths.templateConfig)
        try Data("stale generated config".utf8).write(to: paths.generatedConfig)

        try DefaultResourceInstaller.install(into: paths)

        let installed = try Data(contentsOf: paths.templateConfig)
        let installedText = String(decoding: installed, as: UTF8.self)
        let legacyValues = try TestConfigFixtures.legacyConnectionValues()
        XCTAssertNotEqual(installed, TestConfigFixtures.legacyBundledTemplate)
        XCTAssertFalse(installedText.contains(legacyValues.userID))
        XCTAssertFalse(installedText.contains(legacyValues.serverName))
        XCTAssertTrue(installedText.contains(ConfigTemplate.placeholderUserID))
        XCTAssertTrue(installedText.contains(ConfigTemplate.placeholderServerName))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.generatedConfig.path))
    }

    func testInstallPreservesCustomizedTemplateAndGeneratedConfig() throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try paths.prepare()
        let customizedTemplate = try TestConfigFixtures.connectionTemplate(
            userID: "2ea73587-acfa-4475-91ec-dcf25729644f",
            serverName: "customer.example.net",
            path: "/customer"
        )
        let generatedConfig = Data("customer generated config".utf8)
        try customizedTemplate.write(to: paths.templateConfig)
        try generatedConfig.write(to: paths.generatedConfig)

        try DefaultResourceInstaller.install(into: paths)

        XCTAssertEqual(try Data(contentsOf: paths.templateConfig), customizedTemplate)
        XCTAssertEqual(try Data(contentsOf: paths.generatedConfig), generatedConfig)
    }

    func testReplaceIfMatchingLegacyReplacesContentAndRemovesDerivedFiles() throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try paths.prepare()
        let replacement = Data("replacement".utf8)
        try TestConfigFixtures.legacyBundledTemplate.write(to: paths.templateConfig)
        try Data("derived".utf8).write(to: paths.generatedConfig)

        let replaced = try DefaultResourceInstaller.replaceIfMatchingLegacy(
            at: paths.templateConfig,
            expectedSHA256: DefaultResourceInstaller.legacyTemplateSHA256,
            replacement: replacement,
            removingDerivedFiles: [paths.generatedConfig]
        )

        XCTAssertTrue(replaced)
        XCTAssertEqual(try Data(contentsOf: paths.templateConfig), replacement)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.generatedConfig.path))
    }

    func testReplaceIfMatchingLegacyPreservesMismatchedContentAndDerivedFiles() throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try paths.prepare()
        let customizedTemplate = Data("customized".utf8)
        let generatedConfig = Data("derived".utf8)
        try customizedTemplate.write(to: paths.templateConfig)
        try generatedConfig.write(to: paths.generatedConfig)

        let replaced = try DefaultResourceInstaller.replaceIfMatchingLegacy(
            at: paths.templateConfig,
            expectedSHA256: DefaultResourceInstaller.legacyTemplateSHA256,
            replacement: Data("replacement".utf8),
            removingDerivedFiles: [paths.generatedConfig]
        )

        XCTAssertFalse(replaced)
        XCTAssertEqual(try Data(contentsOf: paths.templateConfig), customizedTemplate)
        XCTAssertEqual(try Data(contentsOf: paths.generatedConfig), generatedConfig)
    }

    private func makePaths() -> AppPaths {
        AppPaths(
            root: FileManager.default.temporaryDirectory
                .appendingPathComponent("DefaultResourceInstallerTests-\(UUID().uuidString)", isDirectory: true)
        )
    }
}
