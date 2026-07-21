import Foundation
import XCTest

@testable import ViaSixCore

final class RuntimeComponentCancellationTests: XCTestCase {
    func testSingleComponentInstallPreservesTheOtherManagedComponent() async throws {
        let root = makeRoot()
        let archiveURL = root.appendingPathComponent("archive-fixture")
        let runtimeURL = root.appendingPathComponent("Runtime", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: runtimeURL, withIntermediateDirectories: true)
        for payload in RuntimePayloadFile.allCases {
            let url = runtimeURL.appendingPathComponent(payload.rawValue)
            try runtimeFixtureData(for: payload, marker: "existing").write(to: url)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: url.path
            )
        }
        let archiveData = Data("archive fixture".utf8)
        try archiveData.write(to: archiveURL)
        let manifest = makeManifest(sha256: RuntimeSHA256.hexDigest(of: archiveData))
        let recorder = RuntimeComponentDownloadRecorder()
        let manager = RuntimeComponentManager(
            runtimeDirectory: runtimeURL,
            manifest: manifest,
            downloadHandler: { url in
                await recorder.append(url)
                return RuntimeDownloadedFile(fileURL: archiveURL, statusCode: 200)
            },
            archiveExtractor: { asset, _, destinationURL in
                XCTAssertEqual(asset.component, .cfst)
                try runtimeFixtureData(for: .cfst, marker: "downloaded").write(
                    to: destinationURL.appendingPathComponent(RuntimePayloadFile.cfst.rawValue)
                )
            }
        )

        let status = try await manager.downloadAndInstall(
            component: .cfst,
            architecture: .arm64
        )

        XCTAssertTrue(status.isReady)
        XCTAssertEqual(
            try Data(contentsOf: runtimeURL.appendingPathComponent(RuntimePayloadFile.cfst.rawValue)),
            runtimeFixtureData(for: .cfst, marker: "downloaded")
        )
        XCTAssertEqual(
            try Data(
                contentsOf: runtimeURL.appendingPathComponent(RuntimePayloadFile.mihomo.rawValue)
            ),
            runtimeFixtureData(for: .mihomo, marker: "existing")
        )
        let requestedURLs = await recorder.urls
        XCTAssertEqual(
            requestedURLs,
            [manifest.asset(for: .cfst, architecture: .arm64)!.downloadURL]
        )
    }

    func testSingleComponentInstallDoesNotRequireTheOtherComponent() async throws {
        let root = makeRoot()
        let archiveURL = root.appendingPathComponent("archive-fixture")
        let runtimeURL = root.appendingPathComponent("Runtime", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let archiveData = Data("archive fixture".utf8)
        try archiveData.write(to: archiveURL)
        let manager = RuntimeComponentManager(
            runtimeDirectory: runtimeURL,
            manifest: makeManifest(sha256: RuntimeSHA256.hexDigest(of: archiveData)),
            downloadHandler: { _ in
                RuntimeDownloadedFile(fileURL: archiveURL, statusCode: 200)
            },
            archiveExtractor: { asset, _, destinationURL in
                XCTAssertEqual(asset.component, .mihomo)
                try runtimeFixtureData(for: .mihomo, marker: "downloaded").write(
                    to: destinationURL.appendingPathComponent(RuntimePayloadFile.mihomo.rawValue)
                )
            }
        )

        let status = try await manager.downloadAndInstall(
            component: .mihomo,
            architecture: .arm64
        )

        XCTAssertTrue(status.mihomoIsReady)
        XCTAssertFalse(status.cfstIsReady)
        XCTAssertEqual(status.missingFiles, [.cfst])
    }

    func testSingleComponentInstallIsNotBlockedByAnInvalidOtherComponent() async throws {
        let root = makeRoot()
        let archiveURL = root.appendingPathComponent("archive-fixture")
        let runtimeURL = root.appendingPathComponent("Runtime", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: runtimeURL, withIntermediateDirectories: true)
        let invalidMihomoURL = runtimeURL.appendingPathComponent(RuntimePayloadFile.mihomo.rawValue)
        try Data("not an executable".utf8).write(to: invalidMihomoURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: invalidMihomoURL.path
        )
        let archiveData = Data("archive fixture".utf8)
        try archiveData.write(to: archiveURL)
        let manager = RuntimeComponentManager(
            runtimeDirectory: runtimeURL,
            manifest: makeManifest(sha256: RuntimeSHA256.hexDigest(of: archiveData)),
            downloadHandler: { _ in
                RuntimeDownloadedFile(fileURL: archiveURL, statusCode: 200)
            },
            archiveExtractor: { asset, _, destinationURL in
                XCTAssertEqual(asset.component, .cfst)
                try runtimeFixtureData(for: .cfst, marker: "downloaded").write(
                    to: destinationURL.appendingPathComponent(RuntimePayloadFile.cfst.rawValue)
                )
            }
        )

        let status = try await manager.downloadAndInstall(
            component: .cfst,
            architecture: .arm64
        )

        XCTAssertTrue(status.cfstIsReady)
        XCTAssertFalse(status.mihomoIsReady)
        XCTAssertEqual(status.invalidFiles, [.mihomo])
        XCTAssertEqual(try Data(contentsOf: invalidMihomoURL), Data("not an executable".utf8))
    }

    func testDownloadAndInstallReportsStagesInOrder() async throws {
        let root = makeRoot()
        let archiveURL = root.appendingPathComponent("archive-fixture")
        let runtimeURL = root.appendingPathComponent("Runtime", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let archiveData = Data("archive fixture".utf8)
        try archiveData.write(to: archiveURL)
        let manifest = makeManifest(sha256: RuntimeSHA256.hexDigest(of: archiveData))
        let recorder = RuntimeInstallationStageRecorder()
        let manager = RuntimeComponentManager(
            runtimeDirectory: runtimeURL,
            manifest: manifest,
            downloadHandler: { _ in
                RuntimeDownloadedFile(fileURL: archiveURL, statusCode: 200)
            },
            archiveExtractor: { _, _, destinationURL in
                try writeRuntimePayloads(to: destinationURL)
            }
        )

        let status = try await manager.downloadAndInstall(architecture: .arm64) { stage in
            await recorder.append(stage)
        }

        XCTAssertTrue(status.isReady)
        let stages = await recorder.stages
        XCTAssertEqual(
            stages,
            [
                .preparingInstallation,
                .downloading(.cfst),
                .verifying(.cfst),
                .extracting(.cfst),
                .downloading(.mihomo),
                .verifying(.mihomo),
                .extracting(.mihomo),
                .committing,
            ]
        )
    }

    func testConcurrentRuntimeOperationIsRejectedUntilFirstCompletes() async throws {
        let root = makeRoot()
        let archiveURL = root.appendingPathComponent("archive-fixture")
        let runtimeURL = root.appendingPathComponent("Runtime", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let archiveData = Data("archive fixture".utf8)
        try archiveData.write(to: archiveURL)
        let gate = RuntimeDownloadGate()
        let manager = RuntimeComponentManager(
            runtimeDirectory: runtimeURL,
            manifest: makeManifest(sha256: RuntimeSHA256.hexDigest(of: archiveData)),
            downloadHandler: { _ in
                await gate.wait()
                return RuntimeDownloadedFile(fileURL: archiveURL, statusCode: 200)
            },
            archiveExtractor: { _, _, destinationURL in
                try writeRuntimePayloads(to: destinationURL)
            }
        )

        let firstOperation = Task {
            try await manager.downloadAndInstall(architecture: .arm64)
        }
        try await waitUntil { await gate.waiterCount > 0 }

        do {
            _ = try await manager.install(from: root)
            XCTFail("Expected the overlapping operation to be rejected")
        } catch let error as RuntimeComponentError {
            XCTAssertEqual(error, .operationInProgress)
        }

        await gate.open()
        let firstStatus = try await firstOperation.value
        XCTAssertTrue(firstStatus.isReady)
    }

    func testFailedUpdatePreservesExistingRuntime() async throws {
        let root = makeRoot()
        let archiveURL = root.appendingPathComponent("archive-fixture")
        let runtimeURL = root.appendingPathComponent("Runtime", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: runtimeURL, withIntermediateDirectories: true)
        for payload in RuntimePayloadFile.allCases {
            try runtimeFixtureData(for: payload, marker: "existing")
                .write(to: runtimeURL.appendingPathComponent(payload.rawValue))
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: runtimeURL.appendingPathComponent(RuntimePayloadFile.cfst.rawValue).path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: runtimeURL.appendingPathComponent(RuntimePayloadFile.mihomo.rawValue).path
        )

        let archiveData = Data("tampered archive".utf8)
        try archiveData.write(to: archiveURL)
        let manager = RuntimeComponentManager(
            runtimeDirectory: runtimeURL,
            manifest: makeManifest(sha256: String(repeating: "0", count: 64)),
            downloadHandler: { _ in
                RuntimeDownloadedFile(fileURL: archiveURL, statusCode: 200)
            },
            archiveExtractor: { _, _, _ in
                XCTFail("Extraction must not run after checksum failure")
            }
        )

        do {
            _ = try await manager.downloadAndInstall(architecture: .arm64)
            XCTFail("Expected checksum failure")
        } catch let error as RuntimeComponentError {
            guard case .checksumMismatch = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let status = await manager.installedStatus()
        XCTAssertTrue(status.isReady)
        for payload in RuntimePayloadFile.allCases {
            XCTAssertEqual(
                try Data(contentsOf: runtimeURL.appendingPathComponent(payload.rawValue)),
                runtimeFixtureData(for: payload, marker: "existing")
            )
        }
    }

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
                archiveFormat: .zip,
                downloadURL: URL(string: "https://example.invalid/cfst.zip")!,
                sha256: digest,
                payloadExpectations: [RuntimePayloadExpectation(file: .cfst)]
            ),
            RuntimeAsset(
                component: .mihomo,
                version: "test",
                architecture: .arm64,
                archiveName: "mihomo.gz",
                archiveFormat: .gzip(output: .mihomo),
                downloadURL: URL(string: "https://example.invalid/mihomo.gz")!,
                sha256: digest,
                payloadExpectations: [RuntimePayloadExpectation(file: .mihomo)]
            ),
        ])
        let manager = RuntimeComponentManager(
            runtimeDirectory: runtimeURL,
            manifest: manifest,
            downloadHandler: { _ in
                RuntimeDownloadedFile(fileURL: fixtureURL, statusCode: 200)
            },
            archiveExtractor: { _, _, destinationURL in
                try Data("started".utf8).write(to: extractionStartedURL, options: .atomic)
                // Model an extractor that notices cancellation late and still
                // returns normally. The manager must check cancellation before
                // discovering or committing its output.
                try? await Task.sleep(for: .seconds(30))
                try runtimeFixtureData(for: .cfst, marker: "cancelled").write(
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

    private func waitUntil(_ predicate: @escaping @Sendable () async -> Bool) async throws {
        for _ in 0..<100 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for runtime test condition")
    }

    private func makeRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ViaSix-RuntimeCancellation-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeManifest(sha256: String) -> RuntimeManifest {
        RuntimeManifest(assets: [
            RuntimeAsset(
                component: .cfst,
                version: "test",
                architecture: .arm64,
                archiveName: "cfst.zip",
                archiveFormat: .zip,
                downloadURL: URL(string: "https://example.invalid/cfst.zip")!,
                sha256: sha256,
                payloadExpectations: [RuntimePayloadExpectation(file: .cfst)]
            ),
            RuntimeAsset(
                component: .mihomo,
                version: "test",
                architecture: .arm64,
                archiveName: "mihomo.gz",
                archiveFormat: .gzip(output: .mihomo),
                downloadURL: URL(string: "https://example.invalid/mihomo.gz")!,
                sha256: sha256,
                payloadExpectations: [RuntimePayloadExpectation(file: .mihomo)]
            ),
        ])
    }
}

private actor RuntimeComponentDownloadRecorder {
    private(set) var urls: [URL] = []

    func append(_ url: URL) {
        urls.append(url)
    }
}

private actor RuntimeInstallationStageRecorder {
    private(set) var stages: [RuntimeInstallationStage] = []

    func append(_ stage: RuntimeInstallationStage) {
        stages.append(stage)
    }
}

private actor RuntimeDownloadGate {
    private(set) var waiterCount = 0
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        waiterCount += 1
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}

private func writeRuntimePayloads(to destinationURL: URL) throws {
    let fileManager = FileManager.default
    let component = destinationURL.lastPathComponent
    if component == RuntimeComponent.cfst.rawValue {
        try runtimeFixtureData(for: .cfst, marker: "downloaded")
            .write(to: destinationURL.appendingPathComponent(RuntimePayloadFile.cfst.rawValue))
    } else if component == RuntimeComponent.mihomo.rawValue {
        try runtimeFixtureData(for: .mihomo, marker: "downloaded")
            .write(to: destinationURL.appendingPathComponent(RuntimePayloadFile.mihomo.rawValue))
    } else {
        throw POSIXError(.EINVAL)
    }
    try fileManager.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: destinationURL.appendingPathComponent(
            component == RuntimeComponent.cfst.rawValue
                ? RuntimePayloadFile.cfst.rawValue
                : RuntimePayloadFile.mihomo.rawValue
        ).path
    )
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
