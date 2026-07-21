import Foundation

public struct PrivilegedRuntimeManifest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let expectedRuntimeVersion = "1.19.29"
    public static let expectedRelativePath =
        "Contents/Library/HelperTools/com.felix.viasix.mihomo"
    public static let expectedBundleIdentifier = "com.felix.viasix.mihomo"

    private static let maximumEncodedBytes = 64 * 1_024

    public let schemaVersion: Int
    public let runtimeVersion: String
    public let architecture: String
    public let relativePath: String
    public let bundleIdentifier: String
    public let sha256: String
    public let cdHash: String

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        runtimeVersion: String = Self.expectedRuntimeVersion,
        architecture: String = Self.currentArchitecture,
        relativePath: String = Self.expectedRelativePath,
        bundleIdentifier: String = Self.expectedBundleIdentifier,
        sha256: String,
        cdHash: String
    ) {
        self.schemaVersion = schemaVersion
        self.runtimeVersion = runtimeVersion
        self.architecture = architecture
        self.relativePath = relativePath
        self.bundleIdentifier = bundleIdentifier
        self.sha256 = sha256
        self.cdHash = cdHash
    }

    public init(data: Data, expectedArchitecture: String = Self.currentArchitecture) throws {
        guard data.count <= Self.maximumEncodedBytes else {
            throw PrivilegedRuntimeManifestError.manifestTooLarge(data.count)
        }
        do {
            self = try PropertyListDecoder().decode(Self.self, from: data)
        } catch {
            throw PrivilegedRuntimeManifestError.invalidPropertyList(error.localizedDescription)
        }
        try validate(expectedArchitecture: expectedArchitecture)
    }

    public func validate(expectedArchitecture: String = Self.currentArchitecture) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw PrivilegedRuntimeManifestError.unsupportedSchemaVersion(schemaVersion)
        }
        guard runtimeVersion == Self.expectedRuntimeVersion else {
            throw PrivilegedRuntimeManifestError.unexpectedRuntimeVersion(runtimeVersion)
        }
        guard architecture == expectedArchitecture else {
            throw PrivilegedRuntimeManifestError.unexpectedArchitecture(
                expected: expectedArchitecture,
                actual: architecture
            )
        }
        guard relativePath == Self.expectedRelativePath else {
            throw PrivilegedRuntimeManifestError.unexpectedRelativePath(relativePath)
        }
        guard bundleIdentifier == Self.expectedBundleIdentifier else {
            throw PrivilegedRuntimeManifestError.unexpectedBundleIdentifier(bundleIdentifier)
        }
        guard Self.isLowercaseHex(sha256, length: 64) else {
            throw PrivilegedRuntimeManifestError.invalidSHA256
        }
        guard Self.isLowercaseHex(cdHash, length: 40) else {
            throw PrivilegedRuntimeManifestError.invalidCDHash
        }
    }

    public static var currentArchitecture: String {
        #if arch(arm64)
            "arm64"
        #elseif arch(x86_64)
            "x86_64"
        #else
            #error("ViaSix privileged runtime supports only arm64 and x86_64")
        #endif
    }

    private static func isLowercaseHex(_ value: String, length: Int) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == length else { return false }
        return bytes.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "SchemaVersion"
        case runtimeVersion = "RuntimeVersion"
        case architecture = "Architecture"
        case relativePath = "RelativePath"
        case bundleIdentifier = "BundleIdentifier"
        case sha256 = "SHA256"
        case cdHash = "CDHash"
    }
}

public enum PrivilegedRuntimeManifestError: LocalizedError, Equatable, Sendable {
    case manifestTooLarge(Int)
    case invalidPropertyList(String)
    case unsupportedSchemaVersion(Int)
    case unexpectedRuntimeVersion(String)
    case unexpectedArchitecture(expected: String, actual: String)
    case unexpectedRelativePath(String)
    case unexpectedBundleIdentifier(String)
    case invalidSHA256
    case invalidCDHash

    public var errorDescription: String? {
        switch self {
        case .manifestTooLarge(let size):
            "特权运行组件清单过大：\(size) 字节"
        case .invalidPropertyList(let detail):
            "特权运行组件清单无效：\(detail)"
        case .unsupportedSchemaVersion(let version):
            "特权运行组件清单版本不受支持：\(version)"
        case .unexpectedRuntimeVersion(let version):
            "特权 Mihomo 版本不匹配：\(version)"
        case .unexpectedArchitecture(let expected, let actual):
            "特权 Mihomo 架构不匹配（需要 \(expected)，实际 \(actual)）"
        case .unexpectedRelativePath(let path):
            "特权 Mihomo 路径无效：\(path)"
        case .unexpectedBundleIdentifier(let identifier):
            "特权 Mihomo 签名标识无效：\(identifier)"
        case .invalidSHA256:
            "特权 Mihomo SHA-256 无效"
        case .invalidCDHash:
            "特权 Mihomo CDHash 无效"
        }
    }
}
