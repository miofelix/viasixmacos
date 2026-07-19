import Foundation

public struct PreferencesLoadResult: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case persisted
        case missing
        case recoveredCorruptFile(backupURL: URL)
    }

    public let preferences: UserPreferences
    public let source: Source

    public init(preferences: UserPreferences, source: Source) {
        self.preferences = preferences
        self.source = source
    }
}

public enum PreferencesStoreError: LocalizedError, Equatable, Sendable {
    case unreadableFile(URL, reason: String)
    case corruptFileBackupFailed(URL, reason: String)

    public var errorDescription: String? {
        switch self {
        case .unreadableFile(let url, let reason):
            "无法读取偏好文件 \(url.lastPathComponent)：\(reason)。原文件未被修改。"
        case .corruptFileBackupFailed(let url, let reason):
            "偏好文件 \(url.lastPathComponent) 无法解析，且创建备份失败：\(reason)。原文件未被修改。"
        }
    }
}

public actor PreferencesStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load(defaults: UserPreferences) throws -> PreferencesLoadResult {
        let fileManager = FileManager.default
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            if Self.isMissingFileError(error) {
                return PreferencesLoadResult(preferences: defaults, source: .missing)
            }
            throw PreferencesStoreError.unreadableFile(
                fileURL,
                reason: error.localizedDescription
            )
        }

        do {
            return PreferencesLoadResult(
                preferences: try decoder.decode(UserPreferences.self, from: data),
                source: .persisted
            )
        } catch {
            let backupURL: URL
            do {
                backupURL = try moveCorruptFile(using: fileManager)
            } catch {
                throw PreferencesStoreError.corruptFileBackupFailed(
                    fileURL,
                    reason: error.localizedDescription
                )
            }
            return PreferencesLoadResult(
                preferences: defaults,
                source: .recoveredCorruptFile(backupURL: backupURL)
            )
        }
    }

    private nonisolated static func isMissingFileError(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain,
            error.code == CocoaError.Code.fileReadNoSuchFile.rawValue
        {
            return true
        }
        if error.domain == NSPOSIXErrorDomain,
            error.code == POSIXError.Code.ENOENT.rawValue
        {
            return true
        }
        guard let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError else {
            return false
        }
        return isMissingFileError(underlyingError)
    }

    public func save(_ preferences: UserPreferences) throws {
        let data = try encoder.encode(preferences)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        try FilePermissions.restrictFile(fileURL)
    }

    private func moveCorruptFile(using fileManager: FileManager) throws -> URL {
        let directory = fileURL.deletingLastPathComponent()
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let pathExtension = fileURL.pathExtension

        while true {
            let extensionSuffix = pathExtension.isEmpty ? "" : ".\(pathExtension)"
            let backupURL = directory.appendingPathComponent(
                "\(baseName).corrupt-\(UUID().uuidString)\(extensionSuffix)"
            )
            guard !fileManager.fileExists(atPath: backupURL.path) else { continue }
            try fileManager.moveItem(at: fileURL, to: backupURL)
            return backupURL
        }
    }
}
