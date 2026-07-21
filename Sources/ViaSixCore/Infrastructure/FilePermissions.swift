import Foundation

enum FilePermissions {
    static func restrictDirectory(_ url: URL, using fileManager: FileManager = .default) throws {
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    static func restrictFile(_ url: URL, using fileManager: FileManager = .default) throws {
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
