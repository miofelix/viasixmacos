import Foundation
import XCTest

@testable import ViaSixCore

final class LocalProxyConfigurationTests: XCTestCase {
    func testLegacyConfigurationWithoutSchemaVersionIsRejected() throws {
        let legacy = Data(
            #"{"listenAddress":"127.0.0.2","port":18080,"udpEnabled":false,"sniffingEnabled":false,"bypassPrivateNetworks":false,"logLevel":"info","routingMode":"global","networkAccessMode":"localProxy","ipv6TransportPolicy":"compatibility"}"#
                .utf8
        )

        XCTAssertThrowsError(
            try JSONDecoder().decode(LocalProxyConfiguration.self, from: legacy)
        )
    }

    func testNewInstallationDoesNotPersistRemovedTransportPolicy() throws {
        let paths = AppPaths(
            root: FileManager.default.temporaryDirectory.appendingPathComponent(
                "LocalProxyConfigurationTests-\(UUID().uuidString)",
                isDirectory: true
            )
        )
        defer { try? FileManager.default.removeItem(at: paths.root) }

        try DefaultResourceInstaller.install(into: paths)
        let data = try Data(contentsOf: paths.localProxyConfig)
        let local = try JSONDecoder().decode(LocalProxyConfiguration.self, from: data)

        XCTAssertEqual(local.networkAccessMode, .virtualInterface)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("ipv6TransportPolicy"))
    }

    func testControllerPortMustBeValidAndDistinctFromProxyPort() throws {
        XCTAssertThrowsError(
            try LocalProxyConfiguration(controllerPort: 0).validated()
        ) { error in
            XCTAssertEqual(error as? LocalProxyConfigurationError, .invalidControllerPort)
        }

        XCTAssertThrowsError(
            try LocalProxyConfiguration(port: 9_090, controllerPort: 9_090).validated()
        ) { error in
            XCTAssertEqual(error as? LocalProxyConfigurationError, .conflictingControllerPort)
        }
    }

    func testTunFieldsRoundTrip() throws {
        let configured = LocalProxyConfiguration(
            networkAccessMode: .virtualInterface,
            tunStack: .gvisor,
            tunMTU: 1_400,
            tunStrictRoute: true
        )
        let roundTrip = try JSONDecoder().decode(
            LocalProxyConfiguration.self,
            from: JSONEncoder().encode(configured)
        )
        XCTAssertEqual(roundTrip, configured)
    }

    func testTunMTUValidationUsesSafePlatformRange() throws {
        for mtu in [1_279, 9_001] {
            XCTAssertThrowsError(
                try LocalProxyConfiguration(
                    networkAccessMode: .virtualInterface,
                    tunMTU: mtu
                ).validated()
            ) { error in
                XCTAssertEqual(error as? LocalProxyConfigurationError, .invalidTunMTU)
            }
        }
        XCTAssertNoThrow(
            try LocalProxyConfiguration(
                networkAccessMode: .virtualInterface,
                tunMTU: 1_280
            ).validated()
        )
        XCTAssertNoThrow(
            try LocalProxyConfiguration(
                networkAccessMode: .virtualInterface,
                tunMTU: 9_000
            ).validated()
        )
    }

    func testLegacyEnumAliasesAndMissingFieldsAreRejected() throws {
        for payload in [
            #"{"version":1,"logLevel":"none"}"#,
            #"{"version":1,"routingMode":"rule-based"}"#,
            #"{"version":1,"networkAccessMode":"tun"}"#,
        ] {
            XCTAssertThrowsError(
                try JSONDecoder().decode(
                    LocalProxyConfiguration.self,
                    from: Data(payload.utf8)
                )
            )
        }
    }

    func testSystemProxyAndTunPreferencesRoundTripIndependently() throws {
        let configured = LocalProxyConfiguration(
            networkAccessMode: .virtualInterface,
            systemProxyEnabled: true
        )

        let roundTrip = try JSONDecoder().decode(
            LocalProxyConfiguration.self,
            from: JSONEncoder().encode(configured)
        )

        XCTAssertEqual(roundTrip.networkAccessMode, .virtualInterface)
        XCTAssertTrue(roundTrip.systemProxyEnabled)
    }

}
