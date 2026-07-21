import Darwin
import Foundation
import ServiceManagement
import ViaSixPrivilegedProtocol

enum TunHelperRegistrationState: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

enum TunHelperInstallationStrategy: Equatable, Sendable {
    case serviceManagement
    case localAdministrator
}

enum TunHelperInstallerError: LocalizedError, Equatable, Sendable {
    case installerMissing(String)
    case installerTeamMismatch
    case invalidCurrentUser
    case localUnregisterUnsupported
    case commandFailed(executable: String, status: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .installerMissing(let path):
            "当前应用包缺少 TUN 服务安装器：\(path)"
        case .installerTeamMismatch:
            "TUN 服务安装器与当前应用的签名 Team ID 不一致"
        case .invalidCurrentUser:
            "当前登录用户不能安装 TUN 服务"
        case .localUnregisterUnsupported:
            "本地 TUN 服务只能通过新的安装包覆盖修复"
        case .commandFailed(let executable, let status, let output):
            "\(executable) 执行失败（\(status)）：\(output)"
        }
    }
}

struct TunHelperInstaller {
    private var service: SMAppService {
        SMAppService.daemon(plistName: TunHelperConstants.launchDaemonPlistName)
    }

    func status() -> TunHelperRegistrationState {
        switch (try? installationStrategy()) ?? .serviceManagement {
        case .serviceManagement:
            Self.map(service.status)
        case .localAdministrator:
            localServiceIsLoaded() ? .enabled : .notRegistered
        }
    }

    @discardableResult
    func register() throws -> TunHelperRegistrationState {
        switch try installationStrategy() {
        case .serviceManagement:
            try service.register()
        case .localAdministrator:
            try runLocalInstaller()
        }
        return status()
    }

    @discardableResult
    func unregister() async throws -> TunHelperRegistrationState {
        switch try installationStrategy() {
        case .serviceManagement:
            try await service.unregister()
            return status()
        case .localAdministrator:
            throw TunHelperInstallerError.localUnregisterUnsupported
        }
    }

    @discardableResult
    func reregister() async throws -> TunHelperRegistrationState {
        switch try installationStrategy() {
        case .serviceManagement:
            switch service.status {
            case .enabled, .requiresApproval:
                try await service.unregister()
            case .notRegistered, .notFound:
                break
            @unknown default:
                break
            }
            try service.register()
        case .localAdministrator:
            try runLocalInstaller()
        }
        return status()
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    static func strategy(for identity: CodeSigningIdentity) -> TunHelperInstallationStrategy {
        identity.teamIdentifier == nil ? .localAdministrator : .serviceManagement
    }

    static func map(_ status: SMAppService.Status) -> TunHelperRegistrationState {
        switch status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .notFound
        }
    }

    private func installationStrategy() throws -> TunHelperInstallationStrategy {
        #if VIASIX_PACKAGED_APP
            let identity = try CodeSigningInspector.currentProcess(
                expectedIdentifier: TunHelperConstants.appBundleIdentifier
            )
            return Self.strategy(for: identity)
        #else
            return .serviceManagement
        #endif
    }

    private func localServiceIsLoaded() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = [
            "print",
            "system/\(TunHelperConstants.helperBundleIdentifier)",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func runLocalInstaller() throws {
        let userIdentifier = getuid()
        guard userIdentifier > 0 else {
            throw TunHelperInstallerError.invalidCurrentUser
        }
        let appIdentity = try CodeSigningInspector.currentProcess(
            expectedIdentifier: TunHelperConstants.appBundleIdentifier
        )
        let installerURL = Bundle.main.bundleURL.appendingPathComponent(
            TunHelperConstants.installerRelativePath
        )
        guard FileManager.default.isExecutableFile(atPath: installerURL.path) else {
            throw TunHelperInstallerError.installerMissing(installerURL.path)
        }
        let installerIdentity = try CodeSigningInspector.staticCode(
            at: installerURL,
            expectedIdentifier: TunHelperConstants.installerBundleIdentifier
        )
        guard installerIdentity.teamIdentifier == appIdentity.teamIdentifier else {
            throw TunHelperInstallerError.installerTeamMismatch
        }

        let script = """
            on run argv
                if (count of argv) is not 2 then error "missing installer arguments"
                set installerPath to item 1 of argv
                set userIdentifier to item 2 of argv
                do shell script (quoted form of installerPath & " install " & quoted form of userIdentifier) with administrator privileges
            end run
            """
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script, installerURL.path, String(userIdentifier)]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let outputText = String(decoding: outputData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw TunHelperInstallerError.commandFailed(
                executable: "osascript",
                status: process.terminationStatus,
                output: outputText
            )
        }
    }
}
