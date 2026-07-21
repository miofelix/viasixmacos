import Foundation
import XCTest

@testable import ViaSixTunHelperSupport

final class PrivilegedRuntimeManifestTests: XCTestCase {
    private let sha256 = String(repeating: "a", count: 64)
    private let cdHash = String(repeating: "b", count: 40)

    func testDecodesAndValidatesSealedManifest() throws {
        let manifest = PrivilegedRuntimeManifest(
            architecture: "arm64",
            sha256: sha256,
            cdHash: cdHash
        )

        let decoded = try PrivilegedRuntimeManifest(
            data: try PropertyListEncoder().encode(manifest),
            expectedArchitecture: "arm64"
        )

        XCTAssertEqual(decoded, manifest)
    }

    func testRejectsUnexpectedIdentityAndPath() throws {
        for manifest in [
            PrivilegedRuntimeManifest(
                architecture: "arm64",
                relativePath: "../../tmp/mihomo",
                sha256: sha256,
                cdHash: cdHash
            ),
            PrivilegedRuntimeManifest(
                architecture: "arm64",
                bundleIdentifier: "com.example.mihomo",
                sha256: sha256,
                cdHash: cdHash
            ),
        ] {
            XCTAssertThrowsError(
                try PrivilegedRuntimeManifest(
                    data: PropertyListEncoder().encode(manifest),
                    expectedArchitecture: "arm64"
                )
            )
        }
    }

    func testRejectsArchitectureVersionAndDigestMismatch() throws {
        let invalidManifests = [
            PrivilegedRuntimeManifest(
                runtimeVersion: "1.19.28",
                architecture: "arm64",
                sha256: sha256,
                cdHash: cdHash
            ),
            PrivilegedRuntimeManifest(
                architecture: "x86_64",
                sha256: sha256,
                cdHash: cdHash
            ),
            PrivilegedRuntimeManifest(
                architecture: "arm64",
                sha256: String(repeating: "A", count: 64),
                cdHash: cdHash
            ),
            PrivilegedRuntimeManifest(
                architecture: "arm64",
                sha256: sha256,
                cdHash: String(repeating: "b", count: 39)
            ),
        ]

        for manifest in invalidManifests {
            XCTAssertThrowsError(
                try PrivilegedRuntimeManifest(
                    data: PropertyListEncoder().encode(manifest),
                    expectedArchitecture: "arm64"
                )
            )
        }
    }

    func testRejectsOversizedManifestBeforeParsing() {
        let data = Data(repeating: 0x20, count: 64 * 1_024 + 1)

        XCTAssertThrowsError(
            try PrivilegedRuntimeManifest(data: data, expectedArchitecture: "arm64")
        ) { error in
            XCTAssertEqual(
                error as? PrivilegedRuntimeManifestError,
                .manifestTooLarge(64 * 1_024 + 1)
            )
        }
    }
}
