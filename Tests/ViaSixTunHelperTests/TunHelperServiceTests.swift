import Darwin
import Foundation
import XCTest

@testable import ViaSixMihomoConfig
@testable import ViaSixPrivilegedProtocol
@testable import ViaSixTunHelper
@testable import ViaSixTunHelperSupport

final class TunHelperServiceTests: XCTestCase {
    func testProbePreservesV1HandshakeShapeAndReportsRecovery() throws {
        let backend = FakeTunSessionBackend()
        let service = TunHelperService(
            clientUserIdentifier: UInt32(geteuid()),
            backend: backend
        )

        var response = probe(from: service)
        XCTAssertEqual(response.protocolVersion, TunHelperConstants.protocolVersion)
        XCTAssertEqual(
            response.implementationVersion,
            TunHelperConstants.implementationVersion
        )
        XCTAssertEqual(response.supportedFeatures, backend.features.rawValue)
        XCTAssertFalse(response.recoveryPending)
        XCTAssertNil(response.error)

        backend.recoveryRequired = true
        response = probe(from: service)
        XCTAssertEqual(response.protocolVersion, TunHelperConstants.protocolVersion)
        XCTAssertEqual(
            response.implementationVersion,
            TunHelperConstants.implementationVersion
        )
        XCTAssertEqual(response.supportedFeatures, backend.features.rawValue)
        XCTAssertTrue(response.recoveryPending)
        XCTAssertNil(response.error)
    }

    func testStatusReportsBackendCapabilitiesAndRuntimeState() throws {
        let observedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let backend = FakeTunSessionBackend()
        backend.runtimeState = .notInstalled
        let service = TunHelperService(
            clientUserIdentifier: UInt32(geteuid()),
            backend: backend,
            now: { observedAt }
        )

        let response = status(from: service)
        XCTAssertNil(response.error)
        let snapshot = try XCTUnwrap(response.snapshot)
        XCTAssertEqual(snapshot.protocolVersion, TunHelperConstants.protocolVersion)
        XCTAssertEqual(snapshot.features, backend.features)
        XCTAssertEqual(snapshot.runtimeState, .notInstalled)
        XCTAssertEqual(snapshot.sessionPhase, .inactive)
        XCTAssertNil(snapshot.sessionIdentifier)
        XCTAssertFalse(snapshot.sessionOwnedByCaller)
        XCTAssertFalse(snapshot.recoveryRequired)
        XCTAssertEqual(snapshot.observedAt, observedAt)
    }

    func testStatusTreatsPersistedActiveJournalAsRecoveryEvidence() throws {
        try withController { controller in
            let userIdentifier = UInt32(geteuid())
            let journal = try controller.begin(ownerUserIdentifier: userIdentifier)
            let service = TunHelperService(
                clientUserIdentifier: userIdentifier,
                journalController: controller
            )

            let response = status(from: service)
            XCTAssertNil(response.error)
            let snapshot = try XCTUnwrap(response.snapshot)
            XCTAssertEqual(snapshot.sessionPhase, .recoveryRequired)
            XCTAssertEqual(snapshot.sessionIdentifier, journal.sessionIdentifier)
            XCTAssertTrue(snapshot.sessionOwnedByCaller)
            XCTAssertTrue(snapshot.recoveryRequired)
            XCTAssertNil(snapshot.routingMode)
        }
    }

    func testStatusRedactsAnotherUsersPersistedSession() throws {
        try withController { controller in
            let owner = UInt32(geteuid())
            _ = try controller.begin(ownerUserIdentifier: owner)
            let otherUser = owner == UInt32.max ? owner - 1 : owner + 1
            let service = TunHelperService(
                clientUserIdentifier: otherUser,
                journalController: controller
            )

            let response = status(from: service)
            XCTAssertNil(response.error)
            let snapshot = try XCTUnwrap(response.snapshot)
            XCTAssertEqual(snapshot.sessionPhase, .recoveryRequired)
            XCTAssertFalse(snapshot.sessionOwnedByCaller)
            XCTAssertTrue(snapshot.recoveryRequired)
            XCTAssertNil(snapshot.sessionIdentifier)
            XCTAssertNil(snapshot.routingMode)
            XCTAssertNil(snapshot.lastError)
        }
    }

    func testRecoverRejectsAnotherUsersPersistedSession() throws {
        try withController { controller in
            let owner = UInt32(geteuid())
            _ = try controller.begin(ownerUserIdentifier: owner)
            let otherUser = owner == UInt32.max ? owner - 1 : owner + 1
            let service = TunHelperService(
                clientUserIdentifier: otherUser,
                journalController: controller
            )

            let response = mutation { service.recover(reply: $0) }

            XCTAssertNil(response.snapshot)
            XCTAssertEqual(response.error?.domain, TunHelperConstants.errorDomain)
            XCTAssertEqual(
                response.error?.code,
                TunHelperErrorCode.sessionNotOwned.rawValue
            )
            XCTAssertNotNil(try controller.currentJournal())
        }
    }

    func testMutationsUseTypedBackendAndMapRestartRequirement() throws {
        let userIdentifier = UInt32(geteuid())
        let backend = FakeTunSessionBackend()
        let service = TunHelperService(
            clientUserIdentifier: userIdentifier,
            backend: backend
        )
        let payload = try MihomoPrivilegedEnvelope.encode(
            server: nil,
            options: MihomoRuntimeOptions(
                routingMode: .direct,
                externalController: MihomoExternalControllerConfiguration(
                    port: 9_090,
                    secret: "test-controller-secret"
                ),
                tun: MihomoTunConfiguration()
            )
        )
        let envelope = try TunConfigurationEnvelope(payload: payload)

        var response = mutation { service.installOrRepairRuntime(reply: $0) }
        XCTAssertNil(response.error)
        XCTAssertEqual(response.snapshot?.runtimeState, .ready)

        response = mutation { service.startSession(configuration: envelope, reply: $0) }
        XCTAssertNil(response.error)
        XCTAssertEqual(response.snapshot?.sessionPhase, .running)
        XCTAssertTrue(response.snapshot?.sessionOwnedByCaller == true)
        XCTAssertEqual(backend.startedPlan?.options.routingMode, .direct)
        XCTAssertNotNil(backend.startedPlan?.options.tun)

        response = mutation { service.setRoutingMode(.rule, reply: $0) }
        XCTAssertNil(response.snapshot)
        XCTAssertEqual(response.error?.domain, TunHelperConstants.errorDomain)
        XCTAssertEqual(response.error?.code, TunHelperErrorCode.operationFailed.rawValue)

        response = mutation { service.stopSession(reply: $0) }
        XCTAssertNil(response.error)
        XCTAssertEqual(response.snapshot?.sessionPhase, .inactive)

        backend.recoveryRequired = true
        response = mutation { service.recover(reply: $0) }
        XCTAssertNil(response.error)
        XCTAssertFalse(response.snapshot?.recoveryRequired == true)
    }

    func testStartRejectsBinaryPropertyListThatIsNotTypedMihomoConfiguration() throws {
        try withController { controller in
            let service = TunHelperService(
                clientUserIdentifier: UInt32(geteuid()),
                journalController: controller
            )
            let payload = try PropertyListSerialization.data(
                fromPropertyList: ["schemaVersion": 1],
                format: .binary,
                options: 0
            )
            let envelope = try TunConfigurationEnvelope(payload: payload)

            let response = mutation {
                service.startSession(configuration: envelope, reply: $0)
            }

            XCTAssertNil(response.snapshot)
            XCTAssertEqual(response.error?.domain, TunHelperConstants.errorDomain)
            XCTAssertEqual(
                response.error?.code,
                TunHelperErrorCode.invalidConfigurationEnvelope.rawValue
            )
            XCTAssertNil(try controller.currentJournal())
        }
    }

    private func status(
        from service: TunHelperService
    ) -> (snapshot: TunHelperStatusSnapshot?, error: NSError?) {
        mutation { service.status(reply: $0) }
    }

    private func probe(
        from service: TunHelperService
    ) -> (
        protocolVersion: Int,
        implementationVersion: Int,
        supportedFeatures: UInt64,
        recoveryPending: Bool,
        error: NSError?
    ) {
        var result: (Int, Int, UInt64, Bool, NSError?)?
        service.probe { protocolVersion, implementationVersion, features, recovery, error in
            result = (protocolVersion, implementationVersion, features, recovery, error)
        }
        return result ?? (0, 0, 0, false, NSError(domain: "test.no-reply", code: 1))
    }

    private func mutation(
        _ operation: (@escaping (TunHelperStatusSnapshot?, NSError?) -> Void) -> Void
    ) -> (snapshot: TunHelperStatusSnapshot?, error: NSError?) {
        var result: (TunHelperStatusSnapshot?, NSError?)?
        operation { snapshot, error in
            result = (snapshot, error)
        }
        return result ?? (nil, NSError(domain: "test.no-reply", code: 1))
    }

    private func withController(
        _ body: (TunSessionJournalController) throws -> Void
    ) throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ViaSix-TunHelperService-\(UUID().uuidString)",
            isDirectory: true
        )
        let root = parent.appendingPathComponent("State", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: parent) }

        let controller = TunSessionJournalController(
            store: TunSessionJournalStore(
                rootDirectoryURL: root,
                expectedOwnerUserIdentifier: UInt32(geteuid()),
                expectedOwnerGroupIdentifier: UInt32(getegid())
            )
        )
        try body(controller)
    }
}

private final class FakeTunSessionBackend: TunSessionBackend, @unchecked Sendable {
    let features: TunHelperFeature = [
        .fixedRuntimeManagement,
        .sessionLifecycle,
        .recovery,
        .ipv4,
        .ipv6,
        .systemRouting,
        .loopbackPrevention,
        .dnsManagement,
        .networkChangeRecovery,
        .loopbackController,
    ]

    var runtimeState: TunPrivilegedRuntimeState = .ready
    var sessionPhase: TunHelperSessionPhase = .inactive
    var sessionIdentifier: UUID?
    var ownerUserIdentifier: UInt32?
    var recoveryRequired = false
    var routingMode: TunHelperRoutingMode?
    var lastError: String?
    var startedPlan: MihomoPrivilegedRuntimePlan?

    func probe() throws -> TunBackendSnapshot { snapshot() }
    func status() throws -> TunBackendSnapshot { snapshot() }

    func installOrRepairRuntime() throws -> TunBackendSnapshot {
        runtimeState = .ready
        return snapshot()
    }

    func startSession(
        plan: MihomoPrivilegedRuntimePlan,
        ownerUserIdentifier: UInt32
    ) throws -> TunBackendSnapshot {
        startedPlan = plan
        sessionPhase = .running
        sessionIdentifier = UUID()
        self.ownerUserIdentifier = ownerUserIdentifier
        routingMode =
            switch plan.options.routingMode {
            case .rule: .rule
            case .global: .global
            case .direct: .direct
            }
        return snapshot()
    }

    func stopSession(requestingUserIdentifier: UInt32) throws -> TunBackendSnapshot {
        guard ownerUserIdentifier == requestingUserIdentifier else {
            throw PrivilegedTunBackendError.sessionOwnedByAnotherUser
        }
        sessionPhase = .inactive
        sessionIdentifier = nil
        ownerUserIdentifier = nil
        routingMode = nil
        return snapshot()
    }

    func setRoutingMode(
        _ routingMode: TunHelperRoutingMode,
        requestingUserIdentifier: UInt32
    ) throws -> TunBackendSnapshot {
        _ = routingMode
        _ = requestingUserIdentifier
        throw PrivilegedTunBackendError.routingModeRequiresRestart
    }

    func recover(requestingUserIdentifier: UInt32) throws -> TunBackendSnapshot {
        guard ownerUserIdentifier == nil || ownerUserIdentifier == requestingUserIdentifier else {
            throw PrivilegedTunBackendError.sessionOwnedByAnotherUser
        }
        recoveryRequired = false
        sessionPhase = .inactive
        sessionIdentifier = nil
        ownerUserIdentifier = nil
        routingMode = nil
        return snapshot()
    }

    private func snapshot() -> TunBackendSnapshot {
        TunBackendSnapshot(
            supportedFeatures: features,
            runtimeState: runtimeState,
            runtimeVersion: runtimeState == .ready ? "1.19.29" : nil,
            sessionPhase: sessionPhase,
            sessionIdentifier: sessionIdentifier,
            ownerUserIdentifier: ownerUserIdentifier,
            recoveryRequired: recoveryRequired,
            routingMode: routingMode,
            lastError: lastError
        )
    }
}
