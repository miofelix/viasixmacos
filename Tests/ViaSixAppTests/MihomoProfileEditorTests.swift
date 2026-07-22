import Foundation
import ViaSixMihomoConfig
import XCTest

@testable import ViaSixApp

final class MihomoProfileEditorTests: XCTestCase {
    func testGuidedEditorAcceptsLosslessSingleProfile() throws {
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
        let data = try profile.serverConfiguration().formattedData()

        XCTAssertEqual(
            try MihomoGuidedProfileDraft.editable(from: data, selectedServer: "").profile,
            profile
        )
    }

    func testGuidedEditorRejectsConfigurationThatWouldLoseAdditionalFields() throws {
        let data = Data(
            """
            \(inlineProfile())
            proxy-groups:
              - name: PROXY
                type: select
                proxies: [edge]
            rules:
              - MATCH,PROXY
            """.utf8
        )

        XCTAssertThrowsError(
            try MihomoGuidedProfileDraft.editable(from: data, selectedServer: "")
        ) { error in
            XCTAssertEqual(error as? MihomoGuidedProfileDraftError, .requiresAdvancedEditor)
        }
    }

    func testGuidedEditorEditsSelectedIPTemplateWithoutPersistingServer() throws {
        let data = Data(
            """
            x-viasix:
              version: 1
              primary-server: selected-ip
              routing-mode: rule
              udp-enabled: false
              log-level: info
            proxies:
              - name: edge
                type: vless
                port: 443
                uuid: 11111111-1111-4111-8111-111111111111
                encryption: none
                tls: true
                servername: edge.example.com
                client-fingerprint: chrome
                skip-cert-verify: false
                network: ws
                ws-opts:
                  path: /ws
                  headers:
                    Host: edge.example.com
            """.utf8
        )

        let draft = try MihomoGuidedProfileDraft.editable(
            from: data,
            selectedServer: "2606:4700::1"
        )
        XCTAssertTrue(draft.usesSelectedPrimaryServer)
        XCTAssertEqual(draft.profile.serverAddress, "2606:4700::1")
        XCTAssertFalse(draft.profile.udpEnabled)

        var changed = draft.profile
        changed.name = "edited edge"
        let saved = try MihomoServerConfiguration(data: draft.data(replacing: changed))

        XCTAssertTrue(saved.requiresSelectedPrimaryServer)
        XCTAssertEqual(saved.summary.primaryProxyName, "edited edge")
        XCTAssertNil(MihomoServerConfiguration.proxyServerAddress(in: saved.data))
        XCTAssertEqual(saved.viaSixOptions?.udpEnabled, false)
    }

    func testGuidedEditorCanOpenSelectedIPTemplateBeforeSelectingNode() throws {
        let data = Data(
            """
            x-viasix:
              version: 1
              primary-server: selected-ip
              udp-enabled: false
            proxies:
              - name: edge
                type: vless
                port: 443
                uuid: 11111111-1111-4111-8111-111111111111
                encryption: none
                udp: false
                tls: true
                servername: edge.example.com
                client-fingerprint: chrome
                skip-cert-verify: false
                network: ws
                ws-opts:
                  path: /ws
                  headers:
                    Host: edge.example.com
            """.utf8
        )

        let draft = try MihomoGuidedProfileDraft.editable(from: data, selectedServer: "")

        XCTAssertTrue(draft.usesSelectedPrimaryServer)
        XCTAssertEqual(draft.profile.serverAddress, "当前未选择优选节点")
    }

    func testDraftAnalysisRecognizesInlineProxyConfiguration() {
        let analysis = MihomoProfileDraftAnalysis.inspect(inlineProfile())

        XCTAssertEqual(analysis.status, .inlineProxy("origin.example.com"))
        XCTAssertEqual(analysis.inlineServer, "origin.example.com")
        XCTAssertTrue(analysis.isValid)
        XCTAssertTrue(analysis.canFormat)
        XCTAssertFalse(analysis.canMigrate)
        XCTAssertNil(analysis.issue)
    }

    func testDraftAnalysisRecognizesViaSixSelectedIPTemplateAsInlineProxy() {
        let analysis = MihomoProfileDraftAnalysis.inspect(
            """
            x-viasix:
              version: 1
              primary-server: selected-ip
              routing-mode: rule
              udp-enabled: false
              log-level: info
            proxies:
              - name: edge
                type: vless
                port: 443
                uuid: 11111111-1111-4111-8111-111111111111
                tls: true
                servername: origin.example.com
            """
        )

        XCTAssertEqual(analysis.status, .inlineProxy("当前优选节点（运行时注入）"))
        XCTAssertTrue(analysis.isValid)
        XCTAssertTrue(analysis.canFormat)
        XCTAssertNil(analysis.issue)
    }

    func testDraftAnalysisRecognizesProviderOnlyConfiguration() {
        let analysis = MihomoProfileDraftAnalysis.inspect(
            """
            proxy-providers:
              remote:
                type: http
                url: https://subscription.example.com/profile.yaml
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

        XCTAssertEqual(analysis.status, .providerOnly)
        XCTAssertTrue(analysis.isValid)
        XCTAssertTrue(analysis.canFormat)
        XCTAssertNil(analysis.inlineServer)
    }

    func testDraftAnalysisDistinguishesInvalidYAMLAndInvalidConfiguration() {
        let invalidYAML = MihomoProfileDraftAnalysis.inspect("proxies:\n  - [")
        guard case .invalidYAML = invalidYAML.status else {
            return XCTFail("Expected invalid YAML, got \(invalidYAML.status)")
        }
        XCTAssertFalse(invalidYAML.isValid)
        XCTAssertFalse(invalidYAML.canFormat)

        let invalidConfiguration = MihomoProfileDraftAnalysis.inspect("proxies: []")
        XCTAssertEqual(
            invalidConfiguration.status,
            .invalidConfiguration(MihomoConfigurationError.missingProxySource.localizedDescription)
        )
        XCTAssertFalse(invalidConfiguration.isValid)
    }

    func testDraftAnalysisRecognizesMigratableLegacyXrayJSON() throws {
        let legacy = try legacyXrayJSON()
        let analysis = MihomoProfileDraftAnalysis.inspect(legacy)

        XCTAssertEqual(analysis.status, .legacyXrayMigratable("origin.example.com"))
        XCTAssertFalse(analysis.isValid)
        XCTAssertTrue(analysis.canMigrate)
        XCTAssertEqual(analysis.inlineServer, "origin.example.com")

        let migrated = try MihomoProfileDraftAnalysis.migratedYAML(legacy)
        XCTAssertEqual(
            MihomoProfileDraftAnalysis.inspect(migrated).status,
            .inlineProxy("origin.example.com")
        )
        XCTAssertFalse(migrated.contains("outbounds"))
    }

    func testDraftAnalysisReportsLegacyMigrationFailure() throws {
        let legacy = try legacyXrayJSON(realitySpiderX: "/")
        let analysis = MihomoProfileDraftAnalysis.inspect(legacy)

        guard case .legacyXrayMigrationFailed(let message) = analysis.status else {
            return XCTFail("Expected migration failure, got \(analysis.status)")
        }
        XCTAssertTrue(message.contains("spiderX"))
        XCTAssertFalse(analysis.isValid)
        XCTAssertFalse(analysis.canMigrate)
    }

    func testFormattingProducesCanonicalServerOnlyYAML() throws {
        let formatted = try MihomoProfileDraftAnalysis.formattedYAML(
            """
            mixed-port: 9090
            allow-lan: true
            \(inlineProfile())
            """
        )

        XCTAssertFalse(formatted.contains("mixed-port"))
        XCTAssertFalse(formatted.contains("allow-lan"))
        XCTAssertTrue(formatted.contains("proxies:"))
        XCTAssertEqual(
            MihomoProfileDraftAnalysis.inspect(formatted).status,
            .inlineProxy("origin.example.com")
        )
    }

    private func inlineProfile() -> String {
        """
        proxies:
          - name: edge
            type: vless
            server: origin.example.com
            port: 443
            uuid: 11111111-1111-1111-1111-111111111111
            network: ws
            tls: true
            servername: origin.example.com
            ws-opts:
              path: /ws
              headers:
                Host: cdn.example.com
        """
    }

    private func legacyXrayJSON(realitySpiderX: String? = nil) throws -> String {
        var reality: [String: Any] = [
            "serverName": "origin.example.com",
            "publicKey": "public-key",
            "shortId": "abcd",
            "fingerprint": "chrome",
        ]
        if let realitySpiderX {
            reality["spiderX"] = realitySpiderX
        }
        let root: [String: Any] = [
            "outbounds": [
                [
                    "tag": "proxy",
                    "protocol": "vless",
                    "settings": [
                        "vnext": [
                            [
                                "address": "origin.example.com",
                                "port": 443,
                                "users": [
                                    [
                                        "id": "11111111-1111-1111-1111-111111111111",
                                        "encryption": "none",
                                    ]
                                ],
                            ]
                        ]
                    ],
                    "streamSettings": [
                        "network": "tcp",
                        "security": "reality",
                        "realitySettings": reality,
                    ],
                ]
            ]
        ]
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        return String(decoding: data, as: UTF8.self)
    }
}
