import Foundation
import XCTest

@testable import ViaSixApp
@testable import ViaSixPrivilegedProtocol

final class TunHelperClientTests: XCTestCase {
    func testProtocolV1HelperIsRejectedBeforeAnyV2Selector() async throws {
        let remote = try FakeTunHelperRemote(protocolVersion: 1)
        let factory = FakeTunHelperConnectionFactory(remote: remote)
        let client = TunHelperClient(connectionFactory: { factory.makeConnection() })

        do {
            _ = try await client.stopSession()
            XCTFail("Expected the v1 helper to be rejected")
        } catch {
            XCTAssertEqual(
                error as? TunHelperClientError,
                .incompatibleProtocol(expected: 2, actual: 1)
            )
        }

        XCTAssertEqual(remote.events, [.probe])
    }

    func testOutdatedImplementationIsRejectedBeforeAnyMutation() async throws {
        let remote = try FakeTunHelperRemote(
            protocolVersion: TunHelperConstants.protocolVersion,
            implementationVersion: 4
        )
        let factory = FakeTunHelperConnectionFactory(remote: remote)
        let client = TunHelperClient(connectionFactory: { factory.makeConnection() })

        do {
            _ = try await client.stopSession()
            XCTFail("Expected the outdated helper to be rejected")
        } catch {
            XCTAssertEqual(
                error as? TunHelperClientError,
                .incompatibleImplementation(minimum: 5, actual: 4)
            )
        }

        XCTAssertEqual(remote.events, [.probe])
    }

    func testCompatibleProbeIsCachedForConnectionGeneration() async throws {
        let remote = try FakeTunHelperRemote(protocolVersion: 2)
        let factory = FakeTunHelperConnectionFactory(remote: remote)
        let client = TunHelperClient(connectionFactory: { factory.makeConnection() })

        _ = try await client.status()
        _ = try await client.status()
        _ = try await client.setRoutingMode(.global)

        XCTAssertEqual(remote.events, [.probe, .status, .status, .setRoutingMode])
        XCTAssertEqual(factory.connectionCount, 1)
    }

    func testInvalidationForcesNewGenerationHandshake() async throws {
        let remote = try FakeTunHelperRemote(protocolVersion: 2)
        let factory = FakeTunHelperConnectionFactory(remote: remote)
        let client = TunHelperClient(connectionFactory: { factory.makeConnection() })

        _ = try await client.status()
        await client.invalidate()
        _ = try await client.status()

        XCTAssertEqual(remote.events, [.probe, .status, .probe, .status])
        XCTAssertEqual(factory.connectionCount, 2)
    }

    func testMutationTimeoutReportsUnknownOutcome() async throws {
        let remote = try FakeTunHelperRemote(
            protocolVersion: 2,
            ignoredReplies: [.stopSession]
        )
        let factory = FakeTunHelperConnectionFactory(remote: remote)
        let shortTimeouts = TunHelperClientTimeouts(
            status: .seconds(1),
            modeChange: .milliseconds(10),
            sessionMutation: .milliseconds(10),
            installation: .milliseconds(10)
        )
        let client = TunHelperClient(
            connectionFactory: { factory.makeConnection() },
            timeouts: shortTimeouts
        )

        do {
            _ = try await client.stopSession()
            XCTFail("Expected the mutation result to become unknown")
        } catch {
            XCTAssertEqual(error as? TunHelperClientError, .operationOutcomeUnknown)
        }

        XCTAssertEqual(remote.events, [.probe, .stopSession])
    }

    func testMutationTransportFailureReportsUnknownOutcome() async throws {
        let remote = try FakeTunHelperRemote(
            protocolVersion: 2,
            transportFailureEvents: [.stopSession]
        )
        let factory = FakeTunHelperConnectionFactory(remote: remote)
        let client = TunHelperClient(connectionFactory: { factory.makeConnection() })

        do {
            _ = try await client.stopSession()
            XCTFail("Expected the mutation result to become unknown")
        } catch {
            XCTAssertEqual(error as? TunHelperClientError, .operationOutcomeUnknown)
        }

        XCTAssertEqual(remote.events, [.probe, .stopSession])
    }

    func testMutationNilReplyReportsUnknownOutcome() async throws {
        let remote = try FakeTunHelperRemote(
            protocolVersion: 2,
            nilReplyEvents: [.stopSession]
        )
        let factory = FakeTunHelperConnectionFactory(remote: remote)
        let client = TunHelperClient(connectionFactory: { factory.makeConnection() })

        do {
            _ = try await client.stopSession()
            XCTFail("Expected the mutation result to become unknown")
        } catch {
            XCTAssertEqual(error as? TunHelperClientError, .operationOutcomeUnknown)
        }

        XCTAssertEqual(remote.events, [.probe, .stopSession])
    }

    func testStatusNilReplyRemainsInvalidStatusError() async throws {
        let remote = try FakeTunHelperRemote(
            protocolVersion: 2,
            nilReplyEvents: [.status]
        )
        let factory = FakeTunHelperConnectionFactory(remote: remote)
        let client = TunHelperClient(connectionFactory: { factory.makeConnection() })

        do {
            _ = try await client.status()
            XCTFail("Expected invalid status response")
        } catch {
            XCTAssertEqual(error as? TunHelperClientError, .invalidStatusSnapshot)
        }

        XCTAssertEqual(remote.events, [.probe, .status])
    }
}

private final class FakeTunHelperConnectionFactory: @unchecked Sendable {
    private let lock = NSLock()
    private let remote: FakeTunHelperRemote
    private var connections: [FakeTunHelperConnection] = []

    init(remote: FakeTunHelperRemote) {
        self.remote = remote
    }

    var connectionCount: Int {
        lock.withLock { connections.count }
    }

    func makeConnection() -> any TunHelperConnection {
        lock.withLock {
            let connection = FakeTunHelperConnection(remote: remote)
            connections.append(connection)
            return connection
        }
    }
}

private final class FakeTunHelperConnection: TunHelperConnection, @unchecked Sendable {
    var interruptionHandler: (() -> Void)?
    var invalidationHandler: (() -> Void)?

    private let remote: FakeTunHelperRemote

    init(remote: FakeTunHelperRemote) {
        self.remote = remote
    }

    func remoteObjectProxyWithErrorHandler(
        _ handler: @escaping (any Error) -> Void
    ) -> Any {
        remote.installTransportErrorHandler(handler)
        return remote
    }

    func activate() {}

    func invalidate() {}
}

private final class FakeTunHelperRemote: NSObject, TunHelperXPCProtocol, @unchecked Sendable {
    enum Event: Hashable {
        case probe
        case status
        case installOrRepairRuntime
        case startSession
        case stopSession
        case setRoutingMode
        case recover
    }

    private let lock = NSLock()
    private let protocolVersion: Int
    private let implementationVersion: Int
    private let snapshot: TunHelperStatusSnapshot
    private let ignoredReplies: Set<Event>
    private let nilReplyEvents: Set<Event>
    private let transportFailureEvents: Set<Event>
    private var recordedEvents: [Event] = []
    private var transportErrorHandler: ((any Error) -> Void)?

    init(
        protocolVersion: Int,
        implementationVersion: Int = TunHelperConstants.implementationVersion,
        ignoredReplies: Set<Event> = [],
        nilReplyEvents: Set<Event> = [],
        transportFailureEvents: Set<Event> = []
    ) throws {
        self.protocolVersion = protocolVersion
        self.implementationVersion = implementationVersion
        self.ignoredReplies = ignoredReplies
        self.nilReplyEvents = nilReplyEvents
        self.transportFailureEvents = transportFailureEvents
        self.snapshot = try TunHelperStatusSnapshot(
            supportedFeatures: 0,
            runtimeState: .unavailable,
            runtimeVersion: nil,
            sessionPhase: .inactive,
            sessionIdentifier: nil,
            sessionOwnedByCaller: false,
            recoveryRequired: false,
            routingMode: nil,
            lastError: nil
        )
    }

    var events: [Event] {
        lock.withLock { recordedEvents }
    }

    func installTransportErrorHandler(
        _ handler: @escaping (any Error) -> Void
    ) {
        lock.withLock {
            transportErrorHandler = handler
        }
    }

    func probe(
        reply: @escaping (Int, Int, UInt64, Bool, NSError?) -> Void
    ) {
        record(.probe)
        reply(protocolVersion, implementationVersion, 0, false, nil)
    }

    func status(
        reply: @escaping (TunHelperStatusSnapshot?, NSError?) -> Void
    ) {
        respond(to: .status, reply: reply)
    }

    func installOrRepairRuntime(
        reply: @escaping (TunHelperStatusSnapshot?, NSError?) -> Void
    ) {
        respond(to: .installOrRepairRuntime, reply: reply)
    }

    func startSession(
        configuration: TunConfigurationEnvelope,
        reply: @escaping (TunHelperStatusSnapshot?, NSError?) -> Void
    ) {
        _ = configuration
        respond(to: .startSession, reply: reply)
    }

    func stopSession(
        reply: @escaping (TunHelperStatusSnapshot?, NSError?) -> Void
    ) {
        respond(to: .stopSession, reply: reply)
    }

    func setRoutingMode(
        _ routingMode: TunHelperRoutingMode,
        reply: @escaping (TunHelperStatusSnapshot?, NSError?) -> Void
    ) {
        _ = routingMode
        respond(to: .setRoutingMode, reply: reply)
    }

    func recover(
        reply: @escaping (TunHelperStatusSnapshot?, NSError?) -> Void
    ) {
        respond(to: .recover, reply: reply)
    }

    private func respond(
        to event: Event,
        reply: (TunHelperStatusSnapshot?, NSError?) -> Void
    ) {
        record(event)
        if transportFailureEvents.contains(event) {
            let handler = lock.withLock { transportErrorHandler }
            handler?(NSError(domain: "test.transport", code: 1))
            return
        }
        guard !ignoredReplies.contains(event) else { return }
        if nilReplyEvents.contains(event) {
            reply(nil, nil)
            return
        }
        reply(snapshot, nil)
    }

    private func record(_ event: Event) {
        lock.withLock {
            recordedEvents.append(event)
        }
    }
}
