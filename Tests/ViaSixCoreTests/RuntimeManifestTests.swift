import Foundation
import XCTest

@testable import ViaSixCore

final class RuntimeManifestTests: XCTestCase {
    func testPinnedVersionsAndAssetsForEveryArchitecture() throws {
        XCTAssertEqual(RuntimeManifest.cfstVersion, "2.3.5")
        XCTAssertEqual(RuntimeManifest.mihomoVersion, "1.19.29")
        XCTAssertEqual(RuntimeManifest.current.assets.count, 4)
        XCTAssertEqual(Set(RuntimeArchitecture.allCases), [.arm64, .x8664])

        let cases:
            [(
                component: RuntimeComponent,
                architecture: RuntimeArchitecture,
                archiveName: String,
                archiveFormat: RuntimeArchiveFormat,
                url: String,
                sha256: String,
                payloadExpectations: [RuntimePayloadExpectation]
            )] = [
                (
                    .cfst,
                    .arm64,
                    "cfst_darwin_arm64.zip",
                    .zip,
                    "https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.3.5/cfst_darwin_arm64.zip",
                    "0623f6d24c939e3d3716f556f4d39c7b8781cf6600ee838a1b64e6b2fe4609dc",
                    [
                        RuntimePayloadExpectation(
                            file: .cfst,
                            byteCount: 7_739_890,
                            sha256: "c98628414b8812a78c36de0b7fd50066a9fda57347658c212f32f9796dea064a"
                        )
                    ]
                ),
                (
                    .cfst,
                    .x8664,
                    "cfst_darwin_amd64.zip",
                    .zip,
                    "https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.3.5/cfst_darwin_amd64.zip",
                    "66ce3ae89430e851cab9710d54b6d91324e0aae255f0c92a91072d57724561d5",
                    [
                        RuntimePayloadExpectation(
                            file: .cfst,
                            byteCount: 8_151_056,
                            sha256: "899f2db79f3a68d60d35dbaf7f0c34ccbbe3c3ef06d9c8db1a411f99df91c9bf"
                        )
                    ]
                ),
                (
                    .mihomo,
                    .arm64,
                    "mihomo-darwin-arm64-v1.19.29.gz",
                    .gzip(output: .mihomo),
                    "https://github.com/MetaCubeX/mihomo/releases/download/v1.19.29/mihomo-darwin-arm64-v1.19.29.gz",
                    "4dc25df9e899f14161911302a8ee5fc9e202ed9c976fc405bf82c50ff27466ca",
                    [
                        RuntimePayloadExpectation(
                            file: .mihomo,
                            byteCount: 43_229_330,
                            sha256: "ec66e3e883bdc3fca06753784e324e08921e13239f8e945587cb1bfbf4c6b936"
                        )
                    ]
                ),
                (
                    .mihomo,
                    .x8664,
                    "mihomo-darwin-amd64-v1-v1.19.29.gz",
                    .gzip(output: .mihomo),
                    "https://github.com/MetaCubeX/mihomo/releases/download/v1.19.29/mihomo-darwin-amd64-v1-v1.19.29.gz",
                    "addf68bf604e05cce5334e949bb8915dd68b25744669b320f7d4c1e240ab92a0",
                    [
                        RuntimePayloadExpectation(
                            file: .mihomo,
                            byteCount: 47_015_456,
                            sha256: "a139a209965e34ef30fac77ea9bfa9e6ab63c01cad6f94804131fd7f4a552c02"
                        )
                    ]
                ),
            ]

        for expected in cases {
            let asset = try XCTUnwrap(
                RuntimeManifest.current.asset(
                    for: expected.component,
                    architecture: expected.architecture
                )
            )
            XCTAssertEqual(asset.archiveName, expected.archiveName)
            XCTAssertEqual(asset.archiveFormat, expected.archiveFormat)
            XCTAssertEqual(asset.downloadURL.absoluteString, expected.url)
            XCTAssertEqual(asset.sha256, expected.sha256)
            XCTAssertEqual(asset.payloadExpectations, expected.payloadExpectations)
            XCTAssertEqual(asset.sha256.count, 64)
            XCTAssertTrue(asset.sha256.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        }
    }

    func testAssetsForArchitectureAreCompleteAndOrdered() {
        for architecture in RuntimeArchitecture.allCases {
            let assets = RuntimeManifest.current.assets(for: architecture)
            XCTAssertEqual(assets.map(\.component), [.cfst, .mihomo])
            XCTAssertTrue(assets.allSatisfy { $0.architecture == architecture })
        }
    }

    func testRuntimeManagerDefaultsToPinnedManifest() async {
        let manager = RuntimeComponentManager(runtimeDirectory: URL(fileURLWithPath: "/tmp/Runtime"))
        let manifest = await manager.manifest

        XCTAssertEqual(manifest, RuntimeManifest.current)
    }

    func testSHA256ForDataAndFile() throws {
        let expected = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        let data = Data("abc".utf8)
        XCTAssertEqual(RuntimeSHA256.hexDigest(of: data), expected)

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViaSix-SHA256-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try data.write(to: fileURL)
        XCTAssertEqual(try RuntimeSHA256.hexDigest(ofFileAt: fileURL), expected)
    }

    func testRuntimeModelsAreSendable() {
        assertSendable(RuntimeArchitecture.arm64)
        assertSendable(RuntimeComponent.cfst)
        assertSendable(RuntimePayloadFile.mihomo)
        assertSendable(RuntimePayloadExpectation(file: .cfst))
        assertSendable(RuntimeArchiveFormat.gzip(output: .cfst))
        assertSendable(RuntimeManifest.current)
        assertSendable(RuntimeManifest.current.assets[0])
        assertSendable(RuntimeDiscoveredFiles())
        assertSendable(
            RuntimeInstallationStatus(
                runtimeDirectory: URL(fileURLWithPath: "/tmp/Runtime"),
                discoveredFiles: RuntimeDiscoveredFiles(),
                executableFiles: []
            )
        )
        assertSendable(RuntimeComponentError.sourceNotFound(URL(fileURLWithPath: "/tmp/missing")))
    }

    func testArchiveFormatsRoundTripThroughCodable() throws {
        for format in [RuntimeArchiveFormat.zip, .gzip(output: .mihomo)] {
            let encoded = try JSONEncoder().encode(format)
            XCTAssertEqual(try JSONDecoder().decode(RuntimeArchiveFormat.self, from: encoded), format)
        }
    }

    func testManagedMihomoRequiresAnExecutableBeforeItIsReady() {
        let runtimeDirectory = URL(fileURLWithPath: "/tmp/runtime")
        let mihomoURL = runtimeDirectory.appendingPathComponent("mihomo")
        let incomplete = RuntimeInstallationStatus(
            runtimeDirectory: runtimeDirectory,
            discoveredFiles: RuntimeDiscoveredFiles(files: [
                .mihomo: mihomoURL
            ]),
            executableFiles: []
        )

        XCTAssertFalse(incomplete.mihomoIsReady)
        XCTAssertFalse(incomplete.isReady)

        let complete = RuntimeInstallationStatus(
            runtimeDirectory: runtimeDirectory,
            discoveredFiles: RuntimeDiscoveredFiles(files: [
                .cfst: runtimeDirectory.appendingPathComponent("cfst"),
                .mihomo: mihomoURL,
            ]),
            executableFiles: [.cfst, .mihomo]
        )
        XCTAssertTrue(complete.cfstIsReady)
        XCTAssertTrue(complete.mihomoIsReady)
        XCTAssertTrue(complete.isReady)
    }

    func testDiscoversAndAtomicallyInstallsLocalPayload() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViaSix-Runtime-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("Source/Nested", isDirectory: true)
        let runtime = root.appendingPathComponent("Application Support/Runtime", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

        for payload in RuntimePayloadFile.allCases {
            try runtimeFixtureData(for: payload, marker: "first")
                .write(to: source.appendingPathComponent(payload.rawValue))
        }

        let manager = RuntimeComponentManager(runtimeDirectory: runtime)
        let initialStatus = await manager.installedStatus()
        XCTAssertFalse(initialStatus.isInstalled)

        let discovered = try await manager.discover(in: root.appendingPathComponent("Source"))
        XCTAssertEqual(discovered.installedFiles, Set(RuntimePayloadFile.allCases))

        let installedStatus = try await manager.install(from: root.appendingPathComponent("Source"))
        XCTAssertTrue(installedStatus.isReady)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: try XCTUnwrap(installedStatus.cfstURL).path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: try XCTUnwrap(installedStatus.mihomoURL).path))

        let replacementSource = root.appendingPathComponent("Replacement", isDirectory: true)
        try FileManager.default.createDirectory(at: replacementSource, withIntermediateDirectories: true)
        try runtimeFixtureData(for: .cfst, marker: "replacement")
            .write(to: replacementSource.appendingPathComponent(RuntimePayloadFile.cfst.rawValue))

        let updatedStatus = try await manager.install(from: replacementSource)
        XCTAssertTrue(updatedStatus.isReady)
        XCTAssertEqual(
            try Data(contentsOf: try XCTUnwrap(updatedStatus.cfstURL)),
            runtimeFixtureData(for: .cfst, marker: "replacement")
        )
        XCTAssertEqual(
            try Data(contentsOf: try XCTUnwrap(updatedStatus.mihomoURL)),
            runtimeFixtureData(for: .mihomo, marker: "first")
        )
    }

    func testDownloadedArchiveIsVerifiedBeforeUse() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViaSix-Download-\(UUID().uuidString)", isDirectory: true)
        let fixture = root.appendingPathComponent("fixture.zip")
        let destination = root.appendingPathComponent("Downloads", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let archiveData = Data("deterministic archive fixture".utf8)
        try archiveData.write(to: fixture)

        let asset = RuntimeAsset(
            component: .cfst,
            version: "test",
            architecture: .arm64,
            archiveName: "verified.zip",
            archiveFormat: .zip,
            downloadURL: URL(string: "https://example.invalid/verified.zip")!,
            sha256: RuntimeSHA256.hexDigest(of: archiveData),
            payloadExpectations: [RuntimePayloadExpectation(file: .cfst)]
        )
        let manager = RuntimeComponentManager(
            runtimeDirectory: root.appendingPathComponent("Runtime"),
            manifest: RuntimeManifest(assets: [asset]),
            downloadHandler: { _ in RuntimeDownloadedFile(fileURL: fixture, statusCode: 200) },
            archiveExtractor: { _, _, _ in }
        )

        let downloadedURL = try await manager.download(asset, to: destination)
        XCTAssertEqual(try Data(contentsOf: downloadedURL), archiveData)
    }

    func testChecksumMismatchRejectsAndRemovesArchive() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViaSix-Bad-Download-\(UUID().uuidString)", isDirectory: true)
        let fixture = root.appendingPathComponent("fixture.zip")
        let destination = root.appendingPathComponent("Downloads", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let archiveData = Data("tampered archive".utf8)
        try archiveData.write(to: fixture)

        let badHash = String(repeating: "0", count: 64)
        let asset = RuntimeAsset(
            component: .cfst,
            version: "test",
            architecture: .arm64,
            archiveName: "rejected.zip",
            archiveFormat: .zip,
            downloadURL: URL(string: "https://example.invalid/rejected.zip")!,
            sha256: badHash,
            payloadExpectations: [RuntimePayloadExpectation(file: .cfst)]
        )
        let manager = RuntimeComponentManager(
            runtimeDirectory: root.appendingPathComponent("Runtime"),
            manifest: RuntimeManifest(assets: [asset]),
            downloadHandler: { _ in RuntimeDownloadedFile(fileURL: fixture, statusCode: 200) },
            archiveExtractor: { _, _, _ in }
        )

        do {
            _ = try await manager.download(asset, to: destination)
            XCTFail("Expected checksum mismatch")
        } catch let error as RuntimeComponentError {
            XCTAssertEqual(
                error,
                .checksumMismatch(
                    archiveName: asset.archiveName,
                    expected: badHash,
                    actual: RuntimeSHA256.hexDigest(of: archiveData)
                )
            )
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: destination.appendingPathComponent(asset.archiveName).path
            )
        )
    }

    private func assertSendable<Value: Sendable>(_ value: Value) {
        _ = value
    }

    private func runtimeFixtureData(
        for payload: RuntimePayloadFile,
        marker: String
    ) -> Data {
        if payload.requiresExecutablePermission {
            return Data("#!/bin/sh\n# \(marker)-\(payload.rawValue)\nexit 0\n".utf8)
        }
        return Data("\(marker)-\(payload.rawValue)".utf8)
    }
}
