import Darwin
import Foundation
import ViaSixPrivilegedProtocol

private enum TunInstallerError: LocalizedError {
    case mustRunAsRoot
    case unsupportedCommand(String)
    case invalidExecutablePath(String)
    case invalidUserIdentifier(String)
    case invalidAppLayout(String)
    case unsafeFile(path: String, reason: String)
    case signingMismatch(String)
    case launchctlFailed(arguments: [String], status: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .mustRunAsRoot:
            "TUN 服务安装器需要管理员权限"
        case .unsupportedCommand(let command):
            "不支持的 TUN 安装命令：\(command)"
        case .invalidExecutablePath(let path):
            "TUN 安装器路径无效：\(path)"
        case .invalidUserIdentifier(let value):
            "TUN 安装器用户标识无效：\(value)"
        case .invalidAppLayout(let path):
            "TUN 安装器不在 ViaSix.app 的固定位置：\(path)"
        case .unsafeFile(let path, let reason):
            "TUN 安装源包含不安全文件（\(path)）：\(reason)"
        case .signingMismatch(let detail):
            "TUN 安装源签名不一致：\(detail)"
        case .launchctlFailed(let arguments, let status, let output):
            "launchctl \(arguments.joined(separator: " ")) 失败（\(status)）：\(output)"
        }
    }
}

private struct TunInstallerIdentities {
    let app: CodeSigningIdentity
    let helper: CodeSigningIdentity
    let installer: CodeSigningIdentity
    let runtime: CodeSigningIdentity
}

private struct TunLocalServiceInstaller {
    private let fileManager = FileManager.default

    func run(command: String, userIdentifier: String) throws {
        guard geteuid() == 0 else { throw TunInstallerError.mustRunAsRoot }
        guard command == "install" else {
            throw TunInstallerError.unsupportedCommand(command)
        }
        guard let authorizedUserIdentifier = UInt32(userIdentifier),
            authorizedUserIdentifier > 0,
            getpwuid(uid_t(authorizedUserIdentifier)) != nil
        else {
            throw TunInstallerError.invalidUserIdentifier(userIdentifier)
        }
        try install(authorizedUserIdentifier: authorizedUserIdentifier)
    }

    private func install(authorizedUserIdentifier: UInt32) throws {
        let executableURL = try currentExecutableURL()
        let sourceAppURL = try enclosingAppURL(for: executableURL)
        try validateTree(at: sourceAppURL, requiresRootOwnership: false)
        let identities = try validateSignedSource(
            appURL: sourceAppURL,
            currentInstallerURL: executableURL
        )

        let containerURL = URL(
            fileURLWithPath: TunHelperConstants.localInstallationContainerPath,
            isDirectory: true
        )
        let installedRootURL = containerURL.appendingPathComponent(
            "InstalledApp",
            isDirectory: true
        )
        try ensureSecureDirectory(at: containerURL, mode: 0o700)
        try ensureSecureDirectory(at: installedRootURL, mode: 0o700)

        let transaction = UUID().uuidString
        let stagedAppURL = installedRootURL.appendingPathComponent(
            ".ViaSix.\(transaction).app",
            isDirectory: true
        )
        let installedAppURL = URL(
            fileURLWithPath: TunHelperConstants.localInstalledAppPath,
            isDirectory: true
        )
        let backupAppURL = installedRootURL.appendingPathComponent(
            ".ViaSix.\(transaction).backup",
            isDirectory: true
        )
        let policyURL = URL(
            fileURLWithPath: TunHelperConstants.localInstallationPolicyPath
        )
        let stagedPolicyURL = containerURL.appendingPathComponent(
            ".TunLocalInstallationPolicy.\(transaction).tmp"
        )
        let backupPolicyURL = containerURL.appendingPathComponent(
            ".TunLocalInstallationPolicy.\(transaction).backup"
        )
        let daemonPlistURL = URL(
            fileURLWithPath: TunHelperConstants.systemLaunchDaemonPlistPath
        )
        let stagedDaemonPlistURL = daemonPlistURL.deletingLastPathComponent()
            .appendingPathComponent(".\(TunHelperConstants.launchDaemonPlistName).\(transaction).tmp")
        let backupDaemonPlistURL = daemonPlistURL.deletingLastPathComponent()
            .appendingPathComponent(".\(TunHelperConstants.launchDaemonPlistName).\(transaction).backup")

        defer {
            try? fileManager.removeItem(at: stagedAppURL)
            try? fileManager.removeItem(at: stagedPolicyURL)
            try? fileManager.removeItem(at: stagedDaemonPlistURL)
        }

        try fileManager.copyItem(at: sourceAppURL, to: stagedAppURL)
        try secureTree(at: stagedAppURL)
        try validateTree(at: stagedAppURL, requiresRootOwnership: true)
        try validateCopiedApp(at: stagedAppURL, matches: identities)

        let policy = try TunLocalInstallationPolicy(
            appIdentifier: identities.app.identifier,
            appCDHash: identities.app.cdHash,
            helperIdentifier: identities.helper.identifier,
            helperCDHash: identities.helper.cdHash,
            authorizedUserIdentifier: authorizedUserIdentifier
        )
        try policy.encodedPropertyList().write(to: stagedPolicyURL, options: .withoutOverwriting)
        try secureRegularFile(at: stagedPolicyURL, mode: 0o600)

        let daemonData = try makeLaunchDaemonPropertyList(installedAppURL: installedAppURL)
        try daemonData.write(to: stagedDaemonPlistURL, options: .withoutOverwriting)
        try secureRegularFile(at: stagedDaemonPlistURL, mode: 0o644)

        try publish(
            stagedAppURL: stagedAppURL,
            installedAppURL: installedAppURL,
            backupAppURL: backupAppURL,
            stagedPolicyURL: stagedPolicyURL,
            policyURL: policyURL,
            backupPolicyURL: backupPolicyURL,
            stagedDaemonPlistURL: stagedDaemonPlistURL,
            daemonPlistURL: daemonPlistURL,
            backupDaemonPlistURL: backupDaemonPlistURL
        )
    }

    private func currentExecutableURL() throws -> URL {
        let path = CommandLine.arguments[0]
        guard path.hasPrefix("/") else {
            throw TunInstallerError.invalidExecutablePath(path)
        }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    private func enclosingAppURL(for executableURL: URL) throws -> URL {
        let helperToolsURL = executableURL.deletingLastPathComponent()
        let libraryURL = helperToolsURL.deletingLastPathComponent()
        let contentsURL = libraryURL.deletingLastPathComponent()
        let appURL = contentsURL.deletingLastPathComponent()
        guard
            executableURL.lastPathComponent == TunHelperConstants.installerBundleIdentifier,
            helperToolsURL.lastPathComponent == "HelperTools",
            libraryURL.lastPathComponent == "Library",
            contentsURL.lastPathComponent == "Contents",
            appURL.pathExtension == "app"
        else {
            throw TunInstallerError.invalidAppLayout(executableURL.path)
        }
        return appURL
    }

    private func validateSignedSource(
        appURL: URL,
        currentInstallerURL: URL
    ) throws -> TunInstallerIdentities {
        let helperURL = appURL.appendingPathComponent(TunHelperConstants.helperRelativePath)
        let installerURL = appURL.appendingPathComponent(TunHelperConstants.installerRelativePath)
        let runtimeURL = appURL.appendingPathComponent(
            "Contents/Library/HelperTools/com.felix.viasix.mihomo"
        )
        guard installerURL.standardizedFileURL == currentInstallerURL.standardizedFileURL else {
            throw TunInstallerError.invalidAppLayout(currentInstallerURL.path)
        }

        let currentInstaller = try CodeSigningInspector.currentProcess(
            expectedIdentifier: TunHelperConstants.installerBundleIdentifier
        )
        let app = try CodeSigningInspector.staticCode(
            at: appURL,
            expectedIdentifier: TunHelperConstants.appBundleIdentifier
        )
        let helper = try CodeSigningInspector.staticCode(
            at: helperURL,
            expectedIdentifier: TunHelperConstants.helperBundleIdentifier
        )
        let installer = try CodeSigningInspector.staticCode(
            at: installerURL,
            expectedIdentifier: TunHelperConstants.installerBundleIdentifier
        )
        let runtime = try CodeSigningInspector.staticCode(
            at: runtimeURL,
            expectedIdentifier: "com.felix.viasix.mihomo"
        )
        guard currentInstaller == installer else {
            throw TunInstallerError.signingMismatch("当前安装器与 App 内安装器不同")
        }
        guard helper.teamIdentifier == app.teamIdentifier,
            installer.teamIdentifier == app.teamIdentifier,
            runtime.teamIdentifier == app.teamIdentifier
        else {
            throw TunInstallerError.signingMismatch("App、helper、installer 与 Mihomo 的 Team ID 不同")
        }
        return TunInstallerIdentities(
            app: app,
            helper: helper,
            installer: installer,
            runtime: runtime
        )
    }

    private func validateCopiedApp(
        at appURL: URL,
        matches expected: TunInstallerIdentities
    ) throws {
        let actual = try validateSignedSourceCopy(at: appURL)
        guard actual.app == expected.app,
            actual.helper == expected.helper,
            actual.installer == expected.installer,
            actual.runtime == expected.runtime
        else {
            throw TunInstallerError.signingMismatch("复制期间签名身份发生变化")
        }
    }

    private func validateSignedSourceCopy(at appURL: URL) throws -> TunInstallerIdentities {
        let app = try CodeSigningInspector.staticCode(
            at: appURL,
            expectedIdentifier: TunHelperConstants.appBundleIdentifier
        )
        let helper = try CodeSigningInspector.staticCode(
            at: appURL.appendingPathComponent(TunHelperConstants.helperRelativePath),
            expectedIdentifier: TunHelperConstants.helperBundleIdentifier
        )
        let installer = try CodeSigningInspector.staticCode(
            at: appURL.appendingPathComponent(TunHelperConstants.installerRelativePath),
            expectedIdentifier: TunHelperConstants.installerBundleIdentifier
        )
        let runtime = try CodeSigningInspector.staticCode(
            at: appURL.appendingPathComponent(
                "Contents/Library/HelperTools/com.felix.viasix.mihomo"
            ),
            expectedIdentifier: "com.felix.viasix.mihomo"
        )
        return TunInstallerIdentities(
            app: app,
            helper: helper,
            installer: installer,
            runtime: runtime
        )
    }

    private func makeLaunchDaemonPropertyList(installedAppURL: URL) throws -> Data {
        let helperURL = installedAppURL.appendingPathComponent(
            TunHelperConstants.helperRelativePath
        )
        let propertyList: [String: Any] = [
            "Label": TunHelperConstants.helperBundleIdentifier,
            "ProgramArguments": [helperURL.path],
            "UserName": "root",
            "MachServices": [TunHelperConstants.machServiceName: true],
        ]
        return try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .xml,
            options: 0
        )
    }

    private func publish(
        stagedAppURL: URL,
        installedAppURL: URL,
        backupAppURL: URL,
        stagedPolicyURL: URL,
        policyURL: URL,
        backupPolicyURL: URL,
        stagedDaemonPlistURL: URL,
        daemonPlistURL: URL,
        backupDaemonPlistURL: URL
    ) throws {
        var backedUpApp = false
        var backedUpPolicy = false
        var backedUpDaemon = false
        do {
            if fileManager.fileExists(atPath: installedAppURL.path) {
                try validateTree(at: installedAppURL, requiresRootOwnership: true)
                try fileManager.moveItem(at: installedAppURL, to: backupAppURL)
                backedUpApp = true
            }
            if fileManager.fileExists(atPath: policyURL.path) {
                try validateSecureRegularFile(at: policyURL, maximumMode: 0o600)
                try fileManager.moveItem(at: policyURL, to: backupPolicyURL)
                backedUpPolicy = true
            }
            if fileManager.fileExists(atPath: daemonPlistURL.path) {
                try validateSecureRegularFile(at: daemonPlistURL, maximumMode: 0o644)
                try fileManager.moveItem(at: daemonPlistURL, to: backupDaemonPlistURL)
                backedUpDaemon = true
            }

            try fileManager.moveItem(at: stagedAppURL, to: installedAppURL)
            try fileManager.moveItem(at: stagedPolicyURL, to: policyURL)
            try fileManager.moveItem(at: stagedDaemonPlistURL, to: daemonPlistURL)

            _ = try runLaunchctl(
                ["bootout", "system/\(TunHelperConstants.helperBundleIdentifier)"],
                requiresSuccess: false
            )
            _ = try runLaunchctl(
                ["bootstrap", "system", daemonPlistURL.path],
                requiresSuccess: true
            )
        } catch {
            _ = try? runLaunchctl(
                ["bootout", "system/\(TunHelperConstants.helperBundleIdentifier)"],
                requiresSuccess: false
            )
            try? fileManager.removeItem(at: installedAppURL)
            try? fileManager.removeItem(at: policyURL)
            try? fileManager.removeItem(at: daemonPlistURL)
            if backedUpApp {
                try? fileManager.moveItem(at: backupAppURL, to: installedAppURL)
            }
            if backedUpPolicy {
                try? fileManager.moveItem(at: backupPolicyURL, to: policyURL)
            }
            if backedUpDaemon {
                try? fileManager.moveItem(at: backupDaemonPlistURL, to: daemonPlistURL)
                _ = try? runLaunchctl(
                    ["bootstrap", "system", daemonPlistURL.path],
                    requiresSuccess: false
                )
            }
            throw error
        }

        if backedUpApp { try? fileManager.removeItem(at: backupAppURL) }
        if backedUpPolicy { try? fileManager.removeItem(at: backupPolicyURL) }
        if backedUpDaemon { try? fileManager.removeItem(at: backupDaemonPlistURL) }
    }

    private func ensureSecureDirectory(at url: URL, mode: mode_t) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
        }
        var metadata = stat()
        guard lstat(url.path, &metadata) == 0,
            metadata.st_mode & S_IFMT == S_IFDIR
        else {
            throw TunInstallerError.unsafeFile(path: url.path, reason: "不是普通目录")
        }
        guard metadata.st_uid == 0, metadata.st_mode & 0o022 == 0 else {
            throw TunInstallerError.unsafeFile(path: url.path, reason: "目录所有权或权限不安全")
        }
        guard chown(url.path, 0, 0) == 0, chmod(url.path, mode) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
    }

    private func validateTree(at rootURL: URL, requiresRootOwnership: Bool) throws {
        try validateNode(at: rootURL, requiresRootOwnership: requiresRootOwnership)
        for url in try descendantURLs(at: rootURL) {
            try validateNode(at: url, requiresRootOwnership: requiresRootOwnership)
        }
    }

    private func validateNode(at url: URL, requiresRootOwnership: Bool) throws {
        var metadata = stat()
        guard lstat(url.path, &metadata) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        let type = metadata.st_mode & S_IFMT
        guard type == S_IFDIR || type == S_IFREG else {
            throw TunInstallerError.unsafeFile(path: url.path, reason: "仅允许普通文件和目录")
        }
        if type == S_IFREG, metadata.st_nlink != 1 {
            throw TunInstallerError.unsafeFile(path: url.path, reason: "硬链接数无效")
        }
        if requiresRootOwnership {
            guard metadata.st_uid == 0, metadata.st_gid == 0 else {
                throw TunInstallerError.unsafeFile(path: url.path, reason: "不是 root:wheel 所有")
            }
            guard metadata.st_mode & 0o022 == 0 else {
                throw TunInstallerError.unsafeFile(path: url.path, reason: "组或其他用户可写")
            }
        }
    }

    private func secureTree(at rootURL: URL) throws {
        try secureNode(at: rootURL)
        for url in try descendantURLs(at: rootURL) {
            try secureNode(at: url)
        }
    }

    private func descendantURLs(at rootURL: URL) throws -> [URL] {
        var result: [URL] = []
        func appendContents(of directoryURL: URL) throws {
            let children = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: []
            )
            for childURL in children {
                var metadata = stat()
                guard lstat(childURL.path, &metadata) == 0 else {
                    throw POSIXError(.init(rawValue: errno) ?? .EIO)
                }
                result.append(childURL)
                if metadata.st_mode & S_IFMT == S_IFDIR {
                    try appendContents(of: childURL)
                }
            }
        }
        try appendContents(of: rootURL)
        return result
    }

    private func secureNode(at url: URL) throws {
        var metadata = stat()
        guard lstat(url.path, &metadata) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        let type = metadata.st_mode & S_IFMT
        guard type == S_IFDIR || type == S_IFREG else {
            throw TunInstallerError.unsafeFile(path: url.path, reason: "仅允许普通文件和目录")
        }
        var mode = mode_t(metadata.st_mode & 0o755)
        mode &= ~mode_t(0o022)
        if type == S_IFDIR { mode |= 0o700 }
        if type == S_IFREG { mode |= 0o400 }
        guard chown(url.path, 0, 0) == 0, chmod(url.path, mode) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
    }

    private func secureRegularFile(at url: URL, mode: mode_t) throws {
        guard chown(url.path, 0, 0) == 0, chmod(url.path, mode) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        try validateSecureRegularFile(at: url, maximumMode: mode)
    }

    private func validateSecureRegularFile(at url: URL, maximumMode: mode_t) throws {
        var metadata = stat()
        guard lstat(url.path, &metadata) == 0,
            metadata.st_mode & S_IFMT == S_IFREG,
            metadata.st_nlink == 1,
            metadata.st_uid == 0,
            metadata.st_gid == 0,
            metadata.st_mode & 0o777 == maximumMode
        else {
            throw TunInstallerError.unsafeFile(path: url.path, reason: "文件所有权或权限不安全")
        }
    }

    private func runLaunchctl(
        _ arguments: [String],
        requiresSuccess: Bool
    ) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if requiresSuccess, process.terminationStatus != 0 {
            throw TunInstallerError.launchctlFailed(
                arguments: arguments,
                status: process.terminationStatus,
                output: text
            )
        }
        return text
    }
}

do {
    let command = CommandLine.arguments.dropFirst().first ?? ""
    let userIdentifier = CommandLine.arguments.dropFirst(2).first ?? ""
    try TunLocalServiceInstaller().run(
        command: command,
        userIdentifier: userIdentifier
    )
    print("ViaSix TUN service installed")
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
