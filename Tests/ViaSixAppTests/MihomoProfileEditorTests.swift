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

        XCTAssertEqual(try MihomoGuidedProfileDraft.editableProfile(from: data), profile)
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

        XCTAssertThrowsError(try MihomoGuidedProfileDraft.editableProfile(from: data)) { error in
            XCTAssertEqual(error as? MihomoGuidedProfileDraftError, .requiresAdvancedEditor)
        }
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
