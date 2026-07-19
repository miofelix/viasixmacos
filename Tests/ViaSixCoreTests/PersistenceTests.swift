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

        try await store.save(changed)
        let loaded = await store.load(defaults: defaults)
        XCTAssertEqual(loaded, changed)
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
    }
}
