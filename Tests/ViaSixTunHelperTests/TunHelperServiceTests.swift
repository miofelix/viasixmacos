import Darwin
import Foundation
import XCTest

@testable import ViaSixMihomoConfig
@testable import ViaSixPrivilegedProtocol
@testable import ViaSixTunHelper
@testable import ViaSixTunHelperSupport

final class TunHelperServiceTests: XCTestCase {
    func testProbePreservesV1HandshakeShapeAndReportsRecovery() throws {
        try withController { controller in
            let userIdentifier = UInt32(geteuid())
            let service = TunHelperService(
                clientUserIdentifier: userIdentifier,
                journalController: controller
            )

            var response = probe(from: service)
            XCTAssertEqual(response.protocolVersion, 2)
            XCTAssertEqual(response.implementationVersion, 2)
            XCTAssertEqual(response.supportedFeatures, 0)
            XCTAssertFalse(response.recoveryPending)
            XCTAssertNil(response.error)

            _ = try controller.begin(ownerUserIdentifier: userIdentifier)
            response = probe(from: service)
            XCTAssertEqual(response.protocolVersion, 2)
            XCTAssertEqual(response.implementationVersion, 2)
            XCTAssertEqual(response.supportedFeatures, 0)
            XCTAssertTrue(response.recoveryPending)
            XCTAssertNil(response.error)
        }
    }

    func testStatusReportsInactiveUnavailableBackendWithoutCapabilities() throws {
        try withController { controller in
            let observedAt = Date(timeIntervalSince1970: 1_700_000_000)
            let service = TunHelperService(
                clientUserIdentifier: UInt32(geteuid()),
                journalController: controller,
                now: { observedAt }
            )

            let response = status(from: service)
            XCTAssertNil(response.error)
            let snapshot = try XCTUnwrap(response.snapshot)
            XCTAssertEqual(snapshot.protocolVersion, 2)
            XCTAssertEqual(snapshot.features, [])
            XCTAssertEqual(snapshot.runtimeState, .unavailable)
            XCTAssertEqual(snapshot.sessionPhase, .inactive)
            XCTAssertNil(snapshot.sessionIdentifier)
            XCTAssertFalse(snapshot.sessionOwnedByCaller)
            XCTAssertFalse(snapshot.recoveryRequired)
            XCTAssertEqual(snapshot.observedAt, observedAt)
        }
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

    func testEveryMutationFailsClosedAndPreservesJournal() throws {
        try withController { controller in
            let userIdentifier = UInt32(geteuid())
            _ = try controller.begin(ownerUserIdentifier: userIdentifier)
            let before = try XCTUnwrap(controller.currentJournal())
            let service = TunHelperService(
                clientUserIdentifier: userIdentifier,
                journalController: controller
            )
            let payload = try MihomoPrivilegedEnvelope.encode(
                server: nil,
                options: MihomoRuntimeOptions(
                    routingMode: .direct,
                    tun: MihomoTunConfiguration()
                )
            )
            let envelope = try TunConfigurationEnvelope(payload: payload)

            let responses = [
                mutation { service.installOrRepairRuntime(reply: $0) },
                mutation { service.startSession(configuration: envelope, reply: $0) },
                mutation { service.stopSession(reply: $0) },
                mutation { service.setRoutingMode(.rule, reply: $0) },
                mutation { service.recover(reply: $0) },
            ]
            for response in responses {
                XCTAssertNil(response.snapshot)
                XCTAssertEqual(response.error?.domain, TunHelperConstants.errorDomain)
                XCTAssertEqual(
                    response.error?.code,
                    TunHelperErrorCode.backendUnavailable.rawValue
                )
            }
            XCTAssertEqual(try controller.currentJournal(), before)
        }
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
