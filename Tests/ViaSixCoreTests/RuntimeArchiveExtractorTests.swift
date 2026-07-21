import Foundation
import XCTest

@testable import ViaSixCore

final class RuntimeArchiveExtractorTests: XCTestCase {
    func testGzipUsesDeclaredFormatAndCanonicalOutputName() async throws {
        let root = makeRoot()
        let sourceURL = root.appendingPathComponent("untrusted-header-name")
        let archiveURL = root.appendingPathComponent("runtime-payload.zip")
        let destinationURL = root.appendingPathComponent("Extracted", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        let payloadData = Data("#!/bin/sh\nexit 0\n".utf8)
        try payloadData.write(to: sourceURL)
        try makeGzipArchive(from: sourceURL, at: archiveURL)

        let asset = makeAsset(
            component: .mihomo,
            archiveName: archiveURL.lastPathComponent,
            archiveFormat: .gzip(output: .mihomo),
            sha256: try RuntimeSHA256.hexDigest(ofFileAt: archiveURL)
        )
        try await RuntimeComponentManager.extractArchive(asset, archiveURL, destinationURL)

        let canonicalURL = destinationURL.appendingPathComponent(RuntimePayloadFile.mihomo.rawValue)
        XCTAssertEqual(try Data(contentsOf: canonicalURL), payloadData)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: destinationURL.appendingPathComponent(sourceURL.lastPathComponent).path
            )
        )
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: destinationURL.path),
            [RuntimePayloadFile.mihomo.rawValue]
        )
    }

    func testDamagedGzipFailsAndRemovesPartialOutput() async throws {
        let root = makeRoot()
        let archiveURL = root.appendingPathComponent("damaged-runtime")
        let destinationURL = root.appendingPathComponent("Extracted", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        let archiveData = Data("not a gzip archive".utf8)
        try archiveData.write(to: archiveURL)
        let asset = makeAsset(
            component: .mihomo,
            archiveName: archiveURL.lastPathComponent,
            archiveFormat: .gzip(output: .mihomo),
            sha256: RuntimeSHA256.hexDigest(of: archiveData)
        )

        do {
            try await RuntimeComponentManager.extractArchive(asset, archiveURL, destinationURL)
            XCTFail("Expected damaged gzip extraction to fail")
        } catch let error as RuntimeComponentError {
            guard case .extractionFailed(let archiveName, let status, _) = error else {
                return XCTFail("Unexpected runtime error: \(error)")
            }
            XCTAssertEqual(archiveName, archiveURL.lastPathComponent)
            XCTAssertNotEqual(status, 0)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: destinationURL.appendingPathComponent(RuntimePayloadFile.mihomo.rawValue).path
            )
        )
    }

    func testFailedGzipUpdateDoesNotCommitTransaction() async throws {
        let root = makeRoot()
        let archiveURL = root.appendingPathComponent("damaged-runtime.gz")
        let runtimeURL = root.appendingPathComponent("Runtime", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try makeReadyRuntime(at: runtimeURL, marker: "existing")
        let archiveData = Data("damaged gzip payload".utf8)
        try archiveData.write(to: archiveURL)
        let digest = RuntimeSHA256.hexDigest(of: archiveData)
        let manifest = RuntimeManifest(assets: [
            makeAsset(
                archiveName: "cfst-runtime.gz",
                archiveFormat: .gzip(output: .cfst),
                sha256: digest
            ),
            RuntimeAsset(
                component: .mihomo,
                version: "test",
                architecture: .arm64,
                archiveName: "mihomo-runtime.gz",
                archiveFormat: .gzip(output: .mihomo),
                downloadURL: URL(string: "https://example.invalid/mihomo-runtime.gz")!,
                sha256: digest,
                payloadExpectations: [RuntimePayloadExpectation(file: .mihomo)]
            ),
        ])
        let manager = RuntimeComponentManager(
            runtimeDirectory: runtimeURL,
            manifest: manifest,
            downloadHandler: { _ in
                RuntimeDownloadedFile(fileURL: archiveURL, statusCode: 200)
            },
            archiveExtractor: RuntimeComponentManager.extractArchive
        )

        do {
            _ = try await manager.downloadAndInstall(architecture: .arm64)
            XCTFail("Expected damaged gzip installation to fail")
        } catch let error as RuntimeComponentError {
            guard case .extractionFailed = error else {
                return XCTFail("Unexpected runtime error: \(error)")
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
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasPrefix(".Runtime-download-") || $0.hasPrefix(".Runtime-install-") }
        XCTAssertTrue(leftovers.isEmpty, "Unexpected transaction leftovers: \(leftovers)")
    }

    func testCancellingRunningGzipRemovesPartialOutputAndPreservesRuntime() async throws {
        let root = makeRoot()
        let archiveURL = root.appendingPathComponent("large-runtime.gz")
        let runtimeURL = root.appendingPathComponent("Runtime", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try makeReadyRuntime(at: runtimeURL, marker: "existing")
        try makeLargeConcatenatedGzipArchive(at: archiveURL, uncompressedMegabytes: 512)
        let digest = try RuntimeSHA256.hexDigest(ofFileAt: archiveURL)
        let archiveName = "cfst-cancel-\(UUID().uuidString).gz"
        let manifest = RuntimeManifest(assets: [
            makeAsset(
                archiveName: archiveName,
                archiveFormat: .gzip(output: .cfst),
                sha256: digest
            ),
            RuntimeAsset(
                component: .mihomo,
                version: "test",
                architecture: .arm64,
                archiveName: "mihomo-runtime.gz",
                archiveFormat: .gzip(output: .mihomo),
                downloadURL: URL(string: "https://example.invalid/mihomo-runtime.gz")!,
                sha256: digest,
                payloadExpectations: [RuntimePayloadExpectation(file: .mihomo)]
            ),
        ])
        let manager = RuntimeComponentManager(
            runtimeDirectory: runtimeURL,
            manifest: manifest,
            downloadHandler: { _ in
                RuntimeDownloadedFile(fileURL: archiveURL, statusCode: 200)
            },
            archiveExtractor: RuntimeComponentManager.extractArchive
        )
        let task = Task {
            try await manager.downloadAndInstall(architecture: .arm64)
        }
        let partialOutputURL = try await waitForTransactionalOutput(
            under: root,
            minimumSize: 1_048_576
        )
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected gzip extraction cancellation")
        } catch is CancellationError {
            // Expected.
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialOutputURL.path))

        let status = await manager.installedStatus()
        XCTAssertTrue(status.isReady)
        for payload in RuntimePayloadFile.allCases {
            XCTAssertEqual(
                try Data(contentsOf: runtimeURL.appendingPathComponent(payload.rawValue)),
                runtimeFixtureData(for: payload, marker: "existing")
            )
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasPrefix(".Runtime-download-") || $0.hasPrefix(".Runtime-install-") }
        XCTAssertTrue(leftovers.isEmpty, "Unexpected transaction leftovers: \(leftovers)")
        XCTAssertFalse(try runningProcessCommands().contains { $0.contains(archiveName) })
    }

    private func makeAsset(
        component: RuntimeComponent = .cfst,
        archiveName: String,
        archiveFormat: RuntimeArchiveFormat,
        sha256: String
    ) -> RuntimeAsset {
        RuntimeAsset(
            component: component,
            version: "test",
            architecture: .arm64,
            archiveName: archiveName,
            archiveFormat: archiveFormat,
            downloadURL: URL(string: "https://example.invalid/\(archiveName)")!,
            sha256: sha256,
            payloadExpectations: component.payloadFiles.map {
                RuntimePayloadExpectation(file: $0)
            }
        )
    }

    private func makeRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ViaSix-RuntimeArchive-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeGzipArchive(from sourceURL: URL, at archiveURL: URL) throws {
        FileManager.default.createFile(atPath: archiveURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: archiveURL)
        defer { try? output.close() }
        let errors = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-c", "--", sourceURL.path]
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let errorOutput = String(
            decoding: errors.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        guard process.terminationStatus == 0 else {
            throw RuntimeArchiveExtractorTestError.gzipFailed(
                status: process.terminationStatus,
                output: errorOutput
            )
        }
    }

    private func makeLargeConcatenatedGzipArchive(
        at archiveURL: URL,
        uncompressedMegabytes: Int
    ) throws {
        let memberSourceURL = archiveURL.deletingLastPathComponent()
            .appendingPathComponent("gzip-member-source")
        let memberArchiveURL = archiveURL.deletingLastPathComponent()
            .appendingPathComponent("gzip-member.gz")
        try Data(repeating: 0, count: 1_048_576).write(to: memberSourceURL)
        try makeGzipArchive(from: memberSourceURL, at: memberArchiveURL)
        let member = try Data(contentsOf: memberArchiveURL)

        FileManager.default.createFile(atPath: archiveURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: archiveURL)
        defer { try? output.close() }
        for _ in 0..<uncompressedMegabytes {
            try output.write(contentsOf: member)
        }
    }

    private func makeReadyRuntime(at runtimeURL: URL, marker: String) throws {
        try FileManager.default.createDirectory(at: runtimeURL, withIntermediateDirectories: true)
        for payload in RuntimePayloadFile.allCases {
            let fileURL = runtimeURL.appendingPathComponent(payload.rawValue)
            try runtimeFixtureData(for: payload, marker: marker).write(to: fileURL)
            if payload.requiresExecutablePermission {
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: fileURL.path
                )
            }
        }
    }

    private func waitForTransactionalOutput(
        under root: URL,
        minimumSize: Int
    ) async throws -> URL {
        for _ in 0..<5_000 {
            let entries = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil
            )
            for workspaceURL in entries
            where workspaceURL.lastPathComponent.hasPrefix(
                ".Runtime-download-"
            ) {
                let outputURL =
                    workspaceURL
                    .appendingPathComponent("Extracted", isDirectory: true)
                    .appendingPathComponent(RuntimeComponent.cfst.rawValue, isDirectory: true)
                    .appendingPathComponent(RuntimePayloadFile.cfst.rawValue)
                if let size = try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                    size >= minimumSize
                {
                    return outputURL
                }
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw RuntimeArchiveExtractorTestError.timedOutWaitingForExtraction
    }

    private func runningProcessCommands() throws -> [String] {
        let output = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "command="]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let processData = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw RuntimeArchiveExtractorTestError.processListingFailed(process.terminationStatus)
        }
        return String(
            decoding: processData,
            as: UTF8.self
        ).split(separator: "\n").map(String.init)
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

private enum RuntimeArchiveExtractorTestError: Error {
    case gzipFailed(status: Int32, output: String)
    case processListingFailed(Int32)
    case timedOutWaitingForExtraction
}
