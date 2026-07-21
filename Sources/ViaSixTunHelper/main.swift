import Foundation
import OSLog
import ViaSixPrivilegedProtocol
import ViaSixTunHelperSupport

private let logger = Logger(
    subsystem: TunHelperConstants.helperBundleIdentifier,
    category: "Lifecycle"
)

do {
    let identity = try CodeSigningInspector.currentProcess(
        expectedIdentifier: TunHelperConstants.helperBundleIdentifier
    )
    let clientRequirement = try CodeSigningRequirementBuilder.sameTeamRequirement(
        identifier: TunHelperConstants.appBundleIdentifier,
        teamIdentifier: identity.teamIdentifier
    )

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

    let delegate = TunXPCListener(backend: backend)
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
