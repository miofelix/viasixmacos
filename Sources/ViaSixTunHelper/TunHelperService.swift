import Foundation
import ViaSixMihomoConfig
import ViaSixPrivilegedProtocol
import ViaSixTunHelperSupport

final class TunHelperService: NSObject, TunHelperXPCProtocol {
    private let clientUserIdentifier: UInt32
    private let backend: any TunSessionBackend
    private let now: @Sendable () -> Date

    init(
        clientUserIdentifier: UInt32,
        backend: any TunSessionBackend,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.clientUserIdentifier = clientUserIdentifier
        self.backend = backend
        self.now = now
    }

    convenience init(
        clientUserIdentifier: UInt32,
        journalController: TunSessionJournalController,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.init(
            clientUserIdentifier: clientUserIdentifier,
            backend: PrivilegedTunBackend(journalController: journalController),
            now: now
        )
    }

    func probe(
        reply: @escaping (Int, Int, UInt64, Bool, NSError?) -> Void
    ) {
        do {
            let snapshot = try backend.probe()
            reply(
                TunHelperConstants.protocolVersion,
                TunHelperConstants.implementationVersion,
                snapshot.supportedFeatures.rawValue,
                snapshot.recoveryRequired,
                nil
            )
        } catch {
            reply(
                TunHelperConstants.protocolVersion,
                TunHelperConstants.implementationVersion,
                0,
                false,
                remoteError(for: error)
            )
        }
    }

    func status(
        reply: @escaping (TunHelperStatusSnapshot?, NSError?) -> Void
    ) {
        respond(reply) {
            try backend.status()
        }
    }

    func installOrRepairRuntime(
        reply: @escaping (TunHelperStatusSnapshot?, NSError?) -> Void
    ) {
        respond(reply) {
            try backend.installOrRepairRuntime()
        }
    }

    func startSession(
        configuration: TunConfigurationEnvelope,
        reply: @escaping (TunHelperStatusSnapshot?, NSError?) -> Void
    ) {
        do {
            try configuration.validate()
            let plan = try MihomoPrivilegedEnvelope.decodeRuntimePlan(
                from: configuration.payload
            )
            guard plan.options.externalController != nil else {
                throw MihomoConfigurationError.invalidControllerSecret
            }
            respond(reply) {
                try backend.startSession(
                    plan: plan,
                    ownerUserIdentifier: clientUserIdentifier
                )
            }
        } catch {
            reply(nil, TunHelperRemoteError.invalidConfigurationEnvelope(error))
        }
    }

    func stopSession(
        reply: @escaping (TunHelperStatusSnapshot?, NSError?) -> Void
    ) {
        respond(reply) {
            try backend.stopSession(requestingUserIdentifier: clientUserIdentifier)
        }
    }

    func setRoutingMode(
        _ routingMode: TunHelperRoutingMode,
        reply: @escaping (TunHelperStatusSnapshot?, NSError?) -> Void
    ) {
        guard TunHelperRoutingMode.allCases.contains(routingMode) else {
            reply(nil, TunHelperRemoteError.invalidRoutingMode())
            return
        }
        respond(reply) {
            try backend.setRoutingMode(
                routingMode,
                requestingUserIdentifier: clientUserIdentifier
            )
        }
    }

    func recover(
        reply: @escaping (TunHelperStatusSnapshot?, NSError?) -> Void
    ) {
        respond(reply) {
            try backend.recover(requestingUserIdentifier: clientUserIdentifier)
        }
    }

    private func respond(
        _ reply: @escaping (TunHelperStatusSnapshot?, NSError?) -> Void,
        _ operation: () throws -> TunBackendSnapshot
    ) {
        do {
            reply(try makeSnapshot(from: operation()), nil)
        } catch {
            reply(nil, remoteError(for: error))
        }
    }

    private func makeSnapshot(from snapshot: TunBackendSnapshot) throws -> TunHelperStatusSnapshot {
        let ownsSession =
            snapshot.ownerUserIdentifier == clientUserIdentifier
            && snapshot.sessionPhase != .inactive
        let phase = snapshot.sessionPhase
        return try TunHelperStatusSnapshot(
            supportedFeatures: snapshot.supportedFeatures.rawValue,
            runtimeState: snapshot.runtimeState,
            runtimeVersion: snapshot.runtimeVersion,
            sessionPhase: phase,
            sessionIdentifier: ownsSession ? snapshot.sessionIdentifier : nil,
            sessionOwnedByCaller: ownsSession,
            recoveryRequired: snapshot.recoveryRequired,
            routingMode: ownsSession ? snapshot.routingMode : nil,
            observedAt: now(),
            lastError: ownsSession ? snapshot.lastError : nil
        )
    }

    private func remoteError(for error: any Error) -> NSError {
        if let error = error as? PrivilegedTunBackendError {
            let code: TunHelperErrorCode =
                switch error {
                case .runtimeNotReady: .runtimeUnavailable
                case .sessionAlreadyActive: .sessionBusy
                case .sessionOwnedByAnotherUser: .sessionNotOwned
                default: .operationFailed
                }
            return TunHelperRemoteError.operationFailed(error, code: code)
        }
        return TunHelperRemoteError.operationFailed(error)
    }
}
