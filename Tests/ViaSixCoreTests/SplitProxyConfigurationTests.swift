import Foundation
import XCTest

@testable import ViaSixCore

final class SplitProxyConfigurationTests: XCTestCase {
    func testLegacyLocalProxyConfigurationDefaultsToRuleMode() throws {
        let legacy = Data(
            #"{"listenAddress":"127.0.0.2","port":18080,"udpEnabled":false,"sniffingEnabled":false,"bypassPrivateNetworks":false,"logLevel":"info"}"#
                .utf8
        )

        let local = try JSONDecoder().decode(LocalProxyConfiguration.self, from: legacy)

        XCTAssertEqual(local.routingMode, .rule)
        XCTAssertEqual(local.networkAccessMode, .localProxy)
        XCTAssertEqual(local.endpoint, ProxyEndpoint(host: "127.0.0.2", port: 18_080))
        XCTAssertFalse(local.udpEnabled)
    }

    func testLegacyLocalProxyFieldsMigrateToNeutralValues() throws {
        let legacy = Data(
            #"{"logLevel":"none","systemProxyEnabled":true}"#.utf8
        )

        let local = try JSONDecoder().decode(LocalProxyConfiguration.self, from: legacy)

        XCTAssertEqual(local.logLevel, .silent)
        XCTAssertEqual(local.networkAccessMode, .systemProxy)
        let encoded = try JSONEncoder().encode(local)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertEqual(object["logLevel"] as? String, "silent")
        XCTAssertEqual(object["networkAccessMode"] as? String, "systemProxy")
        XCTAssertNil(object["systemProxyEnabled"])
    }

    func testLegacyTemplateSplitsServerAndLocalSettings() throws {
        let legacy = try TestConfigFixtures.connectionTemplate(
            address: "2001:db8::10",
            userID: "7b602ceb-cc3f-4274-a79d-c1a38f0fb0da",
            serverName: "edge.example.test",
            path: "/proxy",
            listen: "127.0.0.2",
            port: 18_081
        )

        let server = try ConfigTemplate.serverConfiguration(from: legacy)
        let local = try XCTUnwrap(try ConfigTemplate.localConfiguration(from: legacy))
        let serverObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: server) as? [String: Any])

        XCTAssertNil(serverObject["inbounds"])
        XCTAssertEqual(local.endpoint, ProxyEndpoint(host: "127.0.0.2", port: 18_081))
        XCTAssertTrue(local.udpEnabled)
    }

    func testRuntimeConfigurationCombinesSeparateSources() throws {
        let legacy = try TestConfigFixtures.connectionTemplate(
            userID: "7b602ceb-cc3f-4274-a79d-c1a38f0fb0da",
            serverName: "edge.example.test",
            path: "/proxy"
        )
        let server = try ConfigTemplate.serverConfiguration(from: legacy)
        let local = LocalProxyConfiguration(
            listenAddress: "127.0.0.9",
            port: 19_999,
            udpEnabled: false,
            sniffingEnabled: false,
            bypassPrivateNetworks: false,
            logLevel: .info
        )

        let runtime = try ConfigTemplate.runtimeConfiguration(
            server: server,
            local: local,
            address: "2606:4700::1111"
        )
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: runtime) as? [String: Any])
        let inbound = try XCTUnwrap((object["inbounds"] as? [[String: Any]])?.first)
        let outbounds = try XCTUnwrap(object["outbounds"] as? [[String: Any]])
        let proxy = try XCTUnwrap(outbounds.first { $0["tag"] as? String == "proxy" })
        let settings = try XCTUnwrap(proxy["settings"] as? [String: Any])
        let vnext = try XCTUnwrap(settings["vnext"] as? [[String: Any]])

        XCTAssertEqual(inbound["listen"] as? String, "127.0.0.9")
        XCTAssertEqual(inbound["port"] as? Int, 19_999)
        XCTAssertEqual((inbound["settings"] as? [String: Any])?["udp"] as? Bool, false)
        XCTAssertNil(inbound["sniffing"])
        XCTAssertEqual(vnext.first?["address"] as? String, "2606:4700::1111")
        XCTAssertNil(object["routing"])
    }

    func testRuleModeGeneratesPrivateNetworkBypassAndDefaultsOtherTrafficToProxy() throws {
        let server = try configuredServer()
        let local = LocalProxyConfiguration(
            bypassPrivateNetworks: true,
            routingMode: .rule
        )

        let runtime = try ConfigTemplate.runtimeConfiguration(
            server: server,
            local: local,
            address: "2606:4700::1111"
        )
        let object = try configurationObject(runtime)
        let rules = try routingRules(object)

        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules[0]["outboundTag"] as? String, "direct")
        XCTAssertEqual(rules[0]["ip"] as? [String], ["geoip:private"])
        XCTAssertEqual(try ConfigTemplate.localConfiguration(from: runtime)?.routingMode, .rule)
        XCTAssertNoThrow(try ConfigTemplate.validateForLaunch(runtime))
    }

    func testGlobalModeGeneratesCatchAllProxyRoute() throws {
        let server = try configuredServer()
        let local = LocalProxyConfiguration(
            bypassPrivateNetworks: true,
            routingMode: .global
        )

        let runtime = try ConfigTemplate.runtimeConfiguration(
            server: server,
            local: local,
            address: "2606:4700::1111"
        )
        let object = try configurationObject(runtime)
        let rules = try routingRules(object)

        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules[0]["outboundTag"] as? String, "proxy")
        XCTAssertEqual(rules[0]["network"] as? String, "tcp,udp")
        XCTAssertNil(rules[0]["ip"])
        XCTAssertEqual(try ConfigTemplate.localConfiguration(from: runtime)?.routingMode, .global)
        XCTAssertNoThrow(try ConfigTemplate.validateForLaunch(runtime))
    }

    func testDirectModeBuildsAndValidatesWithoutServerConfiguration() throws {
        let local = LocalProxyConfiguration(routingMode: .direct)

        let runtime = try ConfigTemplate.runtimeConfiguration(
            server: nil,
            local: local,
            address: ""
        )
        let object = try configurationObject(runtime)
        let outbounds = try XCTUnwrap(object["outbounds"] as? [[String: Any]])
        let rules = try routingRules(object)

        XCTAssertEqual(outbounds.compactMap { $0["tag"] as? String }, ["direct", "block"])
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules[0]["outboundTag"] as? String, "direct")
        XCTAssertEqual(rules[0]["network"] as? String, "tcp,udp")
        XCTAssertEqual(try ConfigTemplate.localConfiguration(from: runtime)?.routingMode, .direct)
        XCTAssertNoThrow(try ConfigTemplate.validateTemplate(runtime))
        XCTAssertNoThrow(try ConfigTemplate.validateForLaunch(runtime))
    }

    func testRuleAndGlobalModesRequireServerConfiguration() {
        for mode in [ProxyRoutingMode.rule, .global] {
            XCTAssertThrowsError(
                try ConfigTemplate.runtimeConfiguration(
                    server: nil,
                    local: LocalProxyConfiguration(routingMode: mode),
                    address: "2606:4700::1111"
                )
            ) { error in
                XCTAssertEqual(error as? ConfigTemplateError, .connectionNotConfigured)
            }
        }
    }

    func testDirectRoutingSkipsPlaceholderServerValidation() throws {
        let placeholder = try TestConfigFixtures.connectionTemplate(
            userID: ConfigTemplate.placeholderUserID,
            serverName: ConfigTemplate.placeholderServerName,
            path: "/"
        )
        let directTemplate = try ConfigTemplate.updatingLocalConfiguration(
            in: placeholder,
            with: LocalProxyConfiguration(routingMode: .direct)
        )

        XCTAssertNoThrow(try ConfigTemplate.validateForLaunch(directTemplate))

        let globalTemplate = try ConfigTemplate.updatingLocalConfiguration(
            in: directTemplate,
            with: LocalProxyConfiguration(routingMode: .global)
        )
        XCTAssertThrowsError(try ConfigTemplate.validateForLaunch(globalTemplate)) { error in
            XCTAssertEqual(error as? ConfigTemplateError, .connectionNotConfigured)
        }
    }

    func testGuidedServerProfileRoundTripsVlessWebSocketTLS() throws {
        let profile = try XrayServerProfile(
            serverPort: 443,
            userID: "7b602ceb-cc3f-4274-a79d-c1a38f0fb0da",
            transport: .websocket,
            security: .tls,
            serverName: "edge.example.test",
            host: "cdn.example.test",
            path: "/vless"
        ).validated()
        let data = try ConfigTemplate.serverConfiguration(for: profile)
        let decoded = try ConfigTemplate.serverProfile(in: data)

        XCTAssertEqual(decoded, profile)
    }

    func testVlessShareLinkFillsGuidedProfile() throws {
        let profile = try ServerShareLinkParser.profile(
            from:
                "vless://7b602ceb-cc3f-4274-a79d-c1a38f0fb0da@edge.example.test:443?type=ws&security=tls&sni=edge.example.test&host=cdn.example.test&path=%2Fvless&fp=chrome&allowInsecure=1#demo"
        )

        XCTAssertEqual(profile.protocolName, .vless)
        XCTAssertEqual(profile.serverAddress, "edge.example.test")
        XCTAssertEqual(profile.transport, .websocket)
        XCTAssertEqual(profile.security, .tls)
        XCTAssertTrue(profile.allowInsecure)
        XCTAssertEqual(profile.path, "/vless")
        XCTAssertEqual(profile.host, "cdn.example.test")
    }

    func testVmessAndTrojanShareLinksProduceSupportedOutbounds() throws {
        let vmessPayload =
            #"{"v":"2","add":"vmess.example.test","port":"443","id":"7b602ceb-cc3f-4274-a79d-c1a38f0fb0da","aid":"0","net":"ws","type":"none","host":"cdn.example.test","path":"/vmess","tls":"tls","sni":"vmess.example.test"}"#
        let vmessLink = "vmess://" + Data(vmessPayload.utf8).base64EncodedString()
        let vmess = try ServerShareLinkParser.profile(from: vmessLink)
        let trojan = try ServerShareLinkParser.profile(
            from: "trojan://secret@trojan.example.test:443?security=tls&sni=trojan.example.test&type=ws&path=%2F"
        )
        let shadowsocksPayload = Data("aes-256-gcm:secret".utf8).base64EncodedString()
        let shadowsocks = try ServerShareLinkParser.profile(
            from: "ss://\(shadowsocksPayload)@ss.example.test:8388/?plugin=v2ray-plugin%3Bmode%3Dwebsocket"
        )

        XCTAssertEqual(vmess.protocolName, .vmess)
        XCTAssertEqual(vmess.transport, .websocket)
        XCTAssertEqual(trojan.protocolName, .trojan)
        XCTAssertEqual(shadowsocks.protocolName, .shadowsocks)
        XCTAssertNoThrow(try ConfigTemplate.serverConfiguration(for: vmess))
        XCTAssertNoThrow(try ConfigTemplate.serverConfiguration(for: trojan))
        XCTAssertNoThrow(try ConfigTemplate.serverConfiguration(for: shadowsocks))
    }

    private func configuredServer() throws -> Data {
        let legacy = try TestConfigFixtures.connectionTemplate(
            userID: "7b602ceb-cc3f-4274-a79d-c1a38f0fb0da",
            serverName: "edge.example.test",
            path: "/proxy"
        )
        return try ConfigTemplate.serverConfiguration(from: legacy)
    }

    private func configurationObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func routingRules(_ object: [String: Any]) throws -> [[String: Any]] {
        let routing = try XCTUnwrap(object["routing"] as? [String: Any])
        return try XCTUnwrap(routing["rules"] as? [[String: Any]])
    }
}
