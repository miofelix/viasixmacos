import Foundation
import Security

public struct CodeSigningIdentity: Equatable, Sendable {
    public let identifier: String
    public let teamIdentifier: String?
    public let cdHash: String

    public init(identifier: String, teamIdentifier: String?, cdHash: String) {
        self.identifier = identifier
        self.teamIdentifier = teamIdentifier
        self.cdHash = cdHash
    }
}

public enum CodeSigningIdentityError: LocalizedError, Equatable, Sendable {
    case securityFailure(operation: String, status: OSStatus)
    case missingIdentifier
    case missingTeamIdentifier
    case missingCDHash
    case malformedCDHash(String)
    case unexpectedIdentifier(expected: String, actual: String)
    case invalidRequirementComponent(String)

    public var errorDescription: String? {
        switch self {
        case .securityFailure(let operation, let status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "读取代码签名失败（\(operation)）：\(detail)"
        case .missingIdentifier:
            return "当前程序缺少代码签名标识"
        case .missingTeamIdentifier:
            return "当前构建没有 Developer ID Team 标识"
        case .missingCDHash:
            return "当前程序缺少代码签名 CDHash"
        case .malformedCDHash(let value):
            return "代码签名 CDHash 无效：\(value)"
        case .unexpectedIdentifier(let expected, let actual):
            return "代码签名标识不匹配（需要 \(expected)，实际 \(actual)）"
        case .invalidRequirementComponent(let value):
            return "代码签名要求包含无效值：\(value)"
        }
    }
}

public enum CodeSigningInspector {
    public static func currentProcess(
        expectedIdentifier: String? = nil
    ) throws -> CodeSigningIdentity {
        var dynamicCode: SecCode?
        let copySelfStatus = SecCodeCopySelf([], &dynamicCode)
        guard copySelfStatus == errSecSuccess, let dynamicCode else {
            throw CodeSigningIdentityError.securityFailure(
                operation: "SecCodeCopySelf",
                status: copySelfStatus
            )
        }

        let validityStatus = SecCodeCheckValidity(dynamicCode, [], nil)
        guard validityStatus == errSecSuccess else {
            throw CodeSigningIdentityError.securityFailure(
                operation: "SecCodeCheckValidity",
                status: validityStatus
            )
        }

        var staticCode: SecStaticCode?
        let copyStaticStatus = SecCodeCopyStaticCode(dynamicCode, [], &staticCode)
        guard copyStaticStatus == errSecSuccess, let staticCode else {
            throw CodeSigningIdentityError.securityFailure(
                operation: "SecCodeCopyStaticCode",
                status: copyStaticStatus
            )
        }

        var signingInformation: CFDictionary?
        let informationStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        )
        guard informationStatus == errSecSuccess, let signingInformation else {
            throw CodeSigningIdentityError.securityFailure(
                operation: "SecCodeCopySigningInformation",
                status: informationStatus
            )
        }

        let values = signingInformation as NSDictionary
        guard let identifier = values[kSecCodeInfoIdentifier] as? String, !identifier.isEmpty else {
            throw CodeSigningIdentityError.missingIdentifier
        }
        let teamIdentifier = (values[kSecCodeInfoTeamIdentifier] as? String).flatMap {
            $0.isEmpty ? nil : $0
        }
        guard let cdHashData = values[kSecCodeInfoUnique] as? Data else {
            throw CodeSigningIdentityError.missingCDHash
        }
        let cdHash = hexString(cdHashData)
        try validateCDHash(cdHash)
        if let expectedIdentifier, identifier != expectedIdentifier {
            throw CodeSigningIdentityError.unexpectedIdentifier(
                expected: expectedIdentifier,
                actual: identifier
            )
        }
        return CodeSigningIdentity(
            identifier: identifier,
            teamIdentifier: teamIdentifier,
            cdHash: cdHash
        )
    }

    public static func staticCode(
        at url: URL,
        expectedIdentifier: String? = nil
    ) throws -> CodeSigningIdentity {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(
            url as CFURL,
            SecCSFlags(),
            &staticCode
        )
        guard createStatus == errSecSuccess, let staticCode else {
            throw CodeSigningIdentityError.securityFailure(
                operation: "SecStaticCodeCreateWithPath",
                status: createStatus
            )
        }
        let validityStatus = SecStaticCodeCheckValidity(
            staticCode,
            SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures),
            nil
        )
        guard validityStatus == errSecSuccess else {
            throw CodeSigningIdentityError.securityFailure(
                operation: "SecStaticCodeCheckValidity",
                status: validityStatus
            )
        }

        var signingInformation: CFDictionary?
        let informationStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        )
        guard informationStatus == errSecSuccess, let signingInformation else {
            throw CodeSigningIdentityError.securityFailure(
                operation: "SecCodeCopySigningInformation",
                status: informationStatus
            )
        }
        let values = signingInformation as NSDictionary
        guard let identifier = values[kSecCodeInfoIdentifier] as? String, !identifier.isEmpty else {
            throw CodeSigningIdentityError.missingIdentifier
        }
        if let expectedIdentifier, identifier != expectedIdentifier {
            throw CodeSigningIdentityError.unexpectedIdentifier(
                expected: expectedIdentifier,
                actual: identifier
            )
        }
        let teamIdentifier = (values[kSecCodeInfoTeamIdentifier] as? String).flatMap {
            $0.isEmpty ? nil : $0
        }
        guard let cdHashData = values[kSecCodeInfoUnique] as? Data else {
            throw CodeSigningIdentityError.missingCDHash
        }
        let cdHash = hexString(cdHashData)
        try validateCDHash(cdHash)
        return CodeSigningIdentity(
            identifier: identifier,
            teamIdentifier: teamIdentifier,
            cdHash: cdHash
        )
    }

    private static func validateCDHash(_ value: String) throws {
        guard value.utf8.count == 40,
            value.utf8.allSatisfy({ byte in
                (48...57).contains(byte) || (97...102).contains(byte)
            })
        else {
            throw CodeSigningIdentityError.malformedCDHash(value)
        }
    }

    private static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

public enum CodeSigningRequirementBuilder {
    public static func identifierRequirement(identifier: String) throws -> String {
        guard isValidBundleIdentifier(identifier) else {
            throw CodeSigningIdentityError.invalidRequirementComponent(identifier)
        }
        return "identifier \"\(identifier)\""
    }

    public static func sameTeamRequirement(
        identifier: String,
        teamIdentifier: String
    ) throws -> String {
        guard isValidBundleIdentifier(identifier) else {
            throw CodeSigningIdentityError.invalidRequirementComponent(identifier)
        }
        guard isValidTeamIdentifier(teamIdentifier) else {
            throw CodeSigningIdentityError.invalidRequirementComponent(teamIdentifier)
        }
        return
            "anchor apple generic and identifier \"\(identifier)\" "
            + "and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }

    public static func exactCDHashRequirement(
        identifier: String,
        cdHash: String
    ) throws -> String {
        guard isValidBundleIdentifier(identifier) else {
            throw CodeSigningIdentityError.invalidRequirementComponent(identifier)
        }
        guard isValidCDHash(cdHash) else {
            throw CodeSigningIdentityError.invalidRequirementComponent(cdHash)
        }
        return "identifier \"\(identifier)\" and cdhash H\"\(cdHash)\""
    }

    private static func isValidBundleIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.first != ".", value.last != "." else { return false }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "-"
        }
    }

    private static func isValidTeamIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.uppercaseLetters.contains($0)
                || CharacterSet.decimalDigits.contains($0)
        }
    }

    private static func isValidCDHash(_ value: String) -> Bool {
        value.utf8.count == 40
            && value.utf8.allSatisfy { byte in
                (48...57).contains(byte) || (97...102).contains(byte)
            }
    }
}
