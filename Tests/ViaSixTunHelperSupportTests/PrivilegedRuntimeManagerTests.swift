import CryptoKit
import Darwin
import Foundation
import XCTest

@testable import ViaSixTunHelperSupport

final class PrivilegedRuntimeManagerTests: XCTestCase {
    func testInstallsAndRevalidatesFixedRuntimeWithPrivateMetadata() throws {
        try withFixture { fixture in
            let expectedData = Data("signed-mihomo-v1".utf8)
            try fixture.updateBundledRuntime(expectedData)

            let installed = try fixture.manager().installBundledRuntime()

            XCTAssertEqual(installed.executableURL, fixture.installedRuntimeURL)
            XCTAssertEqual(try Data(contentsOf: installed.executableURL), expectedData)
            try assertMetadata(
                at: fixture.containerURL,
                type: S_IFDIR,
                mode: 0o700,
                owner: UInt32(geteuid()),
                group: UInt32(getegid())
            )
            try assertMetadata(
                at: fixture.runtimeDirectoryURL,
                type: S_IFDIR,
                mode: 0o700,
                owner: UInt32(geteuid()),
                group: UInt32(getegid())
            )
            try assertMetadata(
                at: fixture.installedRuntimeURL,
                type: S_IFREG,
                mode: 0o755,
                owner: UInt32(geteuid()),
                group: UInt32(getegid()),
                linkCount: 1
            )
            try assertMetadata(
                at: fixture.installedManifestURL,
                type: S_IFREG,
                mode: 0o600,
                owner: UInt32(geteuid()),
                group: UInt32(getegid()),
                linkCount: 1
            )

            XCTAssertEqual(try fixture.manager().verifiedInstalledRuntime(), installed)
            XCTAssertEqual(
                try fixture.manager().withVerifiedInstalledRuntime { $0 },
                installed
            )
        }
    }

    func testVerificationRejectsInstalledSymbolicLink() throws {
        try withFixture { fixture in
            try fixture.updateBundledRuntime(Data("signed-mihomo".utf8))
            try fixture.manager().installBundledRuntime()
            try FileManager.default.removeItem(at: fixture.installedRuntimeURL)
            try FileManager.default.createSymbolicLink(
                at: fixture.installedRuntimeURL,
                withDestinationURL: fixture.bundledRuntimeURL
            )

            XCTAssertThrowsError(try fixture.manager().verifiedInstalledRuntime()) { error in
                guard
                    case .posix(let operation, let code) =
                        error as? PrivilegedRuntimeManagerError
                else {
                    return XCTFail("Unexpected error: \(error)")
                }
                XCTAssertEqual(operation, "openat(installed Mihomo)")
                XCTAssertEqual(code, ELOOP)
            }
        }
    }

    func testVerificationRejectsDigestTampering() throws {
        try withFixture { fixture in
            try fixture.updateBundledRuntime(Data("signed-mihomo".utf8))
            try fixture.manager().installBundledRuntime()
            let handle = try FileHandle(forWritingTo: fixture.installedRuntimeURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("tamper".utf8))
            try handle.close()

            XCTAssertThrowsError(try fixture.manager().verifiedInstalledRuntime()) { error in
                guard case .digestMismatch = error as? PrivilegedRuntimeManagerError else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }

    func testVerificationRejectsWrongPermissionsOwnershipAndHardLinks() throws {
        try withFixture { fixture in
            try fixture.updateBundledRuntime(Data("signed-mihomo".utf8))
            try fixture.manager().installBundledRuntime()

            XCTAssertEqual(chmod(fixture.installedManifestURL.path, mode_t(0o644)), 0)
            XCTAssertThrowsError(try fixture.manager().verifiedInstalledRuntime()) { error in
                guard case .insecurePermissions = error as? PrivilegedRuntimeManagerError else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
            XCTAssertEqual(chmod(fixture.installedManifestURL.path, mode_t(0o600)), 0)

            let hardLink = fixture.rootURL.appendingPathComponent("mihomo-hardlink")
            try FileManager.default.linkItem(
                at: fixture.installedRuntimeURL,
                to: hardLink
            )
            XCTAssertThrowsError(try fixture.manager().verifiedInstalledRuntime()) { error in
                guard
                    case .invalidFile(_, let reason) =
                        error as? PrivilegedRuntimeManagerError
                else {
                    return XCTFail("Unexpected error: \(error)")
                }
                XCTAssertEqual(reason, "硬链接数无效")
            }
            try FileManager.default.removeItem(at: hardLink)

            let wrongOwnerManager = fixture.manager(
                expectedOwnerUserIdentifier: UInt32(geteuid()) &+ 1
            )
            XCTAssertThrowsError(try wrongOwnerManager.verifiedInstalledRuntime()) { error in
                guard case .insecureOwnership = error as? PrivilegedRuntimeManagerError else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }

    func testAtomicReplacementLeavesOnlyNewCompleteVersion() throws {
        try withFixture { fixture in
            try fixture.updateBundledRuntime(Data("signed-mihomo-v1".utf8))
            try fixture.manager().installBundledRuntime()
            let newData = Data("signed-mihomo-v2".utf8)
            try fixture.updateBundledRuntime(newData)

            let installed = try fixture.manager().installBundledRuntime()

            XCTAssertEqual(try Data(contentsOf: installed.executableURL), newData)
            XCTAssertEqual(try fixture.manager().verifiedInstalledRuntime(), installed)
            XCTAssertFalse(
                try FileManager.default.contentsOfDirectory(atPath: fixture.containerURL.path)
                    .contains { $0.hasPrefix(".Runtime.") }
            )
        }
    }

    func testPostReplacementFailureRollsBackOldVersion() throws {
        enum InjectedFailure: Error { case failed }

        try withFixture { fixture in
            let oldData = Data("signed-mihomo-v1".utf8)
            try fixture.updateBundledRuntime(oldData)
            try fixture.manager().installBundledRuntime()
            try fixture.updateBundledRuntime(Data("signed-mihomo-v2".utf8))
            let failingManager = fixture.manager(
                hooks: PrivilegedRuntimeInstallationHooks(
                    afterAtomicReplacement: { throw InjectedFailure.failed }
                )
            )

            XCTAssertThrowsError(try failingManager.installBundledRuntime())
            XCTAssertEqual(try Data(contentsOf: fixture.installedRuntimeURL), oldData)
            XCTAssertFalse(
                try FileManager.default.contentsOfDirectory(atPath: fixture.containerURL.path)
                    .contains { $0.hasPrefix(".Runtime.") }
            )

            try fixture.updateBundledRuntime(oldData)
            XCTAssertNoThrow(try fixture.manager().verifiedInstalledRuntime())
        }
    }

    func testInstallRepairsContentCorruptionWhenExistingMetadataIsSafe() throws {
        try withFixture { fixture in
            try fixture.updateBundledRuntime(Data("signed-mihomo-v1".utf8))
            try fixture.manager().installBundledRuntime()
            let handle = try FileHandle(forWritingTo: fixture.installedRuntimeURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("corrupt".utf8))
            try handle.close()
            let repairedData = Data("signed-mihomo-v2".utf8)
            try fixture.updateBundledRuntime(repairedData)

            let repaired = try fixture.manager().installBundledRuntime()

            XCTAssertEqual(try Data(contentsOf: repaired.executableURL), repairedData)
            XCTAssertEqual(try fixture.manager().verifiedInstalledRuntime(), repaired)
        }
    }

    func testRejectsInvalidHelperLayoutInstalledManifestMismatchAndTeamMismatch() throws {
        try withFixture { fixture in
            try fixture.updateBundledRuntime(Data("signed-mihomo".utf8))
            let invalidLayoutManager = fixture.manager(
                helperExecutableURL: fixture.rootURL.appendingPathComponent("helper")
            )
            XCTAssertThrowsError(try invalidLayoutManager.installBundledRuntime()) { error in
                guard case .invalidHelperLocation = error as? PrivilegedRuntimeManagerError else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }

            try fixture.manager().installBundledRuntime()
            let mismatchedManifest = PrivilegedRuntimeManifest(
                sha256: String(repeating: "c", count: 64),
                cdHash: String(repeating: "d", count: 40)
            )
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            try encoder.encode(mismatchedManifest).write(
                to: fixture.installedManifestURL,
                options: .atomic
            )
            XCTAssertEqual(chmod(fixture.installedManifestURL.path, mode_t(0o600)), 0)
            XCTAssertThrowsError(try fixture.manager().verifiedInstalledRuntime()) { error in
                XCTAssertEqual(
                    error as? PrivilegedRuntimeManagerError,
                    .installedManifestMismatch
                )
            }

            try fixture.updateBundledRuntime(Data("signed-mihomo-v2".utf8))
            fixture.signer.forceTeamMismatch(
                for: PrivilegedRuntimeManifest.expectedBundleIdentifier
            )
            XCTAssertThrowsError(try fixture.manager().installBundledRuntime()) { error in
                guard
                    case .unexpectedTeamIdentifier =
                        error as? PrivilegedRuntimeCodeSigningError
                else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }

    func testSourceSymlinkAndHardLinkAreRejectedBeforeInstallation() throws {
        try withFixture { fixture in
            let data = Data("signed-mihomo".utf8)
            try fixture.updateBundledRuntime(data)
            let outside = fixture.rootURL.appendingPathComponent("outside-mihomo")
            try data.write(to: outside)
            XCTAssertEqual(chmod(outside.path, mode_t(0o755)), 0)

            try FileManager.default.removeItem(at: fixture.bundledRuntimeURL)
            try FileManager.default.createSymbolicLink(
                at: fixture.bundledRuntimeURL,
                withDestinationURL: outside
            )
            XCTAssertThrowsError(try fixture.manager().installBundledRuntime())

            try FileManager.default.removeItem(at: fixture.bundledRuntimeURL)
            try FileManager.default.linkItem(at: outside, to: fixture.bundledRuntimeURL)
            XCTAssertThrowsError(try fixture.manager().installBundledRuntime()) { error in
                guard
                    case .invalidFile(_, let reason) =
                        error as? PrivilegedRuntimeManagerError
                else {
                    return XCTFail("Unexpected error: \(error)")
                }
                XCTAssertEqual(reason, "硬链接数无效")
            }
        }
    }

    func testRejectsSymbolicLinkInSourceAppPath() throws {
        try withFixture { fixture in
            try fixture.updateBundledRuntime(Data("signed-mihomo".utf8))
            let linkedApp = fixture.rootURL.appendingPathComponent(
                "Linked.app",
                isDirectory: true
            )
            try FileManager.default.createSymbolicLink(
                at: linkedApp,
                withDestinationURL: fixture.appURL
            )
            let linkedHelper = linkedApp.appendingPathComponent(
                "Contents/Library/HelperTools/com.felix.viasix.tun-helper"
            )

            XCTAssertThrowsError(
                try fixture.manager(helperExecutableURL: linkedHelper).installBundledRuntime()
            )
        }
    }

    func testSecureLegacyContainerGroupIsNormalized() throws {
        try withFixture { fixture in
            try fixture.updateBundledRuntime(Data("signed-mihomo".utf8))
            try fixture.manager().installBundledRuntime()
            guard let legacyGroup = supplementaryGroupDifferentFromEffectiveGroup() else {
                throw XCTSkip("No alternate supplementary group is available")
            }
            guard chown(fixture.containerURL.path, uid_t.max, legacyGroup) == 0 else {
                throw XCTSkip("Cannot assign the simulated legacy group")
            }

            XCTAssertNoThrow(try fixture.manager().verifiedInstalledRuntime())
            var metadata = stat()
            XCTAssertEqual(lstat(fixture.containerURL.path, &metadata), 0)
            XCTAssertEqual(metadata.st_gid, getegid())
        }
    }

    private func withFixture(_ body: (RuntimeFixture) throws -> Void) throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        try body(fixture)
    }

    private func assertMetadata(
        at url: URL,
        type: mode_t,
        mode: mode_t,
        owner: UInt32,
        group: UInt32,
        linkCount: UInt16? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        var metadata = stat()
        XCTAssertEqual(lstat(url.path, &metadata), 0, file: file, line: line)
        XCTAssertEqual(metadata.st_mode & S_IFMT, type, file: file, line: line)
        XCTAssertEqual(metadata.st_mode & 0o7777, mode, file: file, line: line)
        XCTAssertEqual(metadata.st_uid, owner, file: file, line: line)
        XCTAssertEqual(metadata.st_gid, group, file: file, line: line)
        if let linkCount {
            XCTAssertEqual(metadata.st_nlink, linkCount, file: file, line: line)
        }
    }

    private func supplementaryGroupDifferentFromEffectiveGroup() -> gid_t? {
        var groups = [gid_t](repeating: 0, count: Int(NGROUPS_MAX))
        let count = getgroups(Int32(groups.count), &groups)
        guard count > 0 else { return nil }
        return groups.prefix(Int(count)).first { $0 != getegid() }
    }
}

private final class RuntimeFixture {
    let rootURL: URL
    let appURL: URL
    let helperURL: URL
    let bundledRuntimeURL: URL
    let bundledManifestURL: URL
    let containerURL: URL
    let signer = FakeRuntimeCodeSigningVerifier()

    var runtimeDirectoryURL: URL {
        containerURL.appendingPathComponent("Runtime", isDirectory: true)
    }

    var installedRuntimeURL: URL {
        runtimeDirectoryURL.appendingPathComponent("mihomo")
    }

    var installedManifestURL: URL {
        runtimeDirectoryURL.appendingPathComponent("PrivilegedRuntime.plist")
    }

    init() throws {
        let temporaryPath = FileManager.default.temporaryDirectory.path
        let resolvedTemporaryPath =
            temporaryPath.hasPrefix("/var/")
            ? "/private\(temporaryPath)"
            : temporaryPath
        let temporaryRoot = URL(
            fileURLWithPath: resolvedTemporaryPath,
            isDirectory: true
        )
        rootURL = temporaryRoot.appendingPathComponent(
            "ViaSix-PrivilegedRuntime-\(UUID().uuidString)",
            isDirectory: true
        )
        appURL = rootURL.appendingPathComponent("ViaSix.app", isDirectory: true)
        helperURL = appURL.appendingPathComponent(
            "Contents/Library/HelperTools/com.felix.viasix.tun-helper"
        )
        bundledRuntimeURL = appURL.appendingPathComponent(
            PrivilegedRuntimeManifest.expectedRelativePath
        )
        bundledManifestURL = appURL.appendingPathComponent(
            "Contents/Resources/PrivilegedRuntime.plist"
        )
        containerURL = rootURL.appendingPathComponent("SystemState", isDirectory: true)

        try FileManager.default.createDirectory(
            at: helperURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: bundledManifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("signed-helper".utf8).write(to: helperURL)
        guard chmod(helperURL.path, mode_t(0o755)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    func updateBundledRuntime(_ data: Data) throws {
        try data.write(to: bundledRuntimeURL, options: .atomic)
        guard chmod(bundledRuntimeURL.path, mode_t(0o755)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let digest = Self.sha256(data)
        let cdHash = String(digest.prefix(40))
        signer.registerRuntime(digest: digest, cdHash: cdHash)
        let manifest = PrivilegedRuntimeManifest(
            sha256: digest,
            cdHash: cdHash
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try encoder.encode(manifest).write(to: bundledManifestURL, options: .atomic)
        guard chmod(bundledManifestURL.path, mode_t(0o644)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    func manager(
        expectedOwnerUserIdentifier: UInt32 = UInt32(geteuid()),
        helperExecutableURL: URL? = nil,
        hooks: PrivilegedRuntimeInstallationHooks = PrivilegedRuntimeInstallationHooks()
    ) -> PrivilegedRuntimeManager {
        let resolvedHelperURL = helperExecutableURL ?? helperURL
        return PrivilegedRuntimeManager(
            helperExecutableURLProvider: { resolvedHelperURL },
            containerDirectoryURL: containerURL,
            expectedOwnerUserIdentifier: expectedOwnerUserIdentifier,
            expectedOwnerGroupIdentifier: UInt32(getegid()),
            codeSigningVerifier: signer,
            hooks: hooks
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private final class FakeRuntimeCodeSigningVerifier:
    @unchecked Sendable,
    PrivilegedRuntimeCodeSigningVerifying
{
    private let lock = NSLock()
    private var runtimeCDHashes: [String: String] = [:]
    private var teamMismatchIdentifier: String?
    private let teamIdentifier = "A1B2C3D4E5"
    private let helperCDHash = String(repeating: "a", count: 40)

    func registerRuntime(digest: String, cdHash: String) {
        lock.withLock {
            runtimeCDHashes[digest] = cdHash
        }
    }

    func forceTeamMismatch(for identifier: String) {
        lock.withLock {
            teamMismatchIdentifier = identifier
        }
    }

    func verifyCurrentHelper(
        expectedIdentifier: String
    ) throws -> PrivilegedRuntimeCodeIdentity {
        PrivilegedRuntimeCodeIdentity(
            identifier: expectedIdentifier,
            teamIdentifier: teamIdentifier,
            cdHash: helperCDHash
        )
    }

    func verifyStaticCode(
        at url: URL,
        expectedIdentifier: String,
        expectedTeamIdentifier: String
    ) throws -> PrivilegedRuntimeCodeIdentity {
        let cdHash: String
        switch expectedIdentifier {
        case "com.felix.viasix.tun-helper":
            cdHash = helperCDHash
        case PrivilegedRuntimeManifest.expectedBundleIdentifier:
            let data = try Data(contentsOf: url)
            let digest = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
            guard let registered = lock.withLock({ runtimeCDHashes[digest] }) else {
                throw FakeSigningError.unknownRuntime
            }
            cdHash = registered
        default:
            cdHash = String(repeating: "b", count: 40)
        }
        let teamIdentifier = lock.withLock {
            teamMismatchIdentifier == expectedIdentifier
                ? "Z9Y8X7W6V5"
                : expectedTeamIdentifier
        }
        return PrivilegedRuntimeCodeIdentity(
            identifier: expectedIdentifier,
            teamIdentifier: teamIdentifier,
            cdHash: cdHash
        )
    }
}

private enum FakeSigningError: Error {
    case unknownRuntime
}
