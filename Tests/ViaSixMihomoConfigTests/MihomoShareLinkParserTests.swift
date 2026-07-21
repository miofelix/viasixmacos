import Foundation
import XCTest

@testable import ViaSixMihomoConfig

final class MihomoShareLinkParserTests: XCTestCase {
    func testVLESSRealityLinkMapsToMihomoFields() throws {
        let profile = try MihomoShareLinkParser.profile(
            from:
                "vless://11111111-1111-1111-1111-111111111111@edge.test:443?type=grpc&security=reality&sni=cdn.test&fp=chrome&pbk=public-key&sid=abcd&serviceName=edge#Hong%20Kong"
        )
        let root = try MihomoYAML.mapping(from: profile.serverConfiguration().data)
        let proxy = try XCTUnwrap(root.mappings("proxies")?.first)

        XCTAssertEqual(profile.name, "Hong Kong")
        XCTAssertEqual(proxy.string("type"), "vless")
        XCTAssertEqual(proxy.string("uuid"), "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(proxy.string("network"), "grpc")
        XCTAssertEqual(proxy.string("servername"), "cdn.test")
        XCTAssertEqual(proxy.mapping("reality-opts")?.string("public-key"), "public-key")
        XCTAssertEqual(proxy.mapping("reality-opts")?.string("short-id"), "abcd")
        XCTAssertEqual(proxy.mapping("grpc-opts")?.string("grpc-service-name"), "edge")
    }

    func testVMessTrojanAndShadowsocksLinksProduceNativeProfiles() throws {
        let vmessPayload: [String: Any] = [
            "v": "2",
            "ps": "vmess",
            "add": "vmess.example.com",
            "port": "443",
            "id": "22222222-2222-2222-2222-222222222222",
            "aid": "0",
            "net": "ws",
            "tls": "tls",
            "host": "cdn.example.com",
            "path": "/socket",
        ]
        let vmessData = try JSONSerialization.data(withJSONObject: vmessPayload)
        let vmessLink = "vmess://" + vmessData.base64EncodedString()

        let vmess = try MihomoShareLinkParser.profile(from: vmessLink)
        let trojan = try MihomoShareLinkParser.profile(
            from: "trojan://password@trojan.example.com:443?sni=trojan.example.com#trojan"
        )
        let ssCredentials = Data("aes-128-gcm:password".utf8).base64EncodedString()
        let shadowsocks = try MihomoShareLinkParser.profile(
            from: "ss://\(ssCredentials)@ss.example.com:8388#ss"
        )

        XCTAssertEqual(vmess.protocolName, .vmess)
        XCTAssertEqual(vmess.transport, .websocket)
        XCTAssertEqual(vmess.host, "cdn.example.com")
        XCTAssertEqual(trojan.protocolName, .trojan)
        XCTAssertEqual(trojan.credential, "password")
        XCTAssertEqual(shadowsocks.protocolName, .shadowsocks)
        XCTAssertEqual(shadowsocks.encryption, "aes-128-gcm")
    }

    func testUnsupportedAndMalformedLinksFailClosed() {
        XCTAssertThrowsError(try MihomoShareLinkParser.profile(from: "https://example.com"))
        XCTAssertThrowsError(try MihomoShareLinkParser.profile(from: "vless://missing"))
        XCTAssertThrowsError(try MihomoShareLinkParser.profile(from: "vmess://not-base64"))
        XCTAssertThrowsError(
            try MihomoShareLinkParser.profile(
                from:
                    "vless://11111111-1111-1111-1111-111111111111@edge.test:443?type=unknown&security=tls&sni=edge.test"
            )
        )
    }

    func testRepeatedQueryItemsUseLastValueWithoutCrashing() throws {
        let profile = try MihomoShareLinkParser.profile(
            from:
                "vless://11111111-1111-1111-1111-111111111111@edge.test:443?type=tcp&type=grpc&security=tls&sni=edge.test&serviceName=svc"
        )
        XCTAssertEqual(profile.transport, .grpc)
    }

    func testURLBasedIPv6HostsAreStoredWithoutBrackets() throws {
        let vless = try MihomoShareLinkParser.profile(
            from:
                "vless://11111111-1111-1111-1111-111111111111@[2606:4700::1]:443?type=tcp&security=none"
        )
        let trojan = try MihomoShareLinkParser.profile(
            from: "trojan://password@[2001:4860:4860::8888]:443?security=tls"
        )

        XCTAssertEqual(vless.serverAddress, "2606:4700::1")
        XCTAssertEqual(trojan.serverAddress, "2001:4860:4860::8888")

        let vlessRoot = try MihomoYAML.mapping(from: vless.serverConfiguration().data)
        let trojanRoot = try MihomoYAML.mapping(from: trojan.serverConfiguration().data)
        XCTAssertEqual(vlessRoot.mappings("proxies")?.first?.string("server"), "2606:4700::1")
        XCTAssertEqual(
            trojanRoot.mappings("proxies")?.first?.string("server"),
            "2001:4860:4860::8888"
        )
    }

    func testVLESSEncryptionRoundTripsThroughNativeConfiguration() throws {
        let encryption = "mlkem768x25519plus.native.0rtt.padding"
        let profile = try MihomoShareLinkParser.profile(
            from:
                "vless://11111111-1111-1111-1111-111111111111@edge.test:443?type=tcp&security=none&encryption=\(encryption)"
        )

        let configuration = try profile.serverConfiguration()
        let root = try MihomoYAML.mapping(from: configuration.data)
        XCTAssertEqual(profile.encryption, encryption)
        XCTAssertEqual(root.mappings("proxies")?.first?.string("encryption"), encryption)

        let reparsed = try configuration.primaryProfile()
        XCTAssertEqual(reparsed.encryption, encryption)
    }

    func testVMessGRPCPathMapsToMihomoServiceName() throws {
        let payload: [String: Any] = [
            "v": "2",
            "ps": "vmess-grpc",
            "add": "vmess.example.com",
            "port": "443",
            "id": "33333333-3333-3333-3333-333333333333",
            "aid": "0",
            "net": "grpc",
            "tls": "tls",
            "sni": "cdn.example.com",
            "path": "edge-service",
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let link = "vmess://" + data.base64EncodedString()

        let profile = try MihomoShareLinkParser.profile(from: link)
        let root = try MihomoYAML.mapping(from: profile.serverConfiguration().data)
        let proxy = try XCTUnwrap(root.mappings("proxies")?.first)

        XCTAssertEqual(profile.serviceName, "edge-service")
        XCTAssertEqual(
            proxy.mapping("grpc-opts")?.string("grpc-service-name"),
            "edge-service"
        )
    }
}
