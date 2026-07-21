import Foundation
import ViaSixPrivilegedProtocol

protocol TunHelperConnection: AnyObject, Sendable {
    var interruptionHandler: (() -> Void)? { get set }
    var invalidationHandler: (() -> Void)? { get set }

    func remoteObjectProxyWithErrorHandler(
        _ handler: @escaping (any Error) -> Void
    ) -> Any
    func activate()
    func invalidate()
}

private final class LiveTunHelperConnection: TunHelperConnection, @unchecked Sendable {
    private let connection: NSXPCConnection

    init(connection: NSXPCConnection) {
        self.connection = connection
    }

    var interruptionHandler: (() -> Void)? {
        get { connection.interruptionHandler }
        set { connection.interruptionHandler = newValue }
    }

    var invalidationHandler: (() -> Void)? {
        get { connection.invalidationHandler }
        set { connection.invalidationHandler = newValue }
    }

    func remoteObjectProxyWithErrorHandler(
        _ handler: @escaping (any Error) -> Void
    ) -> Any {
        connection.remoteObjectProxyWithErrorHandler(handler)
    }

    func activate() {
        connection.activate()
    }

    func invalidate() {
        connection.invalidate()
    }
}

typealias TunHelperConnectionFactory = @Sendable () throws -> any TunHelperConnection

struct TunHelperClientTimeouts: Sendable {
    let status: Duration
    let modeChange: Duration
    let sessionMutation: Duration
    let installation: Duration

    static let live = Self(
        status: .seconds(5),
        modeChange: .seconds(15),
        sessionMutation: .seconds(30),
        installation: .seconds(120)
    )
}

actor TunHelperClient {
    private let connectionFactory: TunHelperConnectionFactory
    private let timeouts: TunHelperClientTimeouts
    private var connection: (any TunHelperConnection)?
    private var connectionGeneration: UUID?
    private var compatibleProbe: (generation: UUID, result: TunHelperProbeResult)?

    init() {
        connectionFactory = Self.makeLiveConnection
        timeouts = .live
    }

    init(
        connectionFactory: @escaping TunHelperConnectionFactory,
        timeouts: TunHelperClientTimeouts = .live
    ) {
        self.connectionFactory = connectionFactory
        self.timeouts = timeouts
    }

    func status() async throws -> TunHelperStatusSnapshot {
        try await perform(
            timeout: timeouts.status,
            timeoutError: .timedOut,
            mutationOutcomeMayBeUnknown: false
        ) {
            helper,
            reply in
            helper.status(reply: reply)
        }
    }

    func installOrRepairRuntime() async throws -> TunHelperStatusSnapshot {
        try await perform(
            timeout: timeouts.installation,
            timeoutError: .operationOutcomeUnknown,
            mutationOutcomeMayBeUnknown: true
        ) { helper, reply in
            helper.installOrRepairRuntime(reply: reply)
        }
    }

    func startSession(
        configuration: TunConfigurationEnvelope
    ) async throws -> TunHelperStatusSnapshot {
        try await perform(
            timeout: timeouts.sessionMutation,
            timeoutError: .operationOutcomeUnknown,
            mutationOutcomeMayBeUnknown: true
        ) { helper, reply in
            helper.startSession(configuration: configuration, reply: reply)
        }
    }

    func stopSession() async throws -> TunHelperStatusSnapshot {
        try await perform(
            timeout: timeouts.sessionMutation,
            timeoutError: .operationOutcomeUnknown,
            mutationOutcomeMayBeUnknown: true
        ) { helper, reply in
            helper.stopSession(reply: reply)
        }
    }

    func setRoutingMode(
        _ routingMode: TunHelperRoutingMode
    ) async throws -> TunHelperStatusSnapshot {
        try await perform(
            timeout: timeouts.modeChange,
            timeoutError: .operationOutcomeUnknown,
            mutationOutcomeMayBeUnknown: true
        ) { helper, reply in
            helper.setRoutingMode(routingMode, reply: reply)
        }
    }

    func recover() async throws -> TunHelperStatusSnapshot {
        try await perform(
            timeout: timeouts.sessionMutation,
            timeoutError: .operationOutcomeUnknown,
            mutationOutcomeMayBeUnknown: true
        ) { helper, reply in
            helper.recover(reply: reply)
        }
    }

    func invalidate() {
        let staleConnection = connection
        connection = nil
        connectionGeneration = nil
        compatibleProbe = nil
        staleConnection?.interruptionHandler = nil
        staleConnection?.invalidationHandler = nil
        staleConnection?.invalidate()
    }

    private func perform(
        timeout: Duration,
        timeoutError: TunHelperClientError,
        mutationOutcomeMayBeUnknown: Bool,
        _ request:
            @escaping (
                _ helper: TunHelperXPCProtocol,
                _ reply: @escaping (TunHelperStatusSnapshot?, NSError?) -> Void
            ) -> Void
    ) async throws -> TunHelperStatusSnapshot {
        let (connection, generation) = try connectionForUse()
        _ = try await ensureCompatible(
            connection: connection,
            generation: generation
        )
        return try await withCheckedThrowingContinuation { continuation in
            let gate = ContinuationGate(continuation)
            scheduleTimeout(
                for: gate,
                after: timeout,
                error: timeoutError,
                connectionGeneration: generation
            )

            let remote = connection.remoteObjectProxyWithErrorHandler { [weak self] error in
                let reportedError: any Error =
                    mutationOutcomeMayBeUnknown
                    ? TunHelperClientError.operationOutcomeUnknown : error
                guard gate.resume(throwing: reportedError) else { return }
                Task {
                    await self?.discardConnection(generation: generation)
                }
            }
            guard let helper = remote as? TunHelperXPCProtocol else {
                if gate.resume(throwing: TunHelperClientError.invalidRemoteObject) {
                    discardConnection(generation: generation)
                }
                return
            }

            request(helper) { [weak self] snapshot, error in
                if let error {
                    gate.resume(throwing: error)
                    return
                }
                guard let snapshot else {
                    let error: TunHelperClientError =
                        mutationOutcomeMayBeUnknown
                        ? .operationOutcomeUnknown : .invalidStatusSnapshot
                    if gate.resume(throwing: error) {
                        Task {
                            await self?.discardConnection(generation: generation)
                        }
                    }
                    return
                }
                guard snapshot.protocolVersion == TunHelperConstants.protocolVersion else {
                    let error: TunHelperClientError =
                        mutationOutcomeMayBeUnknown
                        ? .operationOutcomeUnknown
                        : .incompatibleProtocol(
                            expected: TunHelperConstants.protocolVersion,
                            actual: snapshot.protocolVersion
                        )
                    if gate.resume(
                        throwing: error
                    ) {
                        Task {
                            await self?.discardConnection(generation: generation)
                        }
                    }
                    return
                }
                do {
                    try snapshot.validate()
                    gate.resume(returning: snapshot)
                } catch {
                    let error: TunHelperClientError =
                        mutationOutcomeMayBeUnknown
                        ? .operationOutcomeUnknown : .invalidStatusSnapshot
                    if gate.resume(throwing: error) {
                        Task {
                            await self?.discardConnection(generation: generation)
                        }
                    }
                }
            }
        }
    }

    private func ensureCompatible(
        connection: any TunHelperConnection,
        generation: UUID
    ) async throws -> TunHelperProbeResult {
        if let compatibleProbe, compatibleProbe.generation == generation {
            return compatibleProbe.result
        }

        let result: TunHelperProbeResult = try await withCheckedThrowingContinuation {
            continuation in
            let gate = ContinuationGate(continuation)
            scheduleTimeout(
                for: gate,
                after: timeouts.status,
                error: .timedOut,
                connectionGeneration: generation
            )

            let remote = connection.remoteObjectProxyWithErrorHandler { [weak self] error in
                guard gate.resume(throwing: error) else { return }
                Task {
                    await self?.discardConnection(generation: generation)
                }
            }
            guard let helper = remote as? TunHelperXPCProtocol else {
                if gate.resume(throwing: TunHelperClientError.invalidRemoteObject) {
                    discardConnection(generation: generation)
                }
                return
            }

            helper.probe {
                [weak self]
                protocolVersion,
                implementationVersion,
                supportedFeatures,
                recoveryPending,
                error in
                if let error {
                    gate.resume(throwing: error)
                    return
                }
                let result = TunHelperProbeResult(
                    protocolVersion: protocolVersion,
                    implementationVersion: implementationVersion,
                    supportedFeatures: supportedFeatures,
                    recoveryPending: recoveryPending
                )
                guard protocolVersion == TunHelperConstants.protocolVersion else {
                    if gate.resume(
                        throwing: TunHelperClientError.incompatibleProtocol(
                            expected: TunHelperConstants.protocolVersion,
                            actual: protocolVersion
                        )
                    ) {
                        Task {
                            await self?.discardConnection(generation: generation)
                        }
                    }
                    return
                }
                guard
                    implementationVersion
                        >= TunHelperConstants.minimumCompatibleImplementationVersion
                else {
                    if gate.resume(
                        throwing: TunHelperClientError.incompatibleImplementation(
                            minimum: TunHelperConstants.minimumCompatibleImplementationVersion,
                            actual: implementationVersion
                        )
                    ) {
                        Task {
                            await self?.discardConnection(generation: generation)
                        }
                    }
                    return
                }
                gate.resume(returning: result)
            }
        }

        guard connectionGeneration == generation else {
            throw TunHelperClientError.invalidRemoteObject
        }
        compatibleProbe = (generation, result)
        return result
    }

    private func connectionForUse() throws -> (any TunHelperConnection, UUID) {
        if let connection, let connectionGeneration {
            return (connection, connectionGeneration)
        }

        let connection = try connectionFactory()
        let generation = UUID()
        connection.interruptionHandler = { [weak self] in
            Task {
                await self?.discardConnection(generation: generation)
            }
        }
        connection.invalidationHandler = { [weak self] in
            Task {
                await self?.discardConnection(generation: generation)
            }
        }
        connection.activate()
        self.connection = connection
        connectionGeneration = generation
        compatibleProbe = nil
        return (connection, generation)
    }

    private static func makeLiveConnection() throws -> any TunHelperConnection {
        let identity = try CodeSigningInspector.currentProcess(
            expectedIdentifier: TunHelperConstants.appBundleIdentifier
        )
        let helperRequirement: String
        if let teamIdentifier = identity.teamIdentifier {
            helperRequirement = try CodeSigningRequirementBuilder.sameTeamRequirement(
                identifier: TunHelperConstants.helperBundleIdentifier,
                teamIdentifier: teamIdentifier
            )
        } else {
            // The root-owned local service is pinned to its installed helper
            // CDHash. The client intentionally accepts a compatible installed
            // helper across ordinary app rebuilds, mirroring Clash's
            // install-once/service-IPC lifecycle.
            helperRequirement = try CodeSigningRequirementBuilder.identifierRequirement(
                identifier: TunHelperConstants.helperBundleIdentifier
            )
        }
        let connection = NSXPCConnection(
            machServiceName: TunHelperConstants.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = TunHelperXPCInterfaceFactory.make()
        connection.setCodeSigningRequirement(helperRequirement)
        return LiveTunHelperConnection(connection: connection)
    }

    private func scheduleTimeout<Value>(
        for gate: ContinuationGate<Value>,
        after timeout: Duration,
        error: TunHelperClientError,
        connectionGeneration: UUID
    ) where Value: Sendable {
        Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard gate.resume(throwing: error) else { return }
            await self?.discardConnection(generation: connectionGeneration)
        }
    }

    private func discardConnection(generation: UUID) {
        guard connectionGeneration == generation else { return }
        let staleConnection = connection
        connection = nil
        connectionGeneration = nil
        compatibleProbe = nil
        staleConnection?.interruptionHandler = nil
        staleConnection?.invalidationHandler = nil
        staleConnection?.invalidate()
    }
}

private final class ContinuationGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, any Error>?

    init(_ continuation: CheckedContinuation<Value, any Error>) {
        self.continuation = continuation
    }

    @discardableResult
    func resume(returning value: sending Value) -> Bool {
        guard let continuation = take() else { return false }
        continuation.resume(returning: value)
        return true
    }

    @discardableResult
    func resume(throwing error: any Error) -> Bool {
        guard let continuation = take() else { return false }
        continuation.resume(throwing: error)
        return true
    }

    private func take() -> CheckedContinuation<Value, any Error>? {
        lock.withLock {
            let current = continuation
            continuation = nil
            return current
        }
    }
}
