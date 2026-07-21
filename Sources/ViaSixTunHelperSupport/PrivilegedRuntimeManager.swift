import CryptoKit
import Darwin
import Foundation
import ViaSixPrivilegedProtocol

public struct VerifiedPrivilegedRuntime: Equatable, Sendable {
    public let executableURL: URL
    public let manifest: PrivilegedRuntimeManifest

    public init(
        executableURL: URL,
        manifest: PrivilegedRuntimeManifest
    ) {
        self.executableURL = executableURL
        self.manifest = manifest
    }
}

public enum PrivilegedRuntimeManagerError: LocalizedError, Equatable, Sendable {
    case invalidHelperLocation(String)
    case invalidDirectory(String)
    case invalidFile(path: String, reason: String)
    case insecureOwnership(path: String, expected: UInt32, actual: UInt32)
    case insecureGroup(path: String, expected: UInt32, actual: UInt32)
    case insecurePermissions(path: String, expected: UInt16, actual: UInt16)
    case binaryTooLarge(Int64)
    case digestMismatch(expected: String, actual: String)
    case cdHashMismatch(expected: String, actual: String)
    case helperCDHashMismatch
    case installedManifestMismatch
    case sourceChangedDuringRead
    case rollbackFailed(original: String, rollback: String)
    case posix(operation: String, code: Int32)

    public var errorDescription: String? {
        switch self {
        case .invalidHelperLocation(let path):
            "特权 helper 不在固定的应用内嵌位置：\(path)"
        case .invalidDirectory(let path):
            "特权运行组件目录无效：\(path)"
        case .invalidFile(let path, let reason):
            "特权运行组件文件无效（\(path)）：\(reason)"
        case .insecureOwnership(let path, let expected, let actual):
            "特权运行组件所有者无效（\(path)，需要 \(expected)，实际 \(actual)）"
        case .insecureGroup(let path, let expected, let actual):
            "特权运行组件所属组无效（\(path)，需要 \(expected)，实际 \(actual)）"
        case .insecurePermissions(let path, let expected, let actual):
            "特权运行组件权限无效（\(path)，需要 \(String(expected, radix: 8))，实际 \(String(actual, radix: 8))）"
        case .binaryTooLarge(let size):
            "特权 Mihomo 文件过大：\(size) 字节"
        case .digestMismatch(let expected, let actual):
            "特权 Mihomo 摘要不匹配（需要 \(expected)，实际 \(actual)）"
        case .cdHashMismatch(let expected, let actual):
            "特权 Mihomo CDHash 不匹配（需要 \(expected)，实际 \(actual)）"
        case .helperCDHashMismatch:
            "当前 helper 与应用内嵌 helper 的签名不一致"
        case .installedManifestMismatch:
            "已安装的特权运行组件与当前应用版本不一致"
        case .sourceChangedDuringRead:
            "读取特权 Mihomo 时源文件发生变化"
        case .rollbackFailed(let original, let rollback):
            "特权运行组件安装失败且无法恢复旧版本（原始错误：\(original)；恢复错误：\(rollback)）"
        case .posix(let operation, let code):
            "特权运行组件操作失败（\(operation)，errno \(code)）"
        }
    }
}

struct PrivilegedRuntimeInstallationHooks: Sendable {
    var afterAtomicReplacement: @Sendable () throws -> Void = {}
}

/// Owns the fixed, root-only Mihomo runtime used by the launch daemon.
///
/// The public surface deliberately accepts no executable, manifest, bundle,
/// or destination path. The source is always derived from the running helper's
/// fixed location inside its outer app bundle, and the production destination
/// is always the system Application Support directory below.
public struct PrivilegedRuntimeManager: Sendable {
    public static let systemContainerDirectory = URL(
        fileURLWithPath: "/Library/Application Support/com.felix.viasix",
        isDirectory: true
    )

    private static let runtimeDirectoryName = "Runtime"
    private static let runtimeExecutableName = "mihomo"
    private static let installedManifestName = "PrivilegedRuntime.plist"
    private static let maximumBinaryBytes: Int64 = 512 * 1_024 * 1_024
    private static let operationLock = NSLock()

    private let helperExecutableURLProvider: @Sendable () throws -> URL
    private let containerDirectoryURL: URL
    private let expectedOwnerUserIdentifier: UInt32
    private let expectedOwnerGroupIdentifier: UInt32
    private let codeSigningVerifier: any PrivilegedRuntimeCodeSigningVerifying
    private let hooks: PrivilegedRuntimeInstallationHooks

    public init() {
        self.init(
            helperExecutableURLProvider:
                SecurityPrivilegedRuntimeCodeSigningVerifier.currentProcessCodeURL,
            containerDirectoryURL: Self.systemContainerDirectory,
            expectedOwnerUserIdentifier: 0,
            expectedOwnerGroupIdentifier: 0,
            codeSigningVerifier: SecurityPrivilegedRuntimeCodeSigningVerifier(),
            hooks: PrivilegedRuntimeInstallationHooks()
        )
    }

    init(
        helperExecutableURLProvider: @escaping @Sendable () throws -> URL,
        containerDirectoryURL: URL,
        expectedOwnerUserIdentifier: UInt32,
        expectedOwnerGroupIdentifier: UInt32,
        codeSigningVerifier: any PrivilegedRuntimeCodeSigningVerifying,
        hooks: PrivilegedRuntimeInstallationHooks = PrivilegedRuntimeInstallationHooks()
    ) {
        self.helperExecutableURLProvider = helperExecutableURLProvider
        self.containerDirectoryURL = containerDirectoryURL
        self.expectedOwnerUserIdentifier = expectedOwnerUserIdentifier
        self.expectedOwnerGroupIdentifier = expectedOwnerGroupIdentifier
        self.codeSigningVerifier = codeSigningVerifier
        self.hooks = hooks
    }

    /// Validates the sealed app source, stages a root-owned copy, atomically
    /// replaces the active directory, and validates the installed copy again.
    @discardableResult
    public func installBundledRuntime() throws -> VerifiedPrivilegedRuntime {
        try Self.operationLock.withLock {
            try installBundledRuntimeLocked()
        }
    }

    private func installBundledRuntimeLocked() throws -> VerifiedPrivilegedRuntime {
        let source = try validatedBundledSource()
        defer { source.close() }

        let container = try openContainerDirectory(createIfMissing: true)
        defer { close(container) }

        let stagingName = ".Runtime.\(UUID().uuidString).tmp"
        let staging = try createStagingDirectory(named: stagingName, in: container)
        var stagingEntryExists = true
        defer {
            close(staging)
            if stagingEntryExists {
                try? removeRuntimeDirectory(named: stagingName, in: container)
            }
        }

        let copiedDigest = try installFiles(from: source, into: staging)
        guard copiedDigest == source.manifest.sha256 else {
            throw PrivilegedRuntimeManagerError.digestMismatch(
                expected: source.manifest.sha256,
                actual: copiedDigest
            )
        }
        guard fsync(staging) == 0 else {
            throw posixError("fsync(staging directory)")
        }

        let stagingURL = containerDirectoryURL.appendingPathComponent(
            stagingName,
            isDirectory: true
        )
        _ = try validateRuntimeDirectory(
            named: stagingName,
            in: container,
            at: stagingURL,
            expectedManifest: source.manifest,
            expectedTeamIdentifier: source.teamIdentifier
        )

        let hadExistingRuntime = try runtimeEntryExists(in: container)
        if hadExistingRuntime {
            try validateExistingRuntimeStructure(
                named: Self.runtimeDirectoryName,
                in: container,
                at: runtimeDirectoryURL
            )
            guard
                renameatx_np(
                    container,
                    stagingName,
                    container,
                    Self.runtimeDirectoryName,
                    UInt32(RENAME_SWAP)
                ) == 0
            else {
                throw posixError("renameatx_np(Runtime swap)")
            }
        } else {
            guard
                renameatx_np(
                    container,
                    stagingName,
                    container,
                    Self.runtimeDirectoryName,
                    UInt32(RENAME_EXCL)
                ) == 0
            else {
                throw posixError("renameatx_np(Runtime publish)")
            }
        }
        stagingEntryExists = hadExistingRuntime

        let installed: VerifiedPrivilegedRuntime
        do {
            guard fsync(container) == 0 else {
                throw posixError("fsync(runtime container)")
            }
            try hooks.afterAtomicReplacement()
            installed = try validateRuntimeDirectory(
                named: Self.runtimeDirectoryName,
                in: container,
                at: runtimeDirectoryURL,
                expectedManifest: source.manifest,
                expectedTeamIdentifier: source.teamIdentifier
            )
        } catch {
            do {
                if hadExistingRuntime {
                    guard
                        renameatx_np(
                            container,
                            Self.runtimeDirectoryName,
                            container,
                            stagingName,
                            UInt32(RENAME_SWAP)
                        ) == 0
                    else {
                        throw posixError("renameatx_np(Runtime rollback)")
                    }
                } else {
                    guard
                        renameat(
                            container,
                            Self.runtimeDirectoryName,
                            container,
                            stagingName
                        ) == 0
                    else {
                        throw posixError("renameat(Runtime rollback)")
                    }
                    stagingEntryExists = true
                }
                guard fsync(container) == 0 else {
                    throw posixError("fsync(Runtime rollback)")
                }
            } catch let rollbackError {
                throw PrivilegedRuntimeManagerError.rollbackFailed(
                    original: error.localizedDescription,
                    rollback: rollbackError.localizedDescription
                )
            }
            throw error
        }
        if hadExistingRuntime {
            // The new directory is fully committed at this point. Cleanup is
            // deliberately outside the rollback region because deleting any
            // part of the old directory makes a later rollback unsafe.
            if (try? removeRuntimeDirectory(named: stagingName, in: container)) != nil {
                stagingEntryExists = false
                _ = fsync(container)
            }
        }
        return installed
    }

    /// Returns a verified snapshot for status and diagnostics. Process launch
    /// code must use `withVerifiedInstalledRuntime` so installation cannot swap
    /// the directory between verification and `posix_spawn`.
    public func verifiedInstalledRuntime() throws -> VerifiedPrivilegedRuntime {
        try withVerifiedInstalledRuntime { $0 }
    }

    /// Keeps the process-wide runtime lock held through the caller's operation.
    /// The future fixed-argument launcher must perform `posix_spawn` inside this
    /// closure; returning the URL and launching later is intentionally unsafe.
    public func withVerifiedInstalledRuntime<Result>(
        _ operation: (VerifiedPrivilegedRuntime) throws -> Result
    ) throws -> Result {
        try Self.operationLock.withLock {
            let runtime = try verifiedInstalledRuntimeLocked()
            return try operation(runtime)
        }
    }

    private func verifiedInstalledRuntimeLocked() throws -> VerifiedPrivilegedRuntime {
        let source = try validatedBundledSource()
        defer { source.close() }
        let sourceDigest = try sha256(of: source.runtimeDescriptor)
        guard sourceDigest == source.manifest.sha256 else {
            throw PrivilegedRuntimeManagerError.digestMismatch(
                expected: source.manifest.sha256,
                actual: sourceDigest
            )
        }

        let container = try openContainerDirectory(createIfMissing: false)
        defer { close(container) }
        return try validateRuntimeDirectory(
            named: Self.runtimeDirectoryName,
            in: container,
            at: runtimeDirectoryURL,
            expectedManifest: source.manifest,
            expectedTeamIdentifier: source.teamIdentifier
        )
    }

    private var runtimeDirectoryURL: URL {
        containerDirectoryURL.appendingPathComponent(
            Self.runtimeDirectoryName,
            isDirectory: true
        )
    }

    private var runtimeExecutableURL: URL {
        runtimeDirectoryURL.appendingPathComponent(Self.runtimeExecutableName)
    }

    private func validatedBundledSource() throws -> ValidatedBundledSource {
        let layout = try sourceLayout()
        let app = try openSourceAppDirectory(layout.appBundleURL)
        defer { close(app) }

        let contents = try openDirectory(
            named: "Contents",
            in: app,
            displayPath: layout.appBundleURL.appendingPathComponent("Contents").path
        )
        defer { close(contents) }
        let library = try openDirectory(
            named: "Library",
            in: contents,
            displayPath: layout.appBundleURL.appendingPathComponent("Contents/Library").path
        )
        defer { close(library) }
        let helperTools = try openDirectory(
            named: "HelperTools",
            in: library,
            displayPath: layout.appBundleURL.appendingPathComponent(
                "Contents/Library/HelperTools"
            ).path
        )
        defer { close(helperTools) }
        let resources = try openDirectory(
            named: "Resources",
            in: contents,
            displayPath: layout.appBundleURL.appendingPathComponent("Contents/Resources").path
        )
        defer { close(resources) }

        let helperDescriptor = try openSourceFile(
            named: TunHelperConstants.helperBundleIdentifier,
            in: helperTools,
            displayPath: layout.helperExecutableURL.path,
            executable: true
        )
        defer { close(helperDescriptor) }
        let runtimeDescriptor = try openSourceFile(
            named: "com.felix.viasix.mihomo",
            in: helperTools,
            displayPath: layout.runtimeURL.path,
            executable: true
        )
        var transfersRuntimeDescriptor = false
        defer {
            if !transfersRuntimeDescriptor {
                close(runtimeDescriptor)
            }
        }
        let manifestDescriptor = try openSourceFile(
            named: "PrivilegedRuntime.plist",
            in: resources,
            displayPath: layout.manifestURL.path,
            executable: false
        )
        defer { close(manifestDescriptor) }

        let appSnapshot = try sourceSnapshot(app)
        let helperSnapshot = try sourceSnapshot(helperDescriptor)
        let runtimeSnapshot = try sourceSnapshot(runtimeDescriptor)
        let manifestSnapshot = try sourceSnapshot(manifestDescriptor)

        let manifestData = try readData(
            from: manifestDescriptor,
            maximumBytes: 64 * 1_024,
            tooLarge: { size in
                PrivilegedRuntimeManifestError.manifestTooLarge(size)
            }
        )
        let manifest = try PrivilegedRuntimeManifest(data: manifestData)

        let currentHelperIdentity = try codeSigningVerifier.verifyCurrentHelper(
            expectedIdentifier: TunHelperConstants.helperBundleIdentifier
        )
        try validateCodeIdentity(
            currentHelperIdentity,
            expectedIdentifier: TunHelperConstants.helperBundleIdentifier,
            expectedTeamIdentifier: nil
        )
        let sourceHelperIdentity = try codeSigningVerifier.verifyStaticCode(
            at: layout.helperExecutableURL,
            expectedIdentifier: TunHelperConstants.helperBundleIdentifier,
            expectedTeamIdentifier: currentHelperIdentity.teamIdentifier
        )
        try validateCodeIdentity(
            sourceHelperIdentity,
            expectedIdentifier: TunHelperConstants.helperBundleIdentifier,
            expectedTeamIdentifier: currentHelperIdentity.teamIdentifier
        )
        guard sourceHelperIdentity.cdHash == currentHelperIdentity.cdHash else {
            throw PrivilegedRuntimeManagerError.helperCDHashMismatch
        }
        let appIdentity = try codeSigningVerifier.verifyStaticCode(
            at: layout.appBundleURL,
            expectedIdentifier: TunHelperConstants.appBundleIdentifier,
            expectedTeamIdentifier: currentHelperIdentity.teamIdentifier
        )
        try validateCodeIdentity(
            appIdentity,
            expectedIdentifier: TunHelperConstants.appBundleIdentifier,
            expectedTeamIdentifier: currentHelperIdentity.teamIdentifier
        )
        let runtimeIdentity = try codeSigningVerifier.verifyStaticCode(
            at: layout.runtimeURL,
            expectedIdentifier: PrivilegedRuntimeManifest.expectedBundleIdentifier,
            expectedTeamIdentifier: currentHelperIdentity.teamIdentifier
        )
        try validateCodeIdentity(
            runtimeIdentity,
            expectedIdentifier: PrivilegedRuntimeManifest.expectedBundleIdentifier,
            expectedTeamIdentifier: currentHelperIdentity.teamIdentifier
        )
        guard runtimeIdentity.cdHash == manifest.cdHash else {
            throw PrivilegedRuntimeManagerError.cdHashMismatch(
                expected: manifest.cdHash,
                actual: runtimeIdentity.cdHash
            )
        }
        try validatePath(
            layout.appBundleURL,
            stillReferences: app,
            snapshot: appSnapshot
        )
        try validatePath(
            layout.helperExecutableURL,
            stillReferences: helperDescriptor,
            snapshot: helperSnapshot
        )
        try validatePath(
            layout.runtimeURL,
            stillReferences: runtimeDescriptor,
            snapshot: runtimeSnapshot
        )
        try validatePath(
            layout.manifestURL,
            stillReferences: manifestDescriptor,
            snapshot: manifestSnapshot
        )

        let source = ValidatedBundledSource(
            runtimeDescriptor: runtimeDescriptor,
            manifestData: manifestData,
            manifest: manifest,
            teamIdentifier: currentHelperIdentity.teamIdentifier
        )
        transfersRuntimeDescriptor = true
        return source
    }

    private func installFiles(
        from source: ValidatedBundledSource,
        into staging: Int32
    ) throws -> String {
        let runtime = try createFile(
            named: Self.runtimeExecutableName,
            in: staging,
            finalMode: 0o755
        )
        defer { close(runtime) }
        let digest = try copyAndHash(
            from: source.runtimeDescriptor,
            to: runtime
        )
        guard fchmod(runtime, mode_t(0o755)) == 0 else {
            throw posixError("fchmod(staged Mihomo)")
        }
        guard fsync(runtime) == 0 else {
            throw posixError("fsync(staged Mihomo)")
        }
        try validateInstalledFileDescriptor(
            runtime,
            path: "staging/\(Self.runtimeExecutableName)",
            expectedMode: 0o755
        )

        let manifest = try createFile(
            named: Self.installedManifestName,
            in: staging,
            finalMode: 0o600
        )
        defer { close(manifest) }
        try writeAll(source.manifestData, to: manifest)
        guard fchmod(manifest, mode_t(0o600)) == 0 else {
            throw posixError("fchmod(staged manifest)")
        }
        guard fsync(manifest) == 0 else {
            throw posixError("fsync(staged manifest)")
        }
        try validateInstalledFileDescriptor(
            manifest,
            path: "staging/\(Self.installedManifestName)",
            expectedMode: 0o600
        )
        return digest
    }

    private func validateRuntimeDirectory(
        named directoryName: String,
        in container: Int32,
        at directoryURL: URL,
        expectedManifest: PrivilegedRuntimeManifest?,
        expectedTeamIdentifier: String?
    ) throws -> VerifiedPrivilegedRuntime {
        let directory = openat(
            container,
            directoryName,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard directory >= 0 else { throw posixError("openat(\(directoryName))") }
        defer { close(directory) }
        try validateOwnedDirectoryDescriptor(directory, path: directoryURL.path)

        let manifestDescriptor = openat(
            directory,
            Self.installedManifestName,
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW
        )
        guard manifestDescriptor >= 0 else {
            throw posixError("openat(installed manifest)")
        }
        defer { close(manifestDescriptor) }
        try validateInstalledFileDescriptor(
            manifestDescriptor,
            path: directoryURL.appendingPathComponent(Self.installedManifestName).path,
            expectedMode: 0o600
        )
        let manifestData = try readData(
            from: manifestDescriptor,
            maximumBytes: 64 * 1_024,
            tooLarge: { size in
                PrivilegedRuntimeManifestError.manifestTooLarge(size)
            }
        )
        let manifest = try PrivilegedRuntimeManifest(data: manifestData)
        if let expectedManifest, manifest != expectedManifest {
            throw PrivilegedRuntimeManagerError.installedManifestMismatch
        }

        let runtimeDescriptor = openat(
            directory,
            Self.runtimeExecutableName,
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW
        )
        guard runtimeDescriptor >= 0 else {
            throw posixError("openat(installed Mihomo)")
        }
        defer { close(runtimeDescriptor) }
        try validateInstalledFileDescriptor(
            runtimeDescriptor,
            path: directoryURL.appendingPathComponent(Self.runtimeExecutableName).path,
            expectedMode: 0o755
        )
        let digest = try sha256(of: runtimeDescriptor)
        guard digest == manifest.sha256 else {
            throw PrivilegedRuntimeManagerError.digestMismatch(
                expected: manifest.sha256,
                actual: digest
            )
        }
        let signedSnapshot = try sourceSnapshot(runtimeDescriptor)
        let identity = try codeSigningVerifier.verifyStaticCode(
            at: directoryURL.appendingPathComponent(Self.runtimeExecutableName),
            expectedIdentifier: PrivilegedRuntimeManifest.expectedBundleIdentifier,
            expectedTeamIdentifier: expectedTeamIdentifier
        )
        try validateCodeIdentity(
            identity,
            expectedIdentifier: PrivilegedRuntimeManifest.expectedBundleIdentifier,
            expectedTeamIdentifier: expectedTeamIdentifier
        )
        guard identity.cdHash == manifest.cdHash else {
            throw PrivilegedRuntimeManagerError.cdHashMismatch(
                expected: manifest.cdHash,
                actual: identity.cdHash
            )
        }
        try validatePath(
            directoryURL.appendingPathComponent(Self.runtimeExecutableName),
            stillReferences: runtimeDescriptor,
            snapshot: signedSnapshot
        )
        return VerifiedPrivilegedRuntime(
            executableURL: runtimeExecutableURL,
            manifest: manifest
        )
    }

    private func validateExistingRuntimeStructure(
        named directoryName: String,
        in container: Int32,
        at directoryURL: URL
    ) throws {
        let directory = openat(
            container,
            directoryName,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard directory >= 0 else {
            throw posixError("openat(existing Runtime)")
        }
        defer { close(directory) }
        try validateOwnedDirectoryDescriptor(directory, path: directoryURL.path)

        for (name, mode) in [
            (Self.runtimeExecutableName, UInt16(0o755)),
            (Self.installedManifestName, UInt16(0o600)),
        ] {
            let descriptor = openat(
                directory,
                name,
                O_RDONLY | O_CLOEXEC | O_NOFOLLOW
            )
            guard descriptor >= 0 else {
                throw posixError("openat(existing Runtime file)")
            }
            defer { close(descriptor) }
            try validateInstalledFileDescriptor(
                descriptor,
                path: directoryURL.appendingPathComponent(name).path,
                expectedMode: mode
            )
        }
    }

    private func sourceLayout() throws -> SourceLayout {
        let helperURL = try helperExecutableURLProvider()
        guard
            helperURL.isFileURL,
            helperURL.lastPathComponent == TunHelperConstants.helperBundleIdentifier
        else {
            throw PrivilegedRuntimeManagerError.invalidHelperLocation(helperURL.path)
        }
        let helperTools = helperURL.deletingLastPathComponent()
        let library = helperTools.deletingLastPathComponent()
        let contents = library.deletingLastPathComponent()
        let appBundle = contents.deletingLastPathComponent()
        guard
            helperTools.lastPathComponent == "HelperTools",
            library.lastPathComponent == "Library",
            contents.lastPathComponent == "Contents",
            appBundle.pathExtension == "app"
        else {
            throw PrivilegedRuntimeManagerError.invalidHelperLocation(helperURL.path)
        }
        return SourceLayout(
            appBundleURL: appBundle,
            helperExecutableURL: helperURL,
            runtimeURL: appBundle.appendingPathComponent(
                PrivilegedRuntimeManifest.expectedRelativePath
            ),
            manifestURL: appBundle.appendingPathComponent(
                "Contents/Resources/PrivilegedRuntime.plist"
            )
        )
    }

    private func openContainerDirectory(createIfMissing: Bool) throws -> Int32 {
        let parentURL = containerDirectoryURL.deletingLastPathComponent()
        let directoryName = containerDirectoryURL.lastPathComponent
        guard
            containerDirectoryURL.isFileURL,
            containerDirectoryURL.path.hasPrefix("/"),
            !directoryName.isEmpty,
            directoryName != ".",
            directoryName != ".."
        else {
            throw PrivilegedRuntimeManagerError.invalidDirectory(containerDirectoryURL.path)
        }

        let parent = try openAbsoluteDirectory(parentURL)
        defer { close(parent) }
        var created = false
        if createIfMissing {
            if mkdirat(parent, directoryName, mode_t(0o700)) == 0 {
                created = true
            } else if errno != EEXIST {
                throw posixError("mkdirat(runtime container)")
            }
        }
        let container = openat(
            parent,
            directoryName,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard container >= 0 else { throw posixError("openat(runtime container)") }
        do {
            if created {
                guard
                    fchown(
                        container,
                        expectedOwnerUserIdentifier,
                        expectedOwnerGroupIdentifier
                    ) == 0
                else {
                    throw posixError("fchown(runtime container)")
                }
                guard fchmod(container, mode_t(0o700)) == 0 else {
                    throw posixError("fchmod(runtime container)")
                }
            } else {
                try migrateLegacyContainerGroupIfSafe(
                    container,
                    parent: parent
                )
            }
            try validateOwnedDirectoryDescriptor(
                container,
                path: containerDirectoryURL.path
            )
            return container
        } catch {
            close(container)
            throw error
        }
    }

    private func openAbsoluteDirectory(_ url: URL) throws -> Int32 {
        guard url.isFileURL, url.path.hasPrefix("/") else {
            throw PrivilegedRuntimeManagerError.invalidDirectory(url.path)
        }
        var descriptor = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw posixError("open(/)") }
        do {
            for component in url.pathComponents.dropFirst() {
                guard !component.isEmpty, component != ".", component != ".." else {
                    throw PrivilegedRuntimeManagerError.invalidDirectory(url.path)
                }
                let next = openat(
                    descriptor,
                    component,
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
                )
                guard next >= 0 else {
                    throw posixError("openat(directory component: \(component))")
                }
                close(descriptor)
                descriptor = next
                try validateAncestorDirectoryDescriptor(
                    descriptor,
                    path: component
                )
            }
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }

    private func openSourceAppDirectory(_ url: URL) throws -> Int32 {
        guard url.isFileURL, url.path.hasPrefix("/") else {
            throw PrivilegedRuntimeManagerError.invalidDirectory(url.path)
        }
        var descriptor = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw posixError("open(source /)") }
        do {
            for component in url.pathComponents.dropFirst() {
                guard !component.isEmpty, component != ".", component != ".." else {
                    throw PrivilegedRuntimeManagerError.invalidDirectory(url.path)
                }
                let next = openat(
                    descriptor,
                    component,
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
                )
                guard next >= 0 else {
                    throw posixError("openat(source app component: \(component))")
                }
                close(descriptor)
                descriptor = next
                try validateDirectoryDescriptor(descriptor, path: component)
            }
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }

    private func migrateLegacyContainerGroupIfSafe(
        _ container: Int32,
        parent: Int32
    ) throws {
        var metadata = stat()
        guard fstat(container, &metadata) == 0 else {
            throw posixError("fstat(runtime container migration)")
        }
        guard
            metadata.st_gid != expectedOwnerGroupIdentifier,
            metadata.st_uid == expectedOwnerUserIdentifier,
            UInt16(metadata.st_mode & 0o7777) == 0o700,
            UInt32(geteuid()) == expectedOwnerUserIdentifier
        else { return }

        // Previous builds inherited group `admin` from /Library/Application
        // Support. A root-owned 0700 directory is not exposed to that group,
        // so normalizing only its group to wheel is a safe one-time migration.
        guard
            fchown(
                container,
                expectedOwnerUserIdentifier,
                expectedOwnerGroupIdentifier
            ) == 0
        else {
            throw posixError("fchown(legacy runtime container)")
        }
        guard fsync(container) == 0 else {
            throw posixError("fsync(legacy runtime container)")
        }
        guard fsync(parent) == 0 else {
            throw posixError("fsync(runtime container parent)")
        }
    }

    private func openDirectory(
        named name: String,
        in parent: Int32,
        displayPath: String
    ) throws -> Int32 {
        let descriptor = openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else { throw posixError("openat(source directory)") }
        do {
            try validateDirectoryDescriptor(descriptor, path: displayPath)
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }

    private func openSourceFile(
        named name: String,
        in parent: Int32,
        displayPath: String,
        executable: Bool
    ) throws -> Int32 {
        let descriptor = openat(parent, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw posixError("openat(source file)") }
        do {
            var metadata = stat()
            guard fstat(descriptor, &metadata) == 0 else {
                throw posixError("fstat(source file)")
            }
            guard metadata.st_mode & S_IFMT == S_IFREG else {
                throw PrivilegedRuntimeManagerError.invalidFile(
                    path: displayPath,
                    reason: "不是普通文件"
                )
            }
            guard metadata.st_nlink == 1 else {
                throw PrivilegedRuntimeManagerError.invalidFile(
                    path: displayPath,
                    reason: "硬链接数无效"
                )
            }
            if executable, metadata.st_mode & mode_t(0o111) == 0 {
                throw PrivilegedRuntimeManagerError.invalidFile(
                    path: displayPath,
                    reason: "文件不可执行"
                )
            }
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }

    private func createStagingDirectory(
        named name: String,
        in container: Int32
    ) throws -> Int32 {
        guard mkdirat(container, name, mode_t(0o700)) == 0 else {
            throw posixError("mkdirat(staging directory)")
        }
        let descriptor = openat(
            container,
            name,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else { throw posixError("openat(staging directory)") }
        do {
            guard
                fchown(
                    descriptor,
                    expectedOwnerUserIdentifier,
                    expectedOwnerGroupIdentifier
                ) == 0
            else {
                throw posixError("fchown(staging directory)")
            }
            guard fchmod(descriptor, mode_t(0o700)) == 0 else {
                throw posixError("fchmod(staging directory)")
            }
            try validateOwnedDirectoryDescriptor(descriptor, path: name)
            return descriptor
        } catch {
            close(descriptor)
            _ = unlinkat(container, name, AT_REMOVEDIR)
            throw error
        }
    }

    private func createFile(
        named name: String,
        in directory: Int32,
        finalMode: UInt16
    ) throws -> Int32 {
        let descriptor = openat(
            directory,
            name,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard descriptor >= 0 else { throw posixError("openat(staging file)") }
        do {
            guard
                fchown(
                    descriptor,
                    expectedOwnerUserIdentifier,
                    expectedOwnerGroupIdentifier
                ) == 0
            else {
                throw posixError("fchown(staging file)")
            }
            guard fchmod(descriptor, mode_t(finalMode)) == 0 else {
                throw posixError("fchmod(staging file)")
            }
            return descriptor
        } catch {
            close(descriptor)
            _ = unlinkat(directory, name, 0)
            throw error
        }
    }

    private func runtimeEntryExists(in container: Int32) throws -> Bool {
        var metadata = stat()
        if fstatat(
            container,
            Self.runtimeDirectoryName,
            &metadata,
            AT_SYMLINK_NOFOLLOW
        ) == 0 {
            return true
        }
        if errno == ENOENT { return false }
        throw posixError("fstatat(Runtime)")
    }

    private func removeRuntimeDirectory(named name: String, in container: Int32) throws {
        let directory = openat(
            container,
            name,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard directory >= 0 else {
            if errno == ENOENT { return }
            throw posixError("openat(runtime cleanup)")
        }
        defer { close(directory) }
        for fileName in [Self.runtimeExecutableName, Self.installedManifestName] {
            if unlinkat(directory, fileName, 0) != 0, errno != ENOENT {
                throw posixError("unlinkat(runtime cleanup file)")
            }
        }
        guard unlinkat(container, name, AT_REMOVEDIR) == 0 else {
            throw posixError("unlinkat(runtime cleanup directory)")
        }
    }

    private func validateDirectoryDescriptor(_ descriptor: Int32, path: String) throws {
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else {
            throw posixError("fstat(directory)")
        }
        guard metadata.st_mode & S_IFMT == S_IFDIR else {
            throw PrivilegedRuntimeManagerError.invalidDirectory(path)
        }
    }

    private func validateAncestorDirectoryDescriptor(
        _ descriptor: Int32,
        path: String
    ) throws {
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else {
            throw posixError("fstat(directory ancestor)")
        }
        guard metadata.st_mode & S_IFMT == S_IFDIR else {
            throw PrivilegedRuntimeManagerError.invalidDirectory(path)
        }
        guard
            metadata.st_uid == 0
                || metadata.st_uid == expectedOwnerUserIdentifier
        else {
            throw PrivilegedRuntimeManagerError.insecureOwnership(
                path: path,
                expected: expectedOwnerUserIdentifier,
                actual: metadata.st_uid
            )
        }
        let writableByOthers = metadata.st_mode & mode_t(S_IWGRP | S_IWOTH)
        guard writableByOthers == 0 else {
            throw PrivilegedRuntimeManagerError.insecurePermissions(
                path: path,
                expected: UInt16(metadata.st_mode & 0o755),
                actual: UInt16(metadata.st_mode & 0o7777)
            )
        }
    }

    private func validateOwnedDirectoryDescriptor(
        _ descriptor: Int32,
        path: String
    ) throws {
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else {
            throw posixError("fstat(owned directory)")
        }
        guard metadata.st_mode & S_IFMT == S_IFDIR else {
            throw PrivilegedRuntimeManagerError.invalidDirectory(path)
        }
        guard metadata.st_uid == expectedOwnerUserIdentifier else {
            throw PrivilegedRuntimeManagerError.insecureOwnership(
                path: path,
                expected: expectedOwnerUserIdentifier,
                actual: metadata.st_uid
            )
        }
        guard metadata.st_gid == expectedOwnerGroupIdentifier else {
            throw PrivilegedRuntimeManagerError.insecureGroup(
                path: path,
                expected: expectedOwnerGroupIdentifier,
                actual: metadata.st_gid
            )
        }
        try validateMode(metadata, path: path, expected: 0o700)
    }

    private func validateInstalledFileDescriptor(
        _ descriptor: Int32,
        path: String,
        expectedMode: UInt16
    ) throws {
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else {
            throw posixError("fstat(installed file)")
        }
        guard metadata.st_mode & S_IFMT == S_IFREG else {
            throw PrivilegedRuntimeManagerError.invalidFile(
                path: path,
                reason: "不是普通文件"
            )
        }
        guard metadata.st_nlink == 1 else {
            throw PrivilegedRuntimeManagerError.invalidFile(
                path: path,
                reason: "硬链接数无效"
            )
        }
        guard metadata.st_uid == expectedOwnerUserIdentifier else {
            throw PrivilegedRuntimeManagerError.insecureOwnership(
                path: path,
                expected: expectedOwnerUserIdentifier,
                actual: metadata.st_uid
            )
        }
        guard metadata.st_gid == expectedOwnerGroupIdentifier else {
            throw PrivilegedRuntimeManagerError.insecureGroup(
                path: path,
                expected: expectedOwnerGroupIdentifier,
                actual: metadata.st_gid
            )
        }
        try validateMode(metadata, path: path, expected: expectedMode)
    }

    private func validateCodeIdentity(
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
        if let expectedTeamIdentifier,
            identity.teamIdentifier != expectedTeamIdentifier
        {
            throw PrivilegedRuntimeCodeSigningError.unexpectedTeamIdentifier(
                expected: expectedTeamIdentifier,
                actual: identity.teamIdentifier
            )
        }
        let cdHashBytes = Array(identity.cdHash.utf8)
        guard
            cdHashBytes.count == 40,
            cdHashBytes.allSatisfy({ byte in
                (48...57).contains(byte) || (97...102).contains(byte)
            })
        else {
            throw PrivilegedRuntimeCodeSigningError.malformedCDHash(expectedIdentifier)
        }
    }

    private func validatePath(
        _ url: URL,
        stillReferences descriptor: Int32,
        snapshot: FileSnapshot
    ) throws {
        var descriptorMetadata = stat()
        guard fstat(descriptor, &descriptorMetadata) == 0 else {
            throw posixError("fstat(source identity)")
        }
        var pathMetadata = stat()
        guard lstat(url.path, &pathMetadata) == 0 else {
            throw posixError("lstat(source identity)")
        }
        guard
            descriptorMetadata.st_dev == pathMetadata.st_dev,
            descriptorMetadata.st_ino == pathMetadata.st_ino,
            try sourceSnapshot(descriptor) == snapshot
        else {
            throw PrivilegedRuntimeManagerError.sourceChangedDuringRead
        }
    }

    private func validateMode(
        _ metadata: stat,
        path: String,
        expected: UInt16
    ) throws {
        let actual = UInt16(metadata.st_mode & 0o7777)
        guard actual == expected else {
            throw PrivilegedRuntimeManagerError.insecurePermissions(
                path: path,
                expected: expected,
                actual: actual
            )
        }
    }

    private func copyAndHash(from source: Int32, to destination: Int32) throws -> String {
        let before = try sourceSnapshot(source)
        guard before.size > 0 else {
            throw PrivilegedRuntimeManagerError.invalidFile(
                path: "bundled Mihomo",
                reason: "文件为空"
            )
        }
        guard before.size <= Self.maximumBinaryBytes else {
            throw PrivilegedRuntimeManagerError.binaryTooLarge(before.size)
        }
        guard lseek(source, 0, SEEK_SET) == 0 else {
            throw posixError("lseek(source Mihomo)")
        }

        var hasher = SHA256()
        var totalBytes: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = read(source, &buffer, buffer.count)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw posixError("read(source Mihomo)")
            }
            totalBytes += Int64(count)
            guard totalBytes <= Self.maximumBinaryBytes else {
                throw PrivilegedRuntimeManagerError.binaryTooLarge(totalBytes)
            }
            let chunk = Data(buffer.prefix(count))
            hasher.update(data: chunk)
            try writeAll(chunk, to: destination)
        }

        let after = try sourceSnapshot(source)
        guard before == after, totalBytes == before.size else {
            throw PrivilegedRuntimeManagerError.sourceChangedDuringRead
        }
        return Self.hexString(hasher.finalize())
    }

    private func sha256(of descriptor: Int32) throws -> String {
        let before = try sourceSnapshot(descriptor)
        guard before.size > 0 else {
            throw PrivilegedRuntimeManagerError.invalidFile(
                path: "Mihomo",
                reason: "文件为空"
            )
        }
        guard before.size <= Self.maximumBinaryBytes else {
            throw PrivilegedRuntimeManagerError.binaryTooLarge(before.size)
        }
        guard lseek(descriptor, 0, SEEK_SET) == 0 else {
            throw posixError("lseek(Mihomo)")
        }
        var hasher = SHA256()
        var totalBytes: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw posixError("read(Mihomo)")
            }
            totalBytes += Int64(count)
            guard totalBytes <= Self.maximumBinaryBytes else {
                throw PrivilegedRuntimeManagerError.binaryTooLarge(totalBytes)
            }
            hasher.update(data: Data(buffer.prefix(count)))
        }
        let after = try sourceSnapshot(descriptor)
        guard before == after, totalBytes == before.size else {
            throw PrivilegedRuntimeManagerError.sourceChangedDuringRead
        }
        return Self.hexString(hasher.finalize())
    }

    private func sourceSnapshot(_ descriptor: Int32) throws -> FileSnapshot {
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else {
            throw posixError("fstat(Mihomo snapshot)")
        }
        return FileSnapshot(
            device: metadata.st_dev,
            inode: metadata.st_ino,
            size: metadata.st_size,
            modificationSeconds: metadata.st_mtimespec.tv_sec,
            modificationNanoseconds: metadata.st_mtimespec.tv_nsec,
            changeSeconds: metadata.st_ctimespec.tv_sec,
            changeNanoseconds: metadata.st_ctimespec.tv_nsec
        )
    }

    private func readData(
        from descriptor: Int32,
        maximumBytes: Int,
        tooLarge: (Int) -> any Error
    ) throws -> Data {
        guard lseek(descriptor, 0, SEEK_SET) == 0 else {
            throw posixError("lseek(data)")
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1_024)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw posixError("read(data)")
            }
            data.append(buffer, count: count)
            if data.count > maximumBytes {
                throw tooLarge(data.count)
            }
        }
        return data
    }

    private func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard var address = rawBuffer.baseAddress else { return }
            var remaining = rawBuffer.count
            while remaining > 0 {
                let written = write(descriptor, address, remaining)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw posixError("write(staging file)")
                }
                guard written > 0 else {
                    throw PrivilegedRuntimeManagerError.invalidFile(
                        path: "staging file",
                        reason: "写入没有取得进展"
                    )
                }
                remaining -= written
                address = address.advanced(by: written)
            }
        }
    }

    private func posixError(_ operation: String) -> PrivilegedRuntimeManagerError {
        .posix(operation: operation, code: errno)
    }

    private static func hexString<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

private struct SourceLayout: Sendable {
    let appBundleURL: URL
    let helperExecutableURL: URL
    let runtimeURL: URL
    let manifestURL: URL
}

private final class ValidatedBundledSource: @unchecked Sendable {
    let runtimeDescriptor: Int32
    let manifestData: Data
    let manifest: PrivilegedRuntimeManifest
    let teamIdentifier: String?

    init(
        runtimeDescriptor: Int32,
        manifestData: Data,
        manifest: PrivilegedRuntimeManifest,
        teamIdentifier: String?
    ) {
        self.runtimeDescriptor = runtimeDescriptor
        self.manifestData = manifestData
        self.manifest = manifest
        self.teamIdentifier = teamIdentifier
    }

    func close() {
        Darwin.close(runtimeDescriptor)
    }
}

private struct FileSnapshot: Equatable {
    let device: dev_t
    let inode: ino_t
    let size: off_t
    let modificationSeconds: Int
    let modificationNanoseconds: Int
    let changeSeconds: Int
    let changeNanoseconds: Int
}
