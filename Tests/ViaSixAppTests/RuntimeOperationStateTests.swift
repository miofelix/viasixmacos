import ViaSixCore
import XCTest

@testable import ViaSixApp

@MainActor
final class RuntimeOperationStateTests: XCTestCase {
    func testInstallingOneRuntimeComponentLeavesTheOtherAvailableForSeparateInstall() async throws {
        let paths = makePaths()
        let archiveURL = paths.root.appendingPathComponent("archive-fixture")
        defer { try? FileManager.default.removeItem(at: paths.root) }

        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        let archiveData = Data("archive fixture".utf8)
        try archiveData.write(to: archiveURL)
        let manager = RuntimeComponentManager(
            runtimeDirectory: paths.runtime,
            manifest: makeManifest(sha256: RuntimeSHA256.hexDigest(of: archiveData)),
            downloadHandler: { _ in
                RuntimeDownloadedFile(fileURL: archiveURL, statusCode: 200)
            },
            archiveExtractor: { _, _, destinationURL in
                try writeRuntimePayloads(to: destinationURL)
            }
        )
        let model = makeModel(paths: paths, runtimeManager: manager)

        model.installRuntime(.cfst)
        try await waitUntil { model.state.runtimeOperation == nil }

        XCTAssertTrue(model.state.runtimeStatus?.cfstIsReady == true)
        XCTAssertFalse(model.state.runtimeStatus?.mihomoIsReady == true)
        XCTAssertEqual(model.state.runtimeStatus?.missingFiles, [.mihomo])
        XCTAssertEqual(model.state.runtimePhase, .missing)
        XCTAssertEqual(model.state.notice?.message, "CloudflareSpeedTest 已安装")
        await model.shutdown()
    }

    func testCancellingRuntimeInstallRestoresDiskStateWithoutReportingFailure() async throws {
        let paths = makePaths()
        let archiveURL = paths.root.appendingPathComponent("archive-fixture")
        defer { try? FileManager.default.removeItem(at: paths.root) }

        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        let archiveData = Data("archive fixture".utf8)
        try archiveData.write(to: archiveURL)
        let manager = RuntimeComponentManager(
            runtimeDirectory: paths.runtime,
            manifest: makeManifest(sha256: RuntimeSHA256.hexDigest(of: archiveData)),
            downloadHandler: { _ in
                try await Task.sleep(for: .seconds(30))
                return RuntimeDownloadedFile(fileURL: archiveURL, statusCode: 200)
            },
            archiveExtractor: { _, _, destinationURL in
                try writeRuntimePayloads(to: destinationURL)
            }
        )
        let model = makeModel(paths: paths, runtimeManager: manager)

        model.installRuntime(.cfst)
        try await waitUntil {
            model.state.runtimeOperation == .installing(.cfst, .downloading(.cfst))
        }

        model.cancelRuntimeOperation()
        XCTAssertEqual(model.state.runtimeOperation, .cancelling)
        try await waitUntil { model.state.runtimeOperation == nil }

        XCTAssertEqual(model.state.runtimePhase, .missing)
        XCTAssertNil(model.state.runtimeOperationError)
        XCTAssertEqual(model.state.notice?.message, "已取消运行组件操作，现有组件保持不变")
        XCTAssertTrue(model.state.logs.contains { $0.message.contains("运行组件操作已取消") })
        await model.shutdown()
    }

    func testFailedRuntimeUpdateKeepsExistingComponentsReady() async throws {
        let paths = makePaths()
        let archiveURL = paths.root.appendingPathComponent("archive-fixture")
        defer { try? FileManager.default.removeItem(at: paths.root) }

        try makeReadyRuntime(at: paths.runtime)
        let archiveData = Data("tampered archive".utf8)
        try archiveData.write(to: archiveURL)
        let manager = RuntimeComponentManager(
            runtimeDirectory: paths.runtime,
            manifest: makeManifest(sha256: String(repeating: "0", count: 64)),
            downloadHandler: { _ in
                RuntimeDownloadedFile(fileURL: archiveURL, statusCode: 200)
            },
            archiveExtractor: { _, _, _ in
                XCTFail("Extraction must not run after checksum failure")
            }
        )
        let model = makeModel(paths: paths, runtimeManager: manager)

        model.installRuntime(.cfst)
        try await waitUntil {
            model.state.runtimeOperation == nil && model.state.runtimeOperationError != nil
        }

        XCTAssertEqual(model.state.runtimePhase, .ready)
        XCTAssertEqual(model.state.runtimeStatus?.isReady, true)
        XCTAssertTrue(model.state.runtimeOperationError?.contains("SHA256") == true)
        for payload in RuntimePayloadFile.allCases {
            XCTAssertEqual(
                try Data(contentsOf: paths.runtime.appendingPathComponent(payload.rawValue)),
                runtimeFixtureData(for: payload, marker: "existing")
            )
        }
        await model.shutdown()
    }

    private func makeModel(
        paths: AppPaths,
        runtimeManager: RuntimeComponentManager
    ) -> AppModel {
        AppModel(
            paths: paths,
            preferencesStore: PreferencesStore(fileURL: paths.preferences),
            bootstrapper: AppBootstrapper(paths: paths),
            runtimeManager: runtimeManager,
            exitDetector: ExitIPDetector()
        )
    }

    private func makePaths() -> AppPaths {
        AppPaths(
            root: FileManager.default.temporaryDirectory
                .appendingPathComponent("RuntimeOperationStateTests-\(UUID().uuidString)", isDirectory: true)
        )
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

    private func makeReadyRuntime(at runtimeURL: URL) throws {
        try FileManager.default.createDirectory(at: runtimeURL, withIntermediateDirectories: true)
        for payload in RuntimePayloadFile.allCases {
            let fileURL = runtimeURL.appendingPathComponent(payload.rawValue)
            try runtimeFixtureData(for: payload, marker: "existing").write(to: fileURL)
            if payload.requiresExecutablePermission {
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: fileURL.path
                )
            }
        }
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for runtime operation state")
        throw RuntimeOperationStateTestError.timedOut
    }
}

private enum RuntimeOperationStateTestError: Error {
    case timedOut
}

private func writeRuntimePayloads(to destinationURL: URL) throws {
    if destinationURL.lastPathComponent == RuntimeComponent.cfst.rawValue {
        try runtimeFixtureData(for: .cfst, marker: "downloaded")
            .write(to: destinationURL.appendingPathComponent(RuntimePayloadFile.cfst.rawValue))
        return
    }
    try runtimeFixtureData(for: .mihomo, marker: "downloaded")
        .write(to: destinationURL.appendingPathComponent(RuntimePayloadFile.mihomo.rawValue))
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
