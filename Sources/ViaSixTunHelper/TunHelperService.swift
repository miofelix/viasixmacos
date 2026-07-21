import Foundation
import ViaSixMihomoConfig
import ViaSixPrivilegedProtocol
import ViaSixTunHelperSupport

final class TunHelperService: NSObject, TunHelperXPCProtocol {
    private let clientUserIdentifier: UInt32
    private let journalController: TunSessionJournalController
    private let now: @Sendable () -> Date

    init(
        clientUserIdentifier: UInt32,
        journalController: TunSessionJournalController,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.clientUserIdentifier = clientUserIdentifier
        self.journalController = journalController
        self.now = now
    }

    func probe(
        reply: @escaping (Int, Int, UInt64, Bool, NSError?) -> Void
    ) {
        do {
            reply(
                TunHelperConstants.protocolVersion,
                TunHelperConstants.implementationVersion,
                0,
                try journalController.recoveryPending(),
                nil
            )
        } catch {
            reply(
                TunHelperConstants.protocolVersion,
                TunHelperConstants.implementationVersion,
                0,
                false,
                error as NSError
            )
        }
    }

    func status(
        reply: @escaping (TunHelperStatusSnapshot?, NSError?) -> Void
    ) {
        do {
            reply(try statusSnapshot(), nil)
        } catch {
            reply(nil, error as NSError)
        }
    }

    func installOrRepairRuntime(
        reply: @escaping (TunHelperStatusSnapshot?, NSError?) -> Void
    ) {
        // Runtime installation will use only the signed runtime embedded at a
        // fixed app-relative location. Until that backend exists, do nothing.
        reply(nil, TunHelperRemoteError.backendUnavailable())
    }

    func startSession(
        configuration: TunConfigurationEnvelope,
        reply: @escaping (TunHelperStatusSnapshot?, NSError?) -> Void
    ) {
        do {
            // Validate again at the privilege boundary even though secure XPC
            // decoding already rejects malformed transport objects. Decoding
            // the typed payload rebuilds the Mihomo document through the
            // privileged allowlist instead of accepting executable YAML.
            try configuration.validate()
            _ = try MihomoPrivilegedEnvelope.decodeRuntimeConfiguration(
                from: configuration.payload
            )
        } catch {
            reply(nil, TunHelperRemoteError.invalidConfigurationEnvelope(error))
            return
        }

        // No journal, process, route, or DNS state may change before a fully
        // recoverable single-owner backend is installed.
        reply(nil, TunHelperRemoteError.backendUnavailable())
    }

    func stopSession(
        reply: @escaping (TunHelperStatusSnapshot?, NSError?) -> Void
    ) {
        reply(nil, TunHelperRemoteError.backendUnavailable())
    }

    func setRoutingMode(
        _ routingMode: TunHelperRoutingMode,
        reply: @escaping (TunHelperStatusSnapshot?, NSError?) -> Void
    ) {
        guard
            TunHelperRoutingMode.allCases.contains(where: {
                $0.rawValue == routingMode.rawValue
            })
        else {
            reply(nil, TunHelperRemoteError.invalidRoutingMode())
            return
        }
        reply(nil, TunHelperRemoteError.backendUnavailable())
    }

    func recover(
        reply: @escaping (TunHelperStatusSnapshot?, NSError?) -> Void
    ) {
        // Refuse even when no journal is present: reporting mutation success
        // without a recovery backend would make lifecycle coordination unsafe.
        reply(nil, TunHelperRemoteError.backendUnavailable())
    }

    private func statusSnapshot() throws -> TunHelperStatusSnapshot {
        guard let journal = try journalController.currentJournal() else {
            return try TunHelperStatusSnapshot(
                supportedFeatures: 0,
                runtimeState: .unavailable,
                runtimeVersion: nil,
                sessionPhase: .inactive,
                sessionIdentifier: nil,
                sessionOwnedByCaller: false,
                recoveryRequired: false,
                routingMode: nil,
                observedAt: now(),
                lastError: nil
            )
        }

        let ownedByCaller = journal.ownerUserIdentifier == clientUserIdentifier
        let phase: TunHelperSessionPhase
        let recoveryRequired: Bool
        if journal.recoveryPending {
            // A persisted active/cleanup-required journal is evidence that a
            // concrete backend must reconcile state; it is not proof that a
            // live Mihomo process or route currently exists.
            phase = .recoveryRequired
            recoveryRequired = true
        } else {
            recoveryRequired = false
            switch journal.phase {
            case .stopped:
                phase = .inactive
            case .failed:
                phase = .failed
            case .preparing, .running, .restoring:
                // These phases are recovery-pending by journal definition.
                phase = .recoveryRequired
            }
        }

        let exposesSession = ownedByCaller && phase != .inactive
        return try TunHelperStatusSnapshot(
            supportedFeatures: 0,
            runtimeState: .unavailable,
            runtimeVersion: nil,
            sessionPhase: phase,
            sessionIdentifier: exposesSession ? journal.sessionIdentifier : nil,
            sessionOwnedByCaller: exposesSession,
            recoveryRequired: recoveryRequired,
            routingMode: nil,
            observedAt: now(),
            lastError: exposesSession ? journal.lastError : nil
        )
    }
}
