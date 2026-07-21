import Darwin
import Foundation
import OSLog
import ViaSixPrivilegedProtocol
import ViaSixTunHelperSupport

private let logger = Logger(
    subsystem: TunHelperConstants.helperBundleIdentifier,
    category: "Lifecycle"
)

do {
    guard geteuid() == 0 else {
        throw CocoaError(
            .userCancelled,
            userInfo: [
                NSLocalizedDescriptionKey: "ViaSix TUN helper 只能由 root LaunchDaemon 启动"
            ])
    }
    let identity = try CodeSigningInspector.currentProcess(
        expectedIdentifier: TunHelperConstants.helperBundleIdentifier
    )
    let clientRequirement: String
    let authorizedClientUserIdentifier: UInt32?
    if let teamIdentifier = identity.teamIdentifier {
        clientRequirement = try CodeSigningRequirementBuilder.sameTeamRequirement(
            identifier: TunHelperConstants.appBundleIdentifier,
            teamIdentifier: teamIdentifier
        )
        authorizedClientUserIdentifier = nil
    } else {
        let policy = try TunLocalInstallationPolicy(
            contentsOf: URL(fileURLWithPath: TunHelperConstants.localInstallationPolicyPath)
        )
        guard identity.cdHash == policy.helperCDHash else {
            throw CocoaError(
                .fileReadCorruptFile,
                userInfo: [
                    NSLocalizedDescriptionKey: "当前 helper 与本地安装策略不匹配，请重新修复服务"
                ])
        }
        let installedAppIdentity = try CodeSigningInspector.staticCode(
            at: URL(fileURLWithPath: TunHelperConstants.localInstalledAppPath),
            expectedIdentifier: policy.appIdentifier
        )
        guard installedAppIdentity.teamIdentifier == nil,
            installedAppIdentity.cdHash == policy.appCDHash
        else {
            throw CocoaError(
                .fileReadCorruptFile,
                userInfo: [
                    NSLocalizedDescriptionKey: "已安装 App 与本地安装策略不匹配，请重新修复服务"
                ])
        }
        clientRequirement = try CodeSigningRequirementBuilder.identifierRequirement(
            identifier: policy.appIdentifier
        )
        authorizedClientUserIdentifier = policy.authorizedUserIdentifier
    }

    let journalController = TunSessionJournalController()
    let backend = PrivilegedTunBackend(journalController: journalController)
    do {
        _ = try backend.recoverAtStartup()
    } catch {
        // Keep serving status/recovery so the app can surface and retry the
        // exact failure without discarding the root-owned recovery journal.
        logger.error(
            "Initial TUN recovery failed: \(error.localizedDescription, privacy: .public)"
        )
    }

    let delegate = TunXPCListener(
        backend: backend,
        authorizedClientUserIdentifier: authorizedClientUserIdentifier
    )
    let listener = NSXPCListener(machServiceName: TunHelperConstants.machServiceName)
    listener.setConnectionCodeSigningRequirement(clientRequirement)
    listener.delegate = delegate
    listener.activate()
    logger.info("ViaSix TUN helper is ready")
    RunLoop.current.run()
} catch {
    logger.fault("ViaSix TUN helper refused to start: \(error.localizedDescription, privacy: .public)")
    exit(EXIT_FAILURE)
}
