import Foundation

enum TestConfigFixtures {
    static let syntheticLegacyUserID = "11111111-2222-4333-8444-555555555555"
    static let syntheticLegacyServerName = "legacy.example.invalid"

    static func connectionTemplate(
        address: String = "2001:db8::1",
        userID: String,
        serverName: String,
        path: String,
        listen: String = "127.0.0.1",
        port: Int = 11_451
    ) throws -> Data {
        let object: [String: Any] = [
            "inbounds": [
                [
                    "tag": "mixed-in",
                    "listen": listen,
                    "port": port,
                    "protocol": "mixed",
                    "settings": ["auth": "noauth", "udp": true],
                ]
            ],
            "outbounds": [
                [
                    "tag": "proxy",
                    "protocol": "vless",
                    "settings": [
                        "vnext": [
                            [
                                "address": address,
                                "port": 443,
                                "users": [["id": userID, "encryption": "none"]],
                            ]
                        ]
                    ],
                    "streamSettings": [
                        "network": "ws",
                        "security": "tls",
                        "tlsSettings": ["serverName": serverName],
                        "wsSettings": ["host": serverName, "path": path],
                    ],
                ],
                ["tag": "direct", "protocol": "freedom"],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    static func syntheticLegacyTemplate() throws -> Data {
        try connectionTemplate(
            address: "2001:db8:ffff::1",
            userID: syntheticLegacyUserID,
            serverName: syntheticLegacyServerName,
            path: "/legacy-fixture"
        )
    }

    static func proxyOutbound(from template: Data) throws -> Data {
        guard
            let root = try JSONSerialization.jsonObject(with: template) as? [String: Any],
            let outbounds = root["outbounds"] as? [[String: Any]],
            let proxy = outbounds.first(where: { $0["tag"] as? String == "proxy" })
        else {
            throw TestConfigFixtureError.missingProxyOutbound
        }
        return try JSONSerialization.data(
            withJSONObject: proxy,
            options: [.prettyPrinted, .sortedKeys]
        )
    }
}

private enum TestConfigFixtureError: Error {
    case missingProxyOutbound
}
