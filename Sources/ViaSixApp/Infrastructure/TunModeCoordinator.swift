import Foundation
import ViaSixPrivilegedProtocol

protocol TunModeCoordinating: Sendable {
    func registrationState() async -> TunHelperRegistrationState
    func registerService() async throws -> TunHelperRegistrationState
    func repairService() async throws -> TunHelperRegistrationState
    func openApprovalSettings() async
    func helperStatus() async throws -> TunHelperStatusSnapshot
    func installOrRepairRuntime() async throws -> TunHelperStatusSnapshot
    func startSession(envelopePayload: Data) async throws -> TunHelperStatusSnapshot
    func stopSession() async throws -> TunHelperStatusSnapshot
    func recover() async throws -> TunHelperStatusSnapshot
    func invalidate() async
}

actor TunModeCoordinator: TunModeCoordinating {
    private let installer: TunHelperInstaller
    private let client: TunHelperClient

    init(
        installer: TunHelperInstaller = TunHelperInstaller(),
        client: TunHelperClient = TunHelperClient()
    ) {
        self.installer = installer
        self.client = client
    }

    func registrationState() -> TunHelperRegistrationState {
        installer.status()
    }

    func registerService() throws -> TunHelperRegistrationState {
        try installer.register()
    }

    func repairService() async throws -> TunHelperRegistrationState {
        await client.invalidate()
        return try await installer.reregister()
    }

    func openApprovalSettings() {
        installer.openApprovalSettings()
    }

    func helperStatus() async throws -> TunHelperStatusSnapshot {
        try await client.status()
    }

    func installOrRepairRuntime() async throws -> TunHelperStatusSnapshot {
        try await client.installOrRepairRuntime()
    }

    func startSession(envelopePayload: Data) async throws -> TunHelperStatusSnapshot {
        let envelope = try TunConfigurationEnvelope(payload: envelopePayload)
        return try await client.startSession(configuration: envelope)
    }

    func stopSession() async throws -> TunHelperStatusSnapshot {
        try await client.stopSession()
    }

    func recover() async throws -> TunHelperStatusSnapshot {
        try await client.recover()
    }

    func invalidate() async {
        await client.invalidate()
    }
}
