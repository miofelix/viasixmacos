import Foundation
import XCTest

@testable import ViaSixMihomoConfig

final class MihomoYAMLSafetyTests: XCTestCase {
    func testRejectsAnchorsAndAliasesBeforeNormalization() throws {
        let anchored =
            """
            proxies:
              - &edge
                name: edge
                type: trojan
                server: server.test
                port: 443
                password: secret
            proxy-groups:
              - name: PROXY
                type: select
                proxies: [*edge]
            """

        XCTAssertThrowsError(try MihomoYAML.mapping(from: Data(anchored.utf8))) { error in
            XCTAssertEqual(
                error as? MihomoConfigurationError,
                .unsupportedValue("YAML anchor 或 alias")
            )
        }
    }

    func testRejectsAnchoredScalarWithoutAlias() throws {
        let anchored = "name: &proxy-name edge\n"

        XCTAssertThrowsError(try MihomoYAML.mapping(from: Data(anchored.utf8))) { error in
            XCTAssertEqual(
                error as? MihomoConfigurationError,
                .unsupportedValue("YAML anchor 或 alias")
            )
        }
    }

    func testRejectsSerializedYAMLOverMaximumSize() throws {
        let oversized = String(repeating: "a", count: 8 * 1_024 * 1_024)

        XCTAssertThrowsError(try MihomoYAML.data(from: ["value": oversized])) { error in
            guard case .configurationTooLarge(let size) = error as? MihomoConfigurationError else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertGreaterThan(size, 8 * 1_024 * 1_024)
        }
    }

    func testDepthLimitTraversesComposedNodeTree() throws {
        var yaml = "value: leaf\n"
        for level in 0...64 {
            yaml =
                "level-\(level):\n"
                + yaml
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { "  \($0)" }
                .joined(separator: "\n")
        }

        XCTAssertThrowsError(try MihomoYAML.mapping(from: Data(yaml.utf8))) { error in
            XCTAssertEqual(error as? MihomoConfigurationError, .configurationTooDeep)
        }
    }
}
