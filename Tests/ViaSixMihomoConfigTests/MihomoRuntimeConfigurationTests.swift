import Foundation
import XCTest

@testable import ViaSixMihomoConfig

final class MihomoRuntimeConfigurationTests: XCTestCase {
    func testRuleModeBuildsManagedGroupAndPrivateBypassRules() throws {
        let server = try sampleServer()
        let output = try server.runtimeConfiguration(
            options: MihomoRuntimeOptions(
                listenAddress: "127.0.0.1",
                mixedPort: 20_280,
                routingMode: .rule,
                logLevel: .info,
                ipv6Enabled: true,
                udpEnabled: true,
                sniffingEnabled: true,
                bypassPrivateNetworks: true
            ),
            replacingPrimaryServerWith: "1.1.1.1"
        )
        let root = try MihomoYAML.mapping(from: output)

        XCTAssertEqual(root.int("mixed-port"), 20_280)
        XCTAssertEqual(root.string("bind-address"), "127.0.0.1")
        XCTAssertEqual(root.string("mode"), "rule")
        XCTAssertEqual(root.string("log-level"), "info")
        XCTAssertEqual(root.bool("allow-lan"), false)
        XCTAssertEqual(root.mappings("proxies")?.first?.string("server"), "1.1.1.1")
        XCTAssertEqual(root.mappings("proxies")?.first?.bool("udp"), true)
        XCTAssertEqual(root.mappings("proxy-groups")?.first?.string("name"), "ViaSix")
        let rules = try XCTUnwrap(root["rules"] as? [String])
        XCTAssertTrue(rules.contains("IP-CIDR,192.168.0.0/16,DIRECT,no-resolve"))
        XCTAssertEqual(rules.last, "MATCH,ViaSix")
        XCTAssertEqual(root.mapping("tun")?.bool("enable"), false)
        XCTAssertEqual(root.mapping("sniffer")?.bool("enable"), true)
    }

    func testGlobalAndDirectModesUseMihomoNativeModeValues() throws {
        let server = try sampleServer()
        let global = try MihomoYAML.mapping(
            from: server.runtimeConfiguration(
                options: MihomoRuntimeOptions(routingMode: .global)
            )
        )
        XCTAssertEqual(global.string("mode"), "global")

        let direct = try MihomoYAML.mapping(
            from: MihomoServerConfiguration.runtimeConfiguration(
                server: server,
                options: MihomoRuntimeOptions(routingMode: .direct)
            )
        )
        XCTAssertEqual(direct.string("mode"), "direct")
        XCTAssertEqual(direct["rules"] as? [String], ["MATCH,DIRECT"])
        XCTAssertNil(direct["proxies"])
        XCTAssertNil(direct["proxy-providers"])
        XCTAssertNil(direct["proxy-groups"])
    }

    func testTunModeUsesMihomoAutoRouteAndFakeIPDNS() throws {
        let server = try sampleServer()
        let output = try server.runtimeConfiguration(
            options: MihomoRuntimeOptions(
                routingMode: .rule,
                tun: MihomoTunConfiguration(
                    stack: .mixed,
                    device: "utun1024",
                    autoRoute: true,
                    strictRoute: true,
                    autoDetectInterface: true,
                    dnsHijack: ["any:53", "tcp://any:53"],
                    mtu: 1_500,
                    routeExcludeAddresses: ["1.1.1.1/32"]
                )
            )
        )
        let root = try MihomoYAML.mapping(from: output)
        let tun = try XCTUnwrap(root.mapping("tun"))
        let dns = try XCTUnwrap(root.mapping("dns"))

        XCTAssertEqual(tun.bool("enable"), true)
        XCTAssertEqual(tun.string("stack"), "mixed")
        XCTAssertEqual(tun.string("device"), "utun1024")
        XCTAssertEqual(tun.bool("auto-route"), true)
        XCTAssertEqual(tun.bool("strict-route"), true)
        XCTAssertEqual(tun.bool("auto-detect-interface"), true)
        XCTAssertEqual(tun["dns-hijack"] as? [String], ["any:53", "tcp://any:53"])
        XCTAssertEqual(tun["route-exclude-address"] as? [String], ["1.1.1.1/32"])
        XCTAssertEqual(dns.bool("enable"), true)
        XCTAssertEqual(dns.string("enhanced-mode"), "fake-ip")
        XCTAssertEqual(dns.string("fake-ip-range"), "198.18.0.1/16")
    }

    func testRuntimeRejectsUnsafeLocalValues() throws {
        let server = try sampleServer()
        XCTAssertThrowsError(
            try server.runtimeConfiguration(
                options: MihomoRuntimeOptions(listenAddress: "0.0.0.0")
            )
        ) { error in
            XCTAssertEqual(error as? MihomoConfigurationError, .invalidListenAddress)
        }

        XCTAssertThrowsError(
            try server.runtimeConfiguration(
                options: MihomoRuntimeOptions(
                    tun: MihomoTunConfiguration(device: "en0")
                )
            )
        )

        let udpDisabled = try MihomoYAML.mapping(
            from: server.runtimeConfiguration(
                options: MihomoRuntimeOptions(udpEnabled: false)
            )
        )
        XCTAssertEqual(udpDisabled.mappings("proxies")?.first?.bool("udp"), false)
    }

    private func sampleServer() throws -> MihomoServerConfiguration {
        try MihomoServerConfiguration(
            profile: MihomoProxyProfile(
                name: "edge",
                protocolName: .vless,
                serverAddress: "origin.example.com",
                serverPort: 443,
                credential: "11111111-1111-1111-1111-111111111111",
                transport: .websocket,
                security: .tls,
                serverName: "origin.example.com",
                host: "origin.example.com"
            )
        )
    }
}
