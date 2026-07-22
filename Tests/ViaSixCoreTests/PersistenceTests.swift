import XCTest

@testable import ViaSixCore

final class PersistenceTests: XCTestCase {
    func testDefaultResourcesDoNotCreateOrOverwriteNativeProfile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViaSixTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root)

        try DefaultResourceInstaller.install(into: paths)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.ipv4List.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.ipv6List.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.profileConfig.path))

        let custom = Data(
            """
            proxies:
              - name: custom
                type: ss
                server: server.example
                port: 8388
                cipher: aes-128-gcm
                password: secret
            """.utf8
        )
        try custom.write(to: paths.profileConfig, options: .atomic)
        try DefaultResourceInstaller.install(into: paths)
        XCTAssertEqual(try Data(contentsOf: paths.profileConfig), custom)
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
        changed.mihomoPath = "/opt/viasix/mihomo"

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

    func testPreferencesSymbolicLinkIsRejectedWithoutFollowingOrMovingTarget() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViaSixTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root)
        try paths.prepare()

        let outside = root.appendingPathComponent("outside-preferences.json")
        let sensitive = Data(#"{"selectedIP":"should-not-load"}"#.utf8)
        try sensitive.write(to: outside)
        try FileManager.default.createSymbolicLink(at: paths.preferences, withDestinationURL: outside)

        let store = PreferencesStore(fileURL: paths.preferences)
        let defaults = UserPreferences(parameters: .defaults(ipv6File: paths.ipv6List))

        do {
            _ = try await store.load(defaults: defaults)
            XCTFail("Expected symbolic-link preferences to throw")
        } catch {
            guard case .unreadableFile(let url, let reason) = error as? PreferencesStoreError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(url, paths.preferences)
            XCTAssertTrue(reason.contains("符号链接"))
        }

        do {
            try await store.save(defaults)
            XCTFail("Expected save through symbolic link to throw")
        } catch {
            guard case .unreadableFile = error as? PreferencesStoreError else {
                return XCTFail("Unexpected save error: \(error)")
            }
        }

        XCTAssertEqual(try Data(contentsOf: outside), sensitive)
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

        for directory in [
            paths.root,
            paths.data,
            paths.runtime,
            paths.logs,
            paths.mihomoHome,
            paths.mihomoProviders,
            paths.mihomoRules,
        ] {
            XCTAssertEqual(try permissions(of: directory), 0o700)
        }
        for file in [paths.preferences, paths.ipv4List, paths.ipv6List, paths.localProxyConfig] {
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
        XCTAssertEqual(decoded.mihomoPath, "")
        XCTAssertEqual(decoded.exitIPEndpoint, AppMetadata.defaultExitIPEndpoint)
        XCTAssertEqual(decoded.exitIPDetectionMode, .automatic)
        XCTAssertNil(decoded.lastSuccessfulSpeedTestParameters)
    }

    func testPreferencesNeverMigrateLegacyXrayExecutablePath() throws {
        let parameters = SpeedTestParameters(ipFile: "/tmp/ipv6.txt")
        let parametersData = try JSONEncoder().encode(parameters)
        let parametersObject = try XCTUnwrap(JSONSerialization.jsonObject(with: parametersData))
        let legacy = try JSONSerialization.data(withJSONObject: [
            "parameters": parametersObject,
            "xrayPath": "/Users/example/Runtime/xray",
        ])

        let decoded = try JSONDecoder().decode(UserPreferences.self, from: legacy)
        XCTAssertEqual(decoded.mihomoPath, "")

        let encoded = try JSONEncoder().encode(decoded)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertNil(object["xrayPath"])
        XCTAssertEqual(object["mihomoPath"] as? String, "")
    }

    func testPreferencesMigrateLegacyAndUnknownEnumValuesWithoutDiscardingOtherFields() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViaSixTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root)
        try paths.prepare()

        let parameters = SpeedTestParameters(ipRange: "2606:4700::/32")
        let encodedParameters = try JSONEncoder().encode(parameters)
        let parametersObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedParameters))
        let payload = try JSONSerialization.data(withJSONObject: [
            "parameters": parametersObject,
            "ipSourceMode": "customRange",
            "selectedIP": "2606:4700::1",
            "exitIPDetectionMode": "future-mode",
        ])
        try payload.write(to: paths.preferences)

        let store = PreferencesStore(fileURL: paths.preferences)
        let defaults = UserPreferences(parameters: .defaults(ipv6File: paths.ipv6List))
        let loaded = try await store.load(defaults: defaults)

        XCTAssertEqual(loaded.source, .persisted)
        XCTAssertEqual(loaded.preferences.ipSourceMode, .range)
        XCTAssertEqual(loaded.preferences.exitIPDetectionMode, .automatic)
        XCTAssertEqual(loaded.preferences.selectedIP, "2606:4700::1")
        XCTAssertEqual(loaded.preferences.parameters.ipRange, "2606:4700::/32")

        let futurePayload = try JSONSerialization.data(withJSONObject: [
            "parameters": parametersObject,
            "ipSourceMode": "future-source",
            "selectedIP": "2606:4700::2",
            "exitIPDetectionMode": "auto",
        ])
        let futurePreferences = try JSONDecoder().decode(
            UserPreferences.self,
            from: futurePayload
        )
        XCTAssertEqual(futurePreferences.ipSourceMode, .ipv6)
        XCTAssertEqual(futurePreferences.exitIPDetectionMode, .automatic)
        XCTAssertEqual(futurePreferences.selectedIP, "2606:4700::2")
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
