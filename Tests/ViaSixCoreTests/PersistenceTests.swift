import XCTest

@testable import ViaSixCore

final class PersistenceTests: XCTestCase {
    func testDefaultResourcesInstallWithoutOverwritingUserTemplate() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViaSixTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root)

        try DefaultResourceInstaller.install(into: paths)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.ipv4List.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.ipv6List.path))
        XCTAssertEqual(
            ConfigTemplate.address(in: try Data(contentsOf: paths.templateConfig)),
            "2001:db8::1"
        )

        let custom = Data("custom-template".utf8)
        try custom.write(to: paths.templateConfig, options: .atomic)
        try DefaultResourceInstaller.install(into: paths)
        XCTAssertEqual(try Data(contentsOf: paths.templateConfig), custom)
    }

    func testPreferencesRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViaSixTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root)
        let store = PreferencesStore(fileURL: paths.preferences)
        let defaults = UserPreferences(parameters: .defaults(ipv6File: paths.ipv6List))
        var changed = defaults
        changed.selectedIP = "2606::1"
        changed.parameters.threads = 64
        changed.lastSuccessfulSpeedTestParameters = changed.parameters
        changed.exitIPEndpoint = "https://status.example.test/ip"
        changed.exitIPDetectionMode = .ipv4

        try await store.save(changed)
        let loaded = try await store.load(defaults: defaults)
        XCTAssertEqual(loaded.preferences, changed)
        XCTAssertEqual(loaded.source, .persisted)
    }

    func testMissingPreferencesReturnDefaultsWithoutCreatingAFile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViaSixTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root)
        let store = PreferencesStore(fileURL: paths.preferences)
        let defaults = UserPreferences(parameters: .defaults(ipv6File: paths.ipv6List))

        let loaded = try await store.load(defaults: defaults)

        XCTAssertEqual(loaded.preferences, defaults)
        XCTAssertEqual(loaded.source, .missing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.preferences.path))
    }

    func testCorruptPreferencesAreMovedToUniqueBackupsBeforeReturningDefaults() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViaSixTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root)
        try paths.prepare()
        let store = PreferencesStore(fileURL: paths.preferences)
        let defaults = UserPreferences(parameters: .defaults(ipv6File: paths.ipv6List))
        let firstCorruptData = Data("not-json-one".utf8)
        try firstCorruptData.write(to: paths.preferences)

        let firstLoad = try await store.load(defaults: defaults)
        let firstBackupURL = try recoveredBackupURL(from: firstLoad)

        XCTAssertEqual(firstLoad.preferences, defaults)
        XCTAssertEqual(try Data(contentsOf: firstBackupURL), firstCorruptData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.preferences.path))
        XCTAssertEqual(firstBackupURL.deletingLastPathComponent(), paths.preferences.deletingLastPathComponent())
        XCTAssertTrue(firstBackupURL.lastPathComponent.hasPrefix("preferences.corrupt-"))
        XCTAssertTrue(firstBackupURL.lastPathComponent.hasSuffix(".json"))

        let secondCorruptData = Data("not-json-two".utf8)
        try secondCorruptData.write(to: paths.preferences)
        let secondLoad = try await store.load(defaults: defaults)
        let secondBackupURL = try recoveredBackupURL(from: secondLoad)

        XCTAssertNotEqual(secondBackupURL, firstBackupURL)
        XCTAssertEqual(try Data(contentsOf: firstBackupURL), firstCorruptData)
        XCTAssertEqual(try Data(contentsOf: secondBackupURL), secondCorruptData)
    }

    func testPreferencesReadFailureThrowsWithoutMovingTheOriginal() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViaSixTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root)
        try paths.prepare()
        try FileManager.default.createDirectory(at: paths.preferences, withIntermediateDirectories: false)
        let store = PreferencesStore(fileURL: paths.preferences)
        let defaults = UserPreferences(parameters: .defaults(ipv6File: paths.ipv6List))

        do {
            _ = try await store.load(defaults: defaults)
            XCTFail("Expected an unreadable preferences file to throw")
        } catch {
            guard case .unreadableFile(let url, _) = error as? PreferencesStoreError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(url, paths.preferences)
        }

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

    func testApplicationDataUsesOwnerOnlyPermissions() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViaSixTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root)

        try DefaultResourceInstaller.install(into: paths)
        let store = PreferencesStore(fileURL: paths.preferences)
        try await store.save(UserPreferences(parameters: .defaults(ipv6File: paths.ipv6List)))

        for directory in [paths.root, paths.data, paths.runtime, paths.logs] {
            XCTAssertEqual(try permissions(of: directory), 0o700)
        }
        for file in [paths.preferences, paths.ipv4List, paths.ipv6List, paths.templateConfig] {
            XCTAssertEqual(try permissions(of: file), 0o600)
        }
    }

    func testPreferencesDecodeOlderPayloadWithNewFieldsMissing() throws {
        let parameters = SpeedTestParameters(ipFile: "/tmp/ipv6.txt")
        let encodedParameters = try JSONEncoder().encode(parameters)
        let parametersObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedParameters))
        let legacy = try JSONSerialization.data(withJSONObject: ["parameters": parametersObject])

        let decoded = try JSONDecoder().decode(UserPreferences.self, from: legacy)
        XCTAssertEqual(decoded.ipSourceMode, .ipv6)
        XCTAssertEqual(decoded.selectedIP, "")
        XCTAssertEqual(decoded.cfstPath, "")
        XCTAssertEqual(decoded.xrayPath, "")
        XCTAssertEqual(decoded.exitIPEndpoint, AppMetadata.defaultExitIPEndpoint)
        XCTAssertEqual(decoded.exitIPDetectionMode, .automatic)
        XCTAssertNil(decoded.lastSuccessfulSpeedTestParameters)
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue & 0o777
    }

    private func recoveredBackupURL(from result: PreferencesLoadResult) throws -> URL {
        guard case .recoveredCorruptFile(let backupURL) = result.source else {
            XCTFail("Expected a recovered corrupt preferences result")
            throw CocoaError(.coderInvalidValue)
        }
        return backupURL
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
}
