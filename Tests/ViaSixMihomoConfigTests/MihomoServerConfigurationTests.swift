import Foundation
import XCTest

@testable import ViaSixMihomoConfig

final class MihomoServerConfigurationTests: XCTestCase {
    func testCanonicalServerConfigurationUsesNativeYAMLAndDropsLocalKeys() throws {
        let input = data(
            """
            mixed-port: 9999
            allow-lan: true
            external-controller: 0.0.0.0:9090
            secret: unsafe
            tun:
              enable: true
            dns:
              enable: true
            proxies:
              - name: edge
                type: vless
                server: origin.example.com
                port: 443
                uuid: 11111111-1111-1111-1111-111111111111
                tls: true
                servername: origin.example.com
            proxy-groups:
              - name: PROXY
                type: select
                proxies: [edge]
            rules:
              - MATCH,PROXY
            """
        )

        let configuration = try MihomoServerConfiguration(data: input)
        let root = try MihomoYAML.mapping(from: configuration.data)

        XCTAssertNotNil(root["proxies"])
        XCTAssertNotNil(root["proxy-groups"])
        XCTAssertNotNil(root["rules"])
        XCTAssertNil(root["mixed-port"])
        XCTAssertNil(root["allow-lan"])
        XCTAssertNil(root["external-controller"])
        XCTAssertNil(root["secret"])
        XCTAssertNil(root["tun"])
        XCTAssertNil(root["dns"])
    }

    func testSingleProxyMappingIsAcceptedAndWrapped() throws {
        let configuration = try MihomoServerConfiguration(
            data: data(
                """
                name: single
                type: trojan
                server: server.test
                port: 443
                password: secret
                sni: server.test
                tls: true
                """
            )
        )

        let profile = try configuration.primaryProfile()
        XCTAssertEqual(profile.name, "single")
        XCTAssertEqual(profile.protocolName, .trojan)
        XCTAssertEqual(profile.credential, "secret")
        XCTAssertTrue(configuration.hasReplaceablePrimaryServer)
        XCTAssertFalse(configuration.isProviderOnly)
    }

    func testTrojanImplicitTLSAndSNIRoundTripWithoutSyntheticTLSKey() throws {
        let configuration = try MihomoServerConfiguration(
            data: data(
                """
                proxies:
                  - name: trojan
                    type: trojan
                    server: server.test
                    port: 443
                    password: secret
                    sni: cdn.test
                """
            )
        )

        let profile = try configuration.primaryProfile()
        XCTAssertEqual(profile.security, .tls)
        XCTAssertEqual(profile.serverName, "cdn.test")

        let roundTripped = try MihomoYAML.mapping(from: profile.serverConfiguration().data)
        let proxy = try XCTUnwrap(roundTripped.mappings("proxies")?.first)
        XCTAssertEqual(proxy.string("sni"), "cdn.test")
        XCTAssertNil(proxy["tls"])
    }

    func testMihomoServerlessProxiesDoNotRequireServerFields() throws {
        let configuration = try MihomoServerConfiguration(
            data: data(
                """
                proxies:
                  - name: local-direct
                    type: direct
                  - name: blocked
                    type: reject
                  - name: local-dns
                    type: dns
                """
            )
        )
        let root = try MihomoYAML.mapping(from: configuration.data)

        XCTAssertEqual(root.mappings("proxies")?.count, 3)
        XCTAssertNil(root.mappings("proxies")?.first?.string("server"))
        XCTAssertThrowsError(try configuration.primaryProfile()) { error in
            XCTAssertEqual(error as? MihomoConfigurationError, .missingInlineProxy)
        }
        XCTAssertFalse(configuration.hasReplaceablePrimaryServer)
        XCTAssertFalse(configuration.isProviderOnly)
    }

    func testSingleServerlessProxyMappingIsAcceptedAndWrapped() throws {
        let configuration = try MihomoServerConfiguration(
            data: data(
                """
                name: local-dns
                type: dns
                """
            )
        )
        let root = try MihomoYAML.mapping(from: configuration.data)

        XCTAssertEqual(root.mappings("proxies")?.first?.string("name"), "local-dns")
        XCTAssertEqual(root.mappings("proxies")?.first?.string("type"), "dns")
    }

    func testPrimaryAddressOperationsSkipServerlessBuiltInProxies() throws {
        let configuration = try MihomoServerConfiguration(
            data: data(
                """
                proxies:
                  - name: local-direct
                    type: direct
                  - name: edge
                    type: ss
                    server: origin.example.com
                    port: 8388
                    cipher: aes-128-gcm
                    password: secret
                """
            )
        )

        let updated = try configuration.replacingPrimaryServer(with: "1.1.1.1")
        let root = try MihomoYAML.mapping(from: updated.data)

        XCTAssertNil(root.mappings("proxies")?.first?.string("server"))
        XCTAssertEqual(root.mappings("proxies")?[1].string("server"), "1.1.1.1")
        XCTAssertEqual(try updated.primaryProfile().serverAddress, "1.1.1.1")
        XCTAssertEqual(MihomoServerConfiguration.proxyServerAddress(in: updated.data), "1.1.1.1")
    }

    func testReplacingPrimaryServerPreservesTLSIdentityAndWebSocketHost() throws {
        let profile = MihomoProxyProfile(
            name: "edge",
            protocolName: .vless,
            serverAddress: "origin.example.com",
            serverPort: 443,
            credential: "11111111-1111-1111-1111-111111111111",
            transport: .websocket,
            security: .tls,
            serverName: "origin.example.com",
            host: "cdn.example.com",
            path: "/ws"
        )

        let updated = try MihomoServerConfiguration(profile: profile)
            .replacingPrimaryServer(with: "2606:4700::1")
        let parsed = try updated.primaryProfile()

        XCTAssertEqual(parsed.serverAddress, "2606:4700::1")
        XCTAssertEqual(parsed.serverName, "origin.example.com")
        XCTAssertEqual(parsed.host, "cdn.example.com")
        XCTAssertEqual(parsed.path, "/ws")
    }

    func testProviderOnlyConfigurationIsAcceptedButCannotProduceGuidedProfile() throws {
        let configuration = try MihomoServerConfiguration(
            data: data(
                """
                proxy-providers:
                  remote:
                    type: http
                    url: https://subscription.test/profile.yaml
                    path: ./providers/remote.yaml
                    interval: 3600
                proxy-groups:
                  - name: PROXY
                    type: select
                    use: [remote]
                rules:
                  - MATCH,PROXY
                """
            )
        )

        XCTAssertThrowsError(try configuration.primaryProfile()) { error in
            XCTAssertEqual(error as? MihomoConfigurationError, .missingInlineProxy)
        }
        XCTAssertFalse(configuration.hasReplaceablePrimaryServer)
        XCTAssertTrue(configuration.isProviderOnly)
    }

    func testRejectsLegacyXrayJSONAndDuplicateProxyNames() throws {
        XCTAssertThrowsError(
            try MihomoServerConfiguration(data: data("{\"outbounds\": []}"))
        ) { error in
            XCTAssertEqual(error as? MihomoConfigurationError, .legacyXrayConfiguration)
        }

        XCTAssertThrowsError(
            try MihomoServerConfiguration(
                data: data(
                    """
                    proxies:
                      - {name: duplicate, type: ss, server: one.example, port: 443, cipher: aes-128-gcm, password: a}
                      - {name: duplicate, type: ss, server: two.example, port: 443, cipher: aes-128-gcm, password: b}
                    """
                )
            )
        )
    }

    func testProviderPathsAreRewrittenAndFileProvidersAreRejected() throws {
        let configuration = try MihomoServerConfiguration(
            data: data(
                """
                proxy-providers:
                  remote:
                    type: http
                    url: https://subscription.test/profile.yaml
                    path: ../../outside.yaml
                proxy-groups:
                  - name: PROXY
                    type: select
                    use: [remote]
                rules: ["MATCH,PROXY"]
                """
            )
        )
        let root = try MihomoYAML.mapping(from: configuration.data)
        let path = root.mapping("proxy-providers")?
            .mapping("remote")?
            .string("path")
        XCTAssertTrue(path?.hasPrefix("providers/") == true)
        XCTAssertFalse(path?.contains("..") == true)

        XCTAssertThrowsError(
            try MihomoServerConfiguration(
                data: data(
                    """
                    proxy-providers:
                      local:
                        type: file
                        path: /tmp/nodes.yaml
                    proxy-groups:
                      - {name: PROXY, type: select, use: [local]}
                    rules: ["MATCH,PROXY"]
                    """
                )
            )
        )
    }

    func testRejectsRulesContainingNonStringValues() throws {
        XCTAssertThrowsError(
            try MihomoServerConfiguration(
                data: data(
                    """
                    proxies:
                      - name: edge
                        type: trojan
                        server: server.test
                        port: 443
                        password: secret
                    rules:
                      - MATCH,edge
                      - 42
                    """
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? MihomoConfigurationError,
                .unsupportedValue("rules 必须是字符串列表")
            )
        }
    }

    private func data(_ source: String) -> Data {
        Data(source.utf8)
    }
}
