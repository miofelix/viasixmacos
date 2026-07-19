import Foundation
import XCTest

@testable import ViaSixCore

final class RuntimeComponentCancellationTests: XCTestCase {
    func testCancellationAfterExtractorReturnsDoesNotInstallRuntime() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViaSix-RuntimeCancellation-\(UUID().uuidString)", isDirectory: true)
        let fixtureURL = root.appendingPathComponent("archive-fixture")
        let extractionStartedURL = root.appendingPathComponent("extraction-started")
        let runtimeURL = root.appendingPathComponent("Runtime", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let archiveData = Data("archive fixture".utf8)
        try archiveData.write(to: fixtureURL)
        let digest = RuntimeSHA256.hexDigest(of: archiveData)
        let manifest = RuntimeManifest(assets: [
            RuntimeAsset(
                component: .cfst,
                version: "test",
                architecture: .arm64,
                archiveName: "cfst.zip",
                downloadURL: URL(string: "https://example.invalid/cfst.zip")!,
                sha256: digest,
                payloadFiles: [.cfst]
            ),
            RuntimeAsset(
                component: .xray,
                version: "test",
                architecture: .arm64,
                archiveName: "xray.zip",
                downloadURL: URL(string: "https://example.invalid/xray.zip")!,
                sha256: digest,
                payloadFiles: [.xray, .geoIP, .geoSite]
            ),
        ])
        let manager = RuntimeComponentManager(
            runtimeDirectory: runtimeURL,
            manifest: manifest,
            downloadHandler: { _ in
                RuntimeDownloadedFile(fileURL: fixtureURL, statusCode: 200)
            },
            archiveExtractor: { _, destinationURL in
                try Data("started".utf8).write(to: extractionStartedURL, options: .atomic)
                // Model an extractor that notices cancellation late and still
                // returns normally. The manager must check cancellation before
                // discovering or committing its output.
                try? await Task.sleep(for: .seconds(30))
                try Data("cfst".utf8).write(
                    to: destinationURL.appendingPathComponent(RuntimePayloadFile.cfst.rawValue)
                )
            }
        )

        let installTask = Task {
            try await manager.downloadAndInstall(architecture: .arm64)
        }
        try await waitUntilFileExists(extractionStartedURL)
        installTask.cancel()

        do {
            _ = try await installTask.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }

        let status = await manager.installedStatus()
        XCTAssertFalse(status.isInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: runtimeURL.path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasPrefix(".Runtime-download-") || $0.hasPrefix(".Runtime-install-") }
        XCTAssertTrue(leftovers.isEmpty, "Unexpected transaction leftovers: \(leftovers)")
    }

    private func waitUntilFileExists(_ url: URL) async throws {
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: url.path) { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for \(url.path)")
    }
}
