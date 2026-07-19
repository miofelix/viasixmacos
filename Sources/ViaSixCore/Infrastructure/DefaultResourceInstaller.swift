import CryptoKit
import Foundation

public enum DefaultResourceInstaller {
    static let legacyIPv4SHA256 = "449ea35cc7c80700cf647d39f5061545758bc7564eeeb5e7caa3cbba933f7da4"
    static let legacyTemplateSHA256 = "0641c1251d6f0521a5d56fbe8438fef3b297aace27a9e321ad33ea5b8d04812a"

    public static func install(into paths: AppPaths, using fileManager: FileManager = .default) throws {
        try paths.prepare(using: fileManager)
        try installBundledResource(
            resource: "ip",
            extension: "txt",
            to: paths.ipv4List,
            legacySHA256: legacyIPv4SHA256,
            using: fileManager
        )
        try copyIfMissing(resource: "ipv6", extension: "txt", to: paths.ipv6List, using: fileManager)
        try installBundledResource(
            resource: "template",
            extension: "json",
            to: paths.templateConfig,
            legacySHA256: legacyTemplateSHA256,
            removingDerivedFiles: [paths.generatedConfig],
            using: fileManager
        )
    }

    private static func installBundledResource(
        resource: String,
        extension: String,
        to destination: URL,
        legacySHA256: String,
        removingDerivedFiles: [URL] = [],
        using fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: destination.path) else {
            try copyIfMissing(resource: resource, extension: `extension`, to: destination, using: fileManager)
            return
        }
        guard let source = resourceURL(named: resource, extension: `extension`) else {
            throw ResourceError.missing(resource + "." + `extension`)
        }
        try replaceIfMatchingLegacy(
            at: destination,
            expectedSHA256: legacySHA256,
            replacement: Data(contentsOf: source),
            removingDerivedFiles: removingDerivedFiles,
            using: fileManager
        )
    }

    @discardableResult
    static func replaceIfMatchingLegacy(
        at destination: URL,
        expectedSHA256: String,
        replacement: Data,
        removingDerivedFiles: [URL] = [],
        using fileManager: FileManager = .default
    ) throws -> Bool {
        let installedData = try Data(contentsOf: destination)
        guard sha256(installedData) == expectedSHA256.lowercased() else { return false }
        try replacement.write(to: destination, options: .atomic)
        for fileURL in removingDerivedFiles where fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        return true
    }

    private static func copyIfMissing(
        resource: String,
        extension: String,
        to destination: URL,
        using fileManager: FileManager
    ) throws {
        guard !fileManager.fileExists(atPath: destination.path) else { return }
        guard let source = resourceURL(named: resource, extension: `extension`) else {
            throw ResourceError.missing(resource + "." + `extension`)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    private static func resourceURL(named resource: String, extension: String) -> URL? {
        if let packaged = Bundle.main.url(forResource: resource, withExtension: `extension`) {
            return packaged
        }
        return Bundle.module.url(forResource: resource, withExtension: `extension`)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public enum ResourceError: LocalizedError, Equatable, Sendable {
    case missing(String)

    public var errorDescription: String? {
        switch self {
        case .missing(let name): "缺少内置资源：\(name)"
        }
    }
}
