import Foundation

enum TestConfigFixtures {
    static func connectionTemplate(
        address: String = "2001:db8::1",
        userID: String,
        serverName: String,
        path: String
    ) throws -> Data {
        let object: [String: Any] = [
            "inbounds": [
                [
                    "tag": "mixed-in",
                    "listen": "127.0.0.1",
                    "port": 11_451,
                    "protocol": "mixed",
                    "settings": ["auth": "noauth", "udp": true]
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
                                "users": [["id": userID, "encryption": "none"]]
                            ]
                        ]
                    ],
                    "streamSettings": [
                        "network": "ws",
                        "security": "tls",
                        "tlsSettings": ["serverName": serverName],
                        "wsSettings": ["host": serverName, "path": path]
                    ]
                ],
                ["tag": "direct", "protocol": "freedom"]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    static let legacyBundledTemplate = Data(
        base64Encoded: """
        ewogICJsb2ciOiB7CiAgICAibG9nbGV2ZWwiOiAid2FybmluZyIKICB9LAogICJpbmJvdW5kcyI6IFsKICAgIHsKICAgICAgInRh
        ZyI6ICJtaXhlZC1pbiIsCiAgICAgICJsaXN0ZW4iOiAiMTI3LjAuMC4xIiwKICAgICAgInBvcnQiOiAxMTQ1MSwKICAgICAgInBy
        b3RvY29sIjogIm1peGVkIiwKICAgICAgInNldHRpbmdzIjogewogICAgICAgICJhdXRoIjogIm5vYXV0aCIsCiAgICAgICAgInVk
        cCI6IHRydWUKICAgICAgfSwKICAgICAgInNuaWZmaW5nIjogewogICAgICAgICJlbmFibGVkIjogdHJ1ZSwKICAgICAgICAiZGVz
        dE92ZXJyaWRlIjogWwogICAgICAgICAgImh0dHAiLAogICAgICAgICAgInRscyIsCiAgICAgICAgICAicXVpYyIKICAgICAgICBd
        CiAgICAgIH0KICAgIH0KICBdLAogICJvdXRib3VuZHMiOiBbCiAgICB7CiAgICAgICJ0YWciOiAicHJveHkiLAogICAgICAicHJv
        dG9jb2wiOiAidmxlc3MiLAogICAgICAic2V0dGluZ3MiOiB7CiAgICAgICAgInZuZXh0IjogWwogICAgICAgICAgewogICAgICAg
        ICAgICAiYWRkcmVzcyI6ICIyNDAwOmNiMDA6MjA0OToyYTNiOmQ4ZWU6ZjgyNzo5MmJmOjQ2MSIsCiAgICAgICAgICAgICJwb3J0
        IjogODAsCiAgICAgICAgICAgICJ1c2VycyI6IFsKICAgICAgICAgICAgICB7CiAgICAgICAgICAgICAgICAiaWQiOiAiNjc0NDBj
        NjUtYzY3NC00ZDAyLWEwMzUtMDRmOGVmMjg5MmYxIiwKICAgICAgICAgICAgICAgICJlbmNyeXB0aW9uIjogIm5vbmUiCiAgICAg
        ICAgICAgICAgfQogICAgICAgICAgICBdCiAgICAgICAgICB9CiAgICAgICAgXQogICAgICB9LAogICAgICAic3RyZWFtU2V0dGlu
        Z3MiOiB7CiAgICAgICAgIm5ldHdvcmsiOiAid3MiLAogICAgICAgICJzZWN1cml0eSI6ICJub25lIiwKICAgICAgICAid3NTZXR0
        aW5ncyI6IHsKICAgICAgICAgICJob3N0IjogImZyYWdyYW50LWJ1dHRlcmZseS00NjYwLnhpYW9kYW5mai53b3JrZXJzLmRldiIs
        CiAgICAgICAgICAicGF0aCI6ICIvIiwKICAgICAgICAgICJoZWFkZXJzIjoge30KICAgICAgICB9CiAgICAgIH0KICAgIH0sCiAg
        ICB7CiAgICAgICJ0YWciOiAiZGlyZWN0IiwKICAgICAgInByb3RvY29sIjogImZyZWVkb20iCiAgICB9LAogICAgewogICAgICAi
        dGFnIjogImJsb2NrIiwKICAgICAgInByb3RvY29sIjogImJsYWNraG9sZSIKICAgIH0KICBdLAogICJyb3V0aW5nIjogewogICAg
        ImRvbWFpblN0cmF0ZWd5IjogIkFzSXMiLAogICAgInJ1bGVzIjogWwogICAgICB7CiAgICAgICAgInR5cGUiOiAiZmllbGQiLAog
        ICAgICAgICJpcCI6IFsKICAgICAgICAgICJnZW9pcDpwcml2YXRlIgogICAgICAgIF0sCiAgICAgICAgIm91dGJvdW5kVGFnIjog
        ImRpcmVjdCIKICAgICAgfQogICAgXQogIH0KfQoK
        """,
        options: .ignoreUnknownCharacters
    )!

    static func legacyConnectionValues() throws -> (userID: String, serverName: String) {
        let object = try JSONSerialization.jsonObject(with: legacyBundledTemplate) as? [String: Any]
        let outbounds = object?["outbounds"] as? [[String: Any]]
        let proxy = outbounds?.first { $0["tag"] as? String == "proxy" }
        let settings = proxy?["settings"] as? [String: Any]
        let vnext = settings?["vnext"] as? [[String: Any]]
        let users = vnext?.first?["users"] as? [[String: Any]]
        let streamSettings = proxy?["streamSettings"] as? [String: Any]
        let wsSettings = streamSettings?["wsSettings"] as? [String: Any]

        guard let userID = users?.first?["id"] as? String,
              let serverName = wsSettings?["host"] as? String else {
            throw FixtureError.invalidLegacyTemplate
        }
        return (userID, serverName)
    }

    enum FixtureError: Error {
        case invalidLegacyTemplate
    }
}
