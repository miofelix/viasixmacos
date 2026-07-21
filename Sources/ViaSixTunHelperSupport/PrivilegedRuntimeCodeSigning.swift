import Foundation
import Security
import ViaSixPrivilegedProtocol

struct PrivilegedRuntimeCodeIdentity: Equatable, Sendable {
    let identifier: String
    let teamIdentifier: String?
    let cdHash: String
}

protocol PrivilegedRuntimeCodeSigningVerifying: Sendable {
    func verifyCurrentHelper(
        expectedIdentifier: String
    ) throws -> PrivilegedRuntimeCodeIdentity

    func verifyStaticCode(
        at url: URL,
        expectedIdentifier: String,
        expectedTeamIdentifier: String?
    ) throws -> PrivilegedRuntimeCodeIdentity
}

enum PrivilegedRuntimeCodeSigningError: LocalizedError, Equatable, Sendable {
    case securityFailure(operation: String, status: OSStatus)
    case missingIdentifier(String)
    case missingCDHash(String)
    case malformedCDHash(String)
    case unexpectedIdentifier(expected: String, actual: String)
    case unexpectedTeamIdentifier(expected: String?, actual: String?)

    var errorDescription: String? {
        switch self {
        case .securityFailure(let operation, let status):
            let detail =
                SecCopyErrorMessageString(status, nil) as String?
                ?? "OSStatus \(status)"
            return "特权运行组件签名校验失败（\(operation)）：\(detail)"
        case .missingIdentifier(let path):
            return "特权运行组件缺少签名标识：\(path)"
        case .missingCDHash(let path):
            return "特权运行组件缺少 CDHash：\(path)"
        case .malformedCDHash(let path):
            return "特权运行组件 CDHash 无效：\(path)"
        case .unexpectedIdentifier(let expected, let actual):
            return "特权运行组件签名标识不匹配（需要 \(expected)，实际 \(actual)）"
        case .unexpectedTeamIdentifier(let expected, let actual):
            return
                "特权运行组件 Team ID 不匹配（需要 \(expected ?? "not set")，实际 \(actual ?? "not set")）"
        }
    }
}

struct SecurityPrivilegedRuntimeCodeSigningVerifier:
    PrivilegedRuntimeCodeSigningVerifying
{
    static func currentProcessCodeURL() throws -> URL {
        var dynamicCode: SecCode?
        let copyStatus = SecCodeCopySelf([], &dynamicCode)
        guard copyStatus == errSecSuccess, let dynamicCode else {
            throw PrivilegedRuntimeCodeSigningError.securityFailure(
                operation: "SecCodeCopySelf(path)",
                status: copyStatus
            )
        }
        var staticCode: SecStaticCode?
        let staticStatus = SecCodeCopyStaticCode(dynamicCode, [], &staticCode)
        guard staticStatus == errSecSuccess, let staticCode else {
            throw PrivilegedRuntimeCodeSigningError.securityFailure(
                operation: "SecCodeCopyStaticCode(path)",
                status: staticStatus
            )
        }
        var codeURL: CFURL?
        let pathStatus = SecCodeCopyPath(staticCode, [], &codeURL)
        guard pathStatus == errSecSuccess, let codeURL else {
            throw PrivilegedRuntimeCodeSigningError.securityFailure(
                operation: "SecCodeCopyPath",
                status: pathStatus
            )
        }
        return codeURL as URL
    }

    func verifyCurrentHelper(
        expectedIdentifier: String
    ) throws -> PrivilegedRuntimeCodeIdentity {
        var dynamicCode: SecCode?
        let copyStatus = SecCodeCopySelf([], &dynamicCode)
        guard copyStatus == errSecSuccess, let dynamicCode else {
            throw securityError("SecCodeCopySelf", status: copyStatus)
        }

        var staticCode: SecStaticCode?
        let staticStatus = SecCodeCopyStaticCode(dynamicCode, [], &staticCode)
        guard staticStatus == errSecSuccess, let staticCode else {
            throw securityError("SecCodeCopyStaticCode", status: staticStatus)
        }
        let unverifiedIdentity = try signingIdentity(
            for: staticCode,
            displayPath: "当前 helper"
        )
        try validateExpectedIdentity(
            unverifiedIdentity,
            expectedIdentifier: expectedIdentifier,
            expectedTeamIdentifier: unverifiedIdentity.teamIdentifier
        )
        let requirement = try makeRequirement(
            identifier: expectedIdentifier,
            teamIdentifier: unverifiedIdentity.teamIdentifier,
            cdHash: unverifiedIdentity.cdHash
        )
        let validityStatus = SecCodeCheckValidity(
            dynamicCode,
            SecCSFlags(rawValue: kSecCSStrictValidate),
            requirement
        )
        guard validityStatus == errSecSuccess else {
            throw securityError("SecCodeCheckValidity(helper)", status: validityStatus)
        }
        return unverifiedIdentity
    }

    func verifyStaticCode(
        at url: URL,
        expectedIdentifier: String,
        expectedTeamIdentifier: String?
    ) throws -> PrivilegedRuntimeCodeIdentity {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(
            url as CFURL,
            SecCSFlags(),
            &staticCode
        )
        guard createStatus == errSecSuccess, let staticCode else {
            throw securityError("SecStaticCodeCreateWithPath", status: createStatus)
        }

        let requirement = try makeRequirement(
            identifier: expectedIdentifier,
            teamIdentifier: expectedTeamIdentifier,
            cdHash: nil
        )
        let validityStatus = SecStaticCodeCheckValidity(
            staticCode,
            SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures),
            requirement
        )
        guard validityStatus == errSecSuccess else {
            throw securityError("SecStaticCodeCheckValidity", status: validityStatus)
        }

        let identity = try signingIdentity(
            for: staticCode,
            displayPath: url.path
        )
        try validateExpectedIdentity(
            identity,
            expectedIdentifier: expectedIdentifier,
            expectedTeamIdentifier: expectedTeamIdentifier
        )
        return identity
    }

    private func makeRequirement(
        identifier: String,
        teamIdentifier: String?,
        cdHash: String?
    ) throws -> SecRequirement {
        let requirementText: String
        if let teamIdentifier {
            requirementText = try CodeSigningRequirementBuilder.sameTeamRequirement(
                identifier: identifier,
                teamIdentifier: teamIdentifier
            )
        } else if let cdHash {
            requirementText = try CodeSigningRequirementBuilder.exactCDHashRequirement(
                identifier: identifier,
                cdHash: cdHash
            )
        } else {
            requirementText = try CodeSigningRequirementBuilder.identifierRequirement(
                identifier: identifier
            )
        }
        var requirement: SecRequirement?
        let status = SecRequirementCreateWithString(
            requirementText as CFString,
            SecCSFlags(),
            &requirement
        )
        guard status == errSecSuccess, let requirement else {
            throw securityError("SecRequirementCreateWithString", status: status)
        }
        return requirement
    }

    private func signingIdentity(
        for code: SecStaticCode,
        displayPath: String
    ) throws -> PrivilegedRuntimeCodeIdentity {
        var signingInformation: CFDictionary?
        let status = SecCodeCopySigningInformation(
            code,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        )
        guard status == errSecSuccess, let signingInformation else {
            throw securityError("SecCodeCopySigningInformation", status: status)
        }

        let values = signingInformation as NSDictionary
        guard let identifier = values[kSecCodeInfoIdentifier] as? String, !identifier.isEmpty else {
            throw PrivilegedRuntimeCodeSigningError.missingIdentifier(displayPath)
        }
        let teamIdentifier = (values[kSecCodeInfoTeamIdentifier] as? String).flatMap {
            $0.isEmpty ? nil : $0
        }
        guard let cdHashData = values[kSecCodeInfoUnique] as? Data else {
            throw PrivilegedRuntimeCodeSigningError.missingCDHash(displayPath)
        }
        let cdHash = Self.hexString(cdHashData)
        guard cdHash.utf8.count == 40 else {
            throw PrivilegedRuntimeCodeSigningError.malformedCDHash(displayPath)
        }
        return PrivilegedRuntimeCodeIdentity(
            identifier: identifier,
            teamIdentifier: teamIdentifier,
            cdHash: cdHash
        )
    }

    private func validateExpectedIdentity(
        _ identity: PrivilegedRuntimeCodeIdentity,
        expectedIdentifier: String,
        expectedTeamIdentifier: String?
    ) throws {
        guard identity.identifier == expectedIdentifier else {
            throw PrivilegedRuntimeCodeSigningError.unexpectedIdentifier(
                expected: expectedIdentifier,
                actual: identity.identifier
            )
        }
        guard identity.teamIdentifier == expectedTeamIdentifier else {
            throw PrivilegedRuntimeCodeSigningError.unexpectedTeamIdentifier(
                expected: expectedTeamIdentifier,
                actual: identity.teamIdentifier
            )
        }
    }

    private func securityError(
        _ operation: String,
        status: OSStatus
    ) -> PrivilegedRuntimeCodeSigningError {
        .securityFailure(operation: operation, status: status)
    }

    private static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
