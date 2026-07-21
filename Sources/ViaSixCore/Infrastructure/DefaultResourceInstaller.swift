import CryptoKit
import Foundation

public enum DefaultResourceInstaller {
    struct LegacyResourceDigests: Equatable, Sendable {
        let ipv4: String
        let localProxy: String

        fileprivate static let shipped = Self(
            ipv4: "449ea35cc7c80700cf647d39f5061545758bc7564eeeb5e7caa3cbba933f7da4",
            localProxy: "466d1b4d16bc88c8e9286587269c9db8daa437a12fd896a085562cda15b6972e"
        )
    }

    public static func install(into paths: AppPaths, using fileManager: FileManager = .default) throws {
        try install(into: paths, legacyDigests: .shipped, using: fileManager)
    }

    static func install(
        into paths: AppPaths,
        legacyDigests: LegacyResourceDigests,
        using fileManager: FileManager = .default
    ) throws {
        try paths.prepare(using: fileManager)
        try installBundledResource(
            resource: "ip",
            extension: "txt",
            to: paths.ipv4List,
            legacySHA256: legacyDigests.ipv4,
            using: fileManager
        )
        try copyIfMissing(resource: "ipv6", extension: "txt", to: paths.ipv6List, using: fileManager)
        try installBundledResource(
            resource: "local-proxy",
            extension: "json",
            to: paths.localProxyConfig,
            legacySHA256: legacyDigests.localProxy,
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

        // Derived files are safe to regenerate. Removing them first keeps the
        // migration retryable if replacing the source resource later fails.
        for fileURL in removingDerivedFiles where fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        try replacement.write(to: destination, options: .atomic)
        try FilePermissions.restrictFile(destination, using: fileManager)
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
        try FilePermissions.restrictFile(destination, using: fileManager)
    }

    private static func resourceURL(named resource: String, extension: String) -> URL? {
        if let packaged = Bundle.main.url(forResource: resource, withExtension: `extension`) {
            return packaged
        }

        #if VIASIX_PACKAGED_APP
            return nil
        #else
            return Bundle.module.url(forResource: resource, withExtension: `extension`)
        #endif
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
