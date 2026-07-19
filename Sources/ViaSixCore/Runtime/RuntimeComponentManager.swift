import Foundation

public struct RuntimeDiscoveredFiles: Equatable, Sendable {
    public let files: [RuntimePayloadFile: URL]

    public init(files: [RuntimePayloadFile: URL] = [:]) {
        self.files = files
    }

    public subscript(file: RuntimePayloadFile) -> URL? {
        files[file]
    }

    public var cfstURL: URL? { self[.cfst] }
    public var xrayURL: URL? { self[.xray] }
    public var geoIPURL: URL? { self[.geoIP] }
    public var geoSiteURL: URL? { self[.geoSite] }

    public var installedFiles: Set<RuntimePayloadFile> {
        Set(files.keys)
    }

    public var missingFiles: Set<RuntimePayloadFile> {
        Set(RuntimePayloadFile.allCases).subtracting(installedFiles)
    }

    public var isComplete: Bool {
        missingFiles.isEmpty
    }
}

public struct RuntimeInstallationStatus: Equatable, Sendable {
    public let runtimeDirectory: URL
    public let discoveredFiles: RuntimeDiscoveredFiles
    public let executableFiles: Set<RuntimePayloadFile>

    public init(
        runtimeDirectory: URL,
        discoveredFiles: RuntimeDiscoveredFiles,
        executableFiles: Set<RuntimePayloadFile>
    ) {
        self.runtimeDirectory = runtimeDirectory
        self.discoveredFiles = discoveredFiles
        self.executableFiles = executableFiles
    }

    public var cfstURL: URL? { discoveredFiles.cfstURL }
    public var xrayURL: URL? { discoveredFiles.xrayURL }
    public var geoIPURL: URL? { discoveredFiles.geoIPURL }
    public var geoSiteURL: URL? { discoveredFiles.geoSiteURL }
    public var missingFiles: Set<RuntimePayloadFile> { discoveredFiles.missingFiles }
    public var isInstalled: Bool { discoveredFiles.isComplete }

    public var cfstIsReady: Bool {
        cfstURL != nil && executableFiles.contains(.cfst)
    }

    public var xrayIsReady: Bool {
        xrayURL != nil
            && geoIPURL != nil
            && geoSiteURL != nil
            && executableFiles.contains(.xray)
    }

    public var isReady: Bool {
        isInstalled && cfstIsReady && xrayIsReady
    }
}

public struct RuntimeDownloadedFile: Equatable, Sendable {
    public let fileURL: URL
    public let statusCode: Int

    public init(fileURL: URL, statusCode: Int) {
        self.fileURL = fileURL
        self.statusCode = statusCode
    }
}

public typealias RuntimeDownloadHandler = @Sendable (URL) async throws -> RuntimeDownloadedFile
public typealias RuntimeArchiveExtractor = @Sendable (URL, URL) async throws -> Void

public enum RuntimeComponentError: LocalizedError, Equatable, Sendable {
    case missingManifestAsset(RuntimeComponent, RuntimeArchitecture)
    case missingLatestRelease(RuntimeComponent)
    case invalidLatestRelease(RuntimeComponent)
    case missingLatestReleaseAsset(RuntimeComponent, String)
    case missingLatestReleaseDigest(RuntimeComponent, String)
    case sourceNotFound(URL)
    case sourceIsNotFileOrDirectory(URL)
    case noPayloadFiles([URL])
    case missingArchivePayload(RuntimeComponent, Set<RuntimePayloadFile>)
    case invalidDownloadResponse(URL)
    case httpStatus(Int, URL)
    case checksumMismatch(archiveName: String, expected: String, actual: String)
    case extractionFailed(archiveName: String, status: Int32, output: String)
    case extractionTimedOut(archiveName: String)
    case invalidRuntimeDirectory(URL)

    public var errorDescription: String? {
        switch self {
        case .missingManifestAsset(let component, let architecture):
            return "缺少 \(component.rawValue) 的 \(architecture.rawValue) 运行组件清单。"
        case .missingLatestRelease(let component):
            return "未能解析 \(component.displayName) 的最新正式版本。"
        case .invalidLatestRelease(let component):
            return "\(component.displayName) 的 GitHub 最新版本信息无效。"
        case .missingLatestReleaseAsset(let component, let archiveName):
            return "\(component.displayName) 的最新版本缺少当前 Mac 所需的 \(archiveName)。"
        case .missingLatestReleaseDigest(let component, let archiveName):
            return "\(component.displayName) 的 \(archiveName) 未提供可用的 SHA-256 校验值。"
        case .sourceNotFound(let url):
            return "本地路径不存在：\(url.path)"
        case .sourceIsNotFileOrDirectory(let url):
            return "本地路径不是可读取的文件或目录：\(url.path)"
        case .noPayloadFiles(let urls):
            return "未在本地路径中找到 cfst、xray、geoip.dat 或 geosite.dat：\(urls.map(\.path).joined(separator: ", "))"
        case .missingArchivePayload(let component, let files):
            let names = files.map(\.rawValue).sorted().joined(separator: ", ")
            return "\(component.rawValue) 压缩包缺少必要文件：\(names)"
        case .invalidDownloadResponse(let url):
            return "下载响应不是有效的 HTTP 响应：\(url.absoluteString)"
        case .httpStatus(let status, let url):
            return "下载失败（HTTP \(status)）：\(url.absoluteString)"
        case .checksumMismatch(let archiveName, let expected, let actual):
            return "\(archiveName) 的 SHA256 校验失败，预期 \(expected)，实际 \(actual)。"
        case .extractionFailed(let archiveName, let status, let output):
            return "解压 \(archiveName) 失败（退出码 \(status)）：\(output)"
        case .extractionTimedOut(let archiveName):
            return "解压 \(archiveName) 超时，已停止解压进程。"
        case .invalidRuntimeDirectory(let url):
            return "Runtime 路径已存在，但不是目录：\(url.path)"
        }
    }
}

public actor RuntimeComponentManager {
    private static let extractionTimeout: Duration = .seconds(120)

    public let runtimeDirectory: URL
    public let manifest: RuntimeManifest

    private let downloadHandler: RuntimeDownloadHandler
    private let archiveExtractor: RuntimeArchiveExtractor
    private let releaseResolver: RuntimeReleaseResolver?

    public init(
        runtimeDirectory: URL,
        manifest: RuntimeManifest = .current
    ) {
        self.runtimeDirectory = runtimeDirectory.standardizedFileURL
        self.manifest = manifest
        self.downloadHandler = Self.downloadUsingURLSession
        self.archiveExtractor = Self.extractUsingDitto
        self.releaseResolver = RuntimeReleaseResolver()
    }

    public init(
        paths: AppPaths,
        manifest: RuntimeManifest = .current
    ) {
        self.init(runtimeDirectory: paths.runtime, manifest: manifest)
    }

    public init(
        runtimeDirectory: URL,
        manifest: RuntimeManifest = .current,
        downloadHandler: @escaping RuntimeDownloadHandler,
        archiveExtractor: @escaping RuntimeArchiveExtractor
    ) {
        self.runtimeDirectory = runtimeDirectory.standardizedFileURL
        self.manifest = manifest
        self.downloadHandler = downloadHandler
        self.archiveExtractor = archiveExtractor
        self.releaseResolver = nil
    }

    public func installedStatus() -> RuntimeInstallationStatus {
        let fileManager = FileManager.default
        var files: [RuntimePayloadFile: URL] = [:]
        var executableFiles = Set<RuntimePayloadFile>()

        for payload in RuntimePayloadFile.allCases {
            let fileURL = runtimeDirectory.appendingPathComponent(payload.rawValue)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
                !isDirectory.boolValue
            else {
                continue
            }
            files[payload] = fileURL
            if payload.requiresExecutablePermission,
                fileManager.isExecutableFile(atPath: fileURL.path)
            {
                executableFiles.insert(payload)
            }
        }

        return RuntimeInstallationStatus(
            runtimeDirectory: runtimeDirectory,
            discoveredFiles: RuntimeDiscoveredFiles(files: files),
            executableFiles: executableFiles
        )
    }

    public func discover(in sourcePath: URL) throws -> RuntimeDiscoveredFiles {
        try discover(in: [sourcePath])
    }

    public func discover(in sourcePaths: [URL]) throws -> RuntimeDiscoveredFiles {
        let files = try Self.discoverFiles(
            in: sourcePaths.map(\.standardizedFileURL),
            using: FileManager.default
        )
        return RuntimeDiscoveredFiles(files: files)
    }

    @discardableResult
    public func install(from sourcePath: URL) throws -> RuntimeInstallationStatus {
        try install(from: [sourcePath])
    }

    @discardableResult
    public func install(from sourcePaths: [URL]) throws -> RuntimeInstallationStatus {
        try Task.checkCancellation()
        let normalizedPaths = sourcePaths.map(\.standardizedFileURL)
        let files = try Self.discoverFiles(in: normalizedPaths, using: FileManager.default)
        try Task.checkCancellation()
        guard !files.isEmpty else {
            throw RuntimeComponentError.noPayloadFiles(normalizedPaths)
        }
        return try atomicallyInstall(files)
    }

    @discardableResult
    public func downloadAndInstall(
        architecture: RuntimeArchitecture = .current
    ) async throws -> RuntimeInstallationStatus {
        try Task.checkCancellation()
        let assets: [RuntimeAsset]
        if let releaseResolver {
            assets = try await releaseResolver.latestAssets(for: architecture)
        } else {
            assets = try assetsForInstallation(architecture: architecture)
        }
        try Task.checkCancellation()
        let fileManager = FileManager.default
        let workspace = transactionDirectory(prefix: "download")
        let downloadsDirectory = workspace.appendingPathComponent("Downloads", isDirectory: true)
        let extractedDirectory = workspace.appendingPathComponent("Extracted", isDirectory: true)

        try fileManager.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: extractedDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspace) }

        var payloadFiles: [RuntimePayloadFile: URL] = [:]
        for asset in assets {
            try Task.checkCancellation()
            let archiveURL = try await download(asset, to: downloadsDirectory)
            try Task.checkCancellation()
            let componentDirectory =
                extractedDirectory
                .appendingPathComponent(asset.component.rawValue, isDirectory: true)
            try fileManager.createDirectory(at: componentDirectory, withIntermediateDirectories: true)
            try await archiveExtractor(archiveURL, componentDirectory)
            try Task.checkCancellation()

            let discovered = try Self.discoverFiles(
                in: [componentDirectory],
                using: fileManager
            )
            let requiredFiles = Set(asset.payloadFiles)
            let missingFiles = requiredFiles.subtracting(discovered.keys)
            guard missingFiles.isEmpty else {
                throw RuntimeComponentError.missingArchivePayload(asset.component, missingFiles)
            }
            for payload in asset.payloadFiles {
                payloadFiles[payload] = discovered[payload]
            }
        }

        try Task.checkCancellation()
        return try atomicallyInstall(payloadFiles)
    }

    public func download(_ asset: RuntimeAsset, to destinationDirectory: URL) async throws -> URL {
        try Task.checkCancellation()
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let downloaded = try await downloadHandler(asset.downloadURL)
        try Task.checkCancellation()
        guard (200...299).contains(downloaded.statusCode) else {
            throw RuntimeComponentError.httpStatus(downloaded.statusCode, asset.downloadURL)
        }

        let archiveURL = destinationDirectory.appendingPathComponent(asset.archiveName)
        var shouldRemoveArchive = true
        defer {
            if shouldRemoveArchive {
                try? fileManager.removeItem(at: archiveURL)
            }
        }
        if fileManager.fileExists(atPath: archiveURL.path) {
            try fileManager.removeItem(at: archiveURL)
        }
        try fileManager.copyItem(at: downloaded.fileURL, to: archiveURL)
        try Task.checkCancellation()

        let digest = try RuntimeSHA256.hexDigest(ofFileAt: archiveURL)
        try Task.checkCancellation()
        guard digest == asset.sha256.lowercased() else {
            throw RuntimeComponentError.checksumMismatch(
                archiveName: asset.archiveName,
                expected: asset.sha256.lowercased(),
                actual: digest
            )
        }
        shouldRemoveArchive = false
        return archiveURL
    }

    private func assetsForInstallation(
        architecture: RuntimeArchitecture
    ) throws -> [RuntimeAsset] {
        try RuntimeComponent.allCases.map { component in
            guard let asset = manifest.asset(for: component, architecture: architecture) else {
                throw RuntimeComponentError.missingManifestAsset(component, architecture)
            }
            return asset
        }
    }

    private func atomicallyInstall(
        _ sourceFiles: [RuntimePayloadFile: URL]
    ) throws -> RuntimeInstallationStatus {
        try Task.checkCancellation()
        let fileManager = FileManager.default
        let parentDirectory = runtimeDirectory.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        var isDirectory: ObjCBool = false
        let runtimeExists = fileManager.fileExists(
            atPath: runtimeDirectory.path,
            isDirectory: &isDirectory
        )
        if runtimeExists && !isDirectory.boolValue {
            throw RuntimeComponentError.invalidRuntimeDirectory(runtimeDirectory)
        }

        let workspace = transactionDirectory(prefix: "install")
        let candidateDirectory = workspace.appendingPathComponent("Runtime", isDirectory: true)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspace) }

        if runtimeExists {
            try fileManager.copyItem(at: runtimeDirectory, to: candidateDirectory)
        } else {
            try fileManager.createDirectory(at: candidateDirectory, withIntermediateDirectories: true)
        }

        for (payload, sourceURL) in sourceFiles {
            try Task.checkCancellation()
            let destinationURL = candidateDirectory.appendingPathComponent(payload.rawValue)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }

        for payload in RuntimePayloadFile.allCases where payload.requiresExecutablePermission {
            try Task.checkCancellation()
            let executableURL = candidateDirectory.appendingPathComponent(payload.rawValue)
            guard fileManager.fileExists(atPath: executableURL.path) else { continue }
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o755)],
                ofItemAtPath: executableURL.path
            )
        }

        // This is the commit point. Cancellation is honored before the atomic
        // replacement; once replacement starts it must run to completion so a
        // partially installed Runtime directory is never exposed.
        try Task.checkCancellation()
        if runtimeExists {
            let backupName = ".\(runtimeDirectory.lastPathComponent)-backup-\(UUID().uuidString)"
            _ = try fileManager.replaceItemAt(
                runtimeDirectory,
                withItemAt: candidateDirectory,
                backupItemName: backupName,
                options: []
            )
            let backupURL = parentDirectory.appendingPathComponent(backupName)
            try? fileManager.removeItem(at: backupURL)
        } else {
            try fileManager.moveItem(at: candidateDirectory, to: runtimeDirectory)
        }

        return installedStatus()
    }

    private func transactionDirectory(prefix: String) -> URL {
        runtimeDirectory.deletingLastPathComponent().appendingPathComponent(
            ".\(runtimeDirectory.lastPathComponent)-\(prefix)-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private static func discoverFiles(
        in sourcePaths: [URL],
        using fileManager: FileManager
    ) throws -> [RuntimePayloadFile: URL] {
        var candidates: [RuntimePayloadFile: [URL]] = [:]
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ]

        for sourcePath in sourcePaths {
            try Task.checkCancellation()
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: sourcePath.path, isDirectory: &isDirectory) else {
                throw RuntimeComponentError.sourceNotFound(sourcePath)
            }

            if isDirectory.boolValue {
                guard
                    let enumerator = fileManager.enumerator(
                        at: sourcePath,
                        includingPropertiesForKeys: Array(resourceKeys),
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]
                    )
                else {
                    throw RuntimeComponentError.sourceIsNotFileOrDirectory(sourcePath)
                }
                for case let fileURL as URL in enumerator {
                    try Task.checkCancellation()
                    try addCandidate(
                        fileURL,
                        resourceKeys: resourceKeys,
                        to: &candidates
                    )
                }
            } else {
                try addCandidate(
                    sourcePath,
                    resourceKeys: resourceKeys,
                    to: &candidates
                )
            }
        }

        return candidates.mapValues { urls in
            urls.min { lhs, rhs in
                let lhsDepth = lhs.pathComponents.count
                let rhsDepth = rhs.pathComponents.count
                if lhsDepth == rhsDepth {
                    return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
                }
                return lhsDepth < rhsDepth
            }!
        }
    }

    private static func addCandidate(
        _ fileURL: URL,
        resourceKeys: Set<URLResourceKey>,
        to candidates: inout [RuntimePayloadFile: [URL]]
    ) throws {
        guard let payload = RuntimePayloadFile(rawValue: fileURL.lastPathComponent) else {
            return
        }
        let values = try fileURL.resourceValues(forKeys: resourceKeys)
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            return
        }
        candidates[payload, default: []].append(fileURL.standardizedFileURL)
    }

    private static func downloadUsingURLSession(_ url: URL) async throws -> RuntimeDownloadedFile {
        let (fileURL, response) = try await URLSession.shared.download(from: url)
        guard let response = response as? HTTPURLResponse else {
            throw RuntimeComponentError.invalidDownloadResponse(url)
        }
        return RuntimeDownloadedFile(fileURL: fileURL, statusCode: response.statusCode)
    }

    private static func extractUsingDitto(_ archiveURL: URL, _ destinationURL: URL) async throws {
        let result: SupervisedCommandResult
        do {
            result = try await SupervisedCommand.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
                arguments: ["-x", "-k", archiveURL.path, destinationURL.path],
                workingDirectoryURL: destinationURL,
                timeout: extractionTimeout
            )
        } catch SupervisedCommandError.timedOut {
            throw RuntimeComponentError.extractionTimedOut(archiveName: archiveURL.lastPathComponent)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RuntimeComponentError.extractionFailed(
                archiveName: archiveURL.lastPathComponent,
                status: -1,
                output: error.localizedDescription
            )
        }

        if let readError = result.outputReadError {
            throw RuntimeComponentError.extractionFailed(
                archiveName: archiveURL.lastPathComponent,
                status: result.status,
                output: "读取解压输出失败：\(readError)"
            )
        }
        guard result.status == 0 else {
            throw RuntimeComponentError.extractionFailed(
                archiveName: archiveURL.lastPathComponent,
                status: result.status,
                output: result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
}
