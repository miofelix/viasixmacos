import Foundation
import XCTest

@testable import ViaSixMihomoConfig

final class LegacyXrayConfigurationMigratorTests: XCTestCase {
    func testMigratesVLESSWebSocketTLSWithoutChangingTLSIdentity() throws {
        let legacy: [String: Any] = [
            "outbounds": [
                [
                    "tag": "proxy",
                    "protocol": "vless",
                    "settings": [
                        "vnext": [
                            [
                                "address": "origin.test",
                                "port": 443,
                                "users": [
                                    [
                                        "id": "11111111-1111-1111-1111-111111111111",
                                        "encryption": "none",
                                        "flow": "",
                                    ]
                                ],
                            ]
                        ]
                    ],
                    "streamSettings": [
                        "network": "ws",
                        "security": "tls",
                        "wsSettings": [
                            "path": "/ws",
                            "headers": ["Host": "cdn.test"],
                        ],
                        "tlsSettings": [
                            "serverName": "origin.test",
                            "allowInsecure": false,
                            "fingerprint": "chrome",
                        ],
                    ],
                ],
                ["tag": "direct", "protocol": "freedom"],
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: legacy)

        let profile = try LegacyXrayConfigurationMigrator.profile(from: data)
        let migrated = try LegacyXrayConfigurationMigrator.serverConfiguration(from: data)
        let parsed = try migrated.primaryProfile()

        XCTAssertEqual(profile.protocolName, .vless)
        XCTAssertEqual(profile.serverAddress, "origin.test")
        XCTAssertEqual(profile.serverName, "origin.test")
        XCTAssertEqual(profile.host, "cdn.test")
        XCTAssertEqual(profile.path, "/ws")
        XCTAssertEqual(parsed, profile)
    }

    func testMigratesVMessTrojanAndShadowsocks() throws {
        let vmess = try migrate(
            protocolName: "vmess",
            settings: [
                "vnext": [
                    [
                        "address": "vmess.test",
                        "port": 443,
                        "users": [
                            [
                                "id": "22222222-2222-2222-2222-222222222222",
                                "alterId": 0,
                                "security": "auto",
                            ]
                        ],
                    ]
                ]
            ]
        )
        let trojan = try migrate(
            protocolName: "trojan",
            settings: [
                "servers": [
                    ["address": "trojan.test", "port": 443, "password": "secret"]
                ]
            ]
        )
        let shadowsocks = try migrate(
            protocolName: "shadowsocks",
            settings: [
                "servers": [
                    [
                        "address": "ss.test",
                        "port": 8_388,
                        "password": "secret",
                        "method": "aes-128-gcm",
                    ]
                ]
            ],
            streamSettings: [:]
        )

        XCTAssertEqual(vmess.protocolName, .vmess)
        XCTAssertEqual(trojan.protocolName, .trojan)
        XCTAssertEqual(shadowsocks.protocolName, .shadowsocks)
        XCTAssertEqual(shadowsocks.encryption, "aes-128-gcm")
    }

    func testAmbiguousAndLossyLegacyStructuresFailClosed() throws {
        let multiple: [String: Any] = [
            "outbounds": [
                ["tag": "proxy", "protocol": "vless", "settings": [:]],
                ["tag": "proxy", "protocol": "trojan", "settings": [:]],
            ]
        ]
        XCTAssertThrowsError(
            try LegacyXrayConfigurationMigrator.profile(
                from: JSONSerialization.data(withJSONObject: multiple)
            )
        ) { error in
            XCTAssertEqual(error as? LegacyXrayMigrationError, .multipleProxyOutbounds)
        }

        let realityWithSpiderX: [String: Any] = [
            "tag": "proxy",
            "protocol": "vless",
            "settings": [
                "vnext": [
                    [
                        "address": "origin.test",
                        "port": 443,
                        "users": [
                            ["id": "11111111-1111-1111-1111-111111111111"]
                        ],
                    ]
                ]
            ],
            "streamSettings": [
                "network": "tcp",
                "security": "reality",
                "realitySettings": [
                    "serverName": "origin.test",
                    "publicKey": "key",
                    "shortId": "abcd",
                    "spiderX": "/",
                ],
            ],
        ]
        XCTAssertThrowsError(
            try LegacyXrayConfigurationMigrator.profile(
                from: JSONSerialization.data(withJSONObject: realityWithSpiderX)
            )
        ) { error in
            XCTAssertEqual(error as? LegacyXrayMigrationError, .unsupportedRealitySpiderX)
        }
    }

    func testLegacyHTTPTransportsFailInsteadOfDroppingTransportSettings() throws {
        let settings: [String: Any] = [
            "vnext": [
                [
                    "address": "vmess.test",
                    "port": 443,
                    "users": [
                        [
                            "id": "22222222-2222-2222-2222-222222222222",
                            "alterId": 0,
                            "security": "auto",
                        ]
                    ],
                ]
            ]
        ]

        for transport in ["http", "h2"] {
            XCTAssertThrowsError(
                try migrate(
                    protocolName: "vmess",
                    settings: settings,
                    streamSettings: [
                        "network": transport,
                        "security": "none",
                        "httpSettings": [
                            "host": ["cdn.test"],
                            "path": "/transport",
                        ],
                    ]
                )
            ) { error in
                XCTAssertEqual(
                    error as? LegacyXrayMigrationError,
                    .unsupportedTransport(transport)
                )
            }
        }
    }

    private func migrate(
        protocolName: String,
        settings: [String: Any],
        streamSettings: [String: Any] = ["network": "tcp", "security": "none"]
    ) throws -> MihomoProxyProfile {
        let outbound: [String: Any] = [
            "tag": "proxy",
            "protocol": protocolName,
            "settings": settings,
            "streamSettings": streamSettings,
        ]
        return try LegacyXrayConfigurationMigrator.profile(
            from: JSONSerialization.data(withJSONObject: outbound)
        )
    }
}
