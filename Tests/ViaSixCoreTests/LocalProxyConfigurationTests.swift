import Foundation
import XCTest

@testable import ViaSixCore

final class LocalProxyConfigurationTests: XCTestCase {
    func testLegacyLocalProxyConfigurationDefaultsToRuleMode() throws {
        let legacy = Data(
            #"{"listenAddress":"127.0.0.2","port":18080,"udpEnabled":false,"sniffingEnabled":false,"bypassPrivateNetworks":false,"logLevel":"info"}"#
                .utf8
        )

        let local = try JSONDecoder().decode(LocalProxyConfiguration.self, from: legacy)

        XCTAssertEqual(local.routingMode, .rule)
        XCTAssertEqual(local.networkAccessMode, .localProxy)
        XCTAssertEqual(local.controllerPort, AppMetadata.controllerPort)
        XCTAssertEqual(local.endpoint, ProxyEndpoint(host: "127.0.0.2", port: 18_080))
        XCTAssertFalse(local.udpEnabled)
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

    func testTunFieldsRoundTripAndDefaultForOlderPayloads() throws {
        let legacy = try XCTUnwrap(
            #"{"networkAccessMode":"virtualInterface"}"#.data(using: .utf8)
        )
        let decoded = try JSONDecoder().decode(LocalProxyConfiguration.self, from: legacy)
        XCTAssertEqual(decoded.tunStack, .mixed)
        XCTAssertEqual(decoded.tunMTU, 1_500)
        XCTAssertFalse(decoded.tunStrictRoute)

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

    func testLegacyLocalProxyFieldsMigrateToNeutralValues() throws {
        let legacy = Data(
            #"{"logLevel":"none","systemProxyEnabled":true}"#.utf8
        )

        let local = try JSONDecoder().decode(LocalProxyConfiguration.self, from: legacy)

        XCTAssertEqual(local.logLevel, .silent)
        XCTAssertEqual(local.networkAccessMode, .localProxy)
        XCTAssertTrue(local.systemProxyEnabled)
        let encoded = try JSONEncoder().encode(local)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertEqual(object["logLevel"] as? String, "silent")
        XCTAssertEqual(object["networkAccessMode"] as? String, "localProxy")
        XCTAssertEqual(object["systemProxyEnabled"] as? Bool, true)
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

    func testLegacyXrayLocalMigratorPreservesListenerAndRulePreferences() throws {
        let data = try legacyDocument(
            listenAddress: "127.0.0.2",
            port: 18_081,
            udpEnabled: false,
            sniffingEnabled: true,
            logLevel: "none",
            rules: [
                [
                    "type": "field",
                    "ip": ["geoip:private"],
                    "outboundTag": "direct",
                ]
            ]
        )

        let local = try XCTUnwrap(
            LegacyXrayLocalConfigurationMigrator.configuration(from: data)
        )

        XCTAssertEqual(local.endpoint, ProxyEndpoint(host: "127.0.0.2", port: 18_081))
        XCTAssertFalse(local.udpEnabled)
        XCTAssertTrue(local.sniffingEnabled)
        XCTAssertTrue(local.bypassPrivateNetworks)
        XCTAssertEqual(local.logLevel, .silent)
        XCTAssertEqual(local.routingMode, .rule)
        XCTAssertEqual(local.networkAccessMode, .localProxy)
    }

    func testLegacyXrayLocalMigratorInfersGlobalAndDirectModes() throws {
        let global = try legacyDocument(
            rules: [catchAllRule(outboundTag: "proxy")]
        )
        XCTAssertEqual(
            LegacyXrayLocalConfigurationMigrator.configuration(from: global)?.routingMode,
            .global
        )

        let direct = try legacyDocument(
            rules: [catchAllRule(outboundTag: "direct")]
        )
        XCTAssertEqual(
            LegacyXrayLocalConfigurationMigrator.configuration(from: direct)?.routingMode,
            .direct
        )

        var constrainedRule = catchAllRule(outboundTag: "direct")
        constrainedRule["domain"] = ["example.com"]
        let constrained = try legacyDocument(rules: [constrainedRule])
        XCTAssertEqual(
            LegacyXrayLocalConfigurationMigrator.configuration(from: constrained)?.routingMode,
            .rule
        )

        let directOnly = try legacyDocument(
            rules: [],
            includeProxyOutbound: false
        )
        XCTAssertEqual(
            LegacyXrayLocalConfigurationMigrator.configuration(from: directOnly)?.routingMode,
            .direct
        )
    }

    func testLegacyXrayLocalMigratorFailsClosedForUntrustedDocuments() throws {
        XCTAssertNil(
            LegacyXrayLocalConfigurationMigrator.configuration(
                from: Data("not-json".utf8)
            )
        )
        XCTAssertNil(
            LegacyXrayLocalConfigurationMigrator.configuration(
                from: Data(repeating: 0x20, count: 8 * 1_024 * 1_024 + 1)
            )
        )

        let exposed = try legacyDocument(listenAddress: "0.0.0.0")
        XCTAssertNil(LegacyXrayLocalConfigurationMigrator.configuration(from: exposed))

        let invalidPort = try legacyDocument(port: 65_536)
        XCTAssertNil(LegacyXrayLocalConfigurationMigrator.configuration(from: invalidPort))

        let missingMixedInbound = try JSONSerialization.data(withJSONObject: [
            "inbounds": [["protocol": "socks", "listen": "127.0.0.1", "port": 10_080]]
        ])
        XCTAssertNil(
            LegacyXrayLocalConfigurationMigrator.configuration(from: missingMixedInbound)
        )
    }

    private func legacyDocument(
        listenAddress: String = "127.0.0.1",
        port: Int = 11_451,
        udpEnabled: Bool = true,
        sniffingEnabled: Bool = false,
        logLevel: String = "warning",
        rules: [[String: Any]] = [],
        includeProxyOutbound: Bool = true
    ) throws -> Data {
        var outbounds: [[String: Any]] = []
        if includeProxyOutbound {
            outbounds.append(["tag": "proxy", "protocol": "vless"])
        }
        outbounds.append(["tag": "direct", "protocol": "freedom"])

        return try JSONSerialization.data(withJSONObject: [
            "log": ["loglevel": logLevel],
            "inbounds": [
                [
                    "protocol": "mixed",
                    "listen": listenAddress,
                    "port": port,
                    "settings": ["udp": udpEnabled],
                    "sniffing": ["enabled": sniffingEnabled],
                ]
            ],
            "outbounds": outbounds,
            "routing": ["rules": rules],
        ])
    }

    private func catchAllRule(outboundTag: String) -> [String: Any] {
        [
            "type": "field",
            "network": "tcp,udp",
            "outboundTag": outboundTag,
        ]
    }
}
