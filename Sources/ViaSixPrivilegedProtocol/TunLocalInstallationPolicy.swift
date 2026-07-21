import Foundation

public struct TunLocalInstallationPolicy: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let appIdentifier: String
    public let appCDHash: String
    public let helperIdentifier: String
    public let helperCDHash: String
    public let authorizedUserIdentifier: UInt32

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        appIdentifier: String,
        appCDHash: String,
        helperIdentifier: String,
        helperCDHash: String,
        authorizedUserIdentifier: UInt32
    ) throws {
        self.schemaVersion = schemaVersion
        self.appIdentifier = appIdentifier
        self.appCDHash = appCDHash
        self.helperIdentifier = helperIdentifier
        self.helperCDHash = helperCDHash
        self.authorizedUserIdentifier = authorizedUserIdentifier
        try validate()
    }

    public init(data: Data) throws {
        self = try PropertyListDecoder().decode(Self.self, from: data)
        try validate()
    }

    public init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    public func encodedPropertyList() throws -> Data {
        try validate()
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        return try encoder.encode(self)
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw TunLocalInstallationPolicyError.unsupportedSchemaVersion(schemaVersion)
        }
        guard appIdentifier == TunHelperConstants.appBundleIdentifier else {
            throw TunLocalInstallationPolicyError.unexpectedIdentifier(
                expected: TunHelperConstants.appBundleIdentifier,
                actual: appIdentifier
            )
        }
        guard helperIdentifier == TunHelperConstants.helperBundleIdentifier else {
            throw TunLocalInstallationPolicyError.unexpectedIdentifier(
                expected: TunHelperConstants.helperBundleIdentifier,
                actual: helperIdentifier
            )
        }
        guard Self.isValidCDHash(appCDHash) else {
            throw TunLocalInstallationPolicyError.invalidCDHash(appCDHash)
        }
        guard Self.isValidCDHash(helperCDHash) else {
            throw TunLocalInstallationPolicyError.invalidCDHash(helperCDHash)
        }
        guard authorizedUserIdentifier > 0 else {
            throw TunLocalInstallationPolicyError.invalidUserIdentifier(
                authorizedUserIdentifier
            )
        }
    }

    private static func isValidCDHash(_ value: String) -> Bool {
        value.utf8.count == 40
            && value.utf8.allSatisfy { byte in
                (48...57).contains(byte) || (97...102).contains(byte)
            }
    }
}

public enum TunLocalInstallationPolicyError: LocalizedError, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case unexpectedIdentifier(expected: String, actual: String)
    case invalidCDHash(String)
    case invalidUserIdentifier(UInt32)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "本地 TUN 安装策略版本不受支持：\(version)"
        case .unexpectedIdentifier(let expected, let actual):
            "本地 TUN 安装策略标识不匹配（需要 \(expected)，实际 \(actual)）"
        case .invalidCDHash(let value):
            "本地 TUN 安装策略 CDHash 无效：\(value)"
        case .invalidUserIdentifier(let value):
            "本地 TUN 安装策略用户标识无效：\(value)"
        }
    }
}
