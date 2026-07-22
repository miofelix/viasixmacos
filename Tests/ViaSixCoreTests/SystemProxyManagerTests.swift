import Foundation
import XCTest

@testable import ViaSixCore

final class SystemProxyManagerTests: XCTestCase {
    func testEnableUpdatesEveryEnabledServiceAndPreservesUnknownKeys() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("viasix-system-proxy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshotURL = root.appendingPathComponent("system-proxy.json")
        let original = try plistData([
            "HTTPEnable": 0,
            "ProxyAutoConfigEnable": 1,
            "ProxyAutoConfigURLString": "https://pac.example/pac",
            "ExceptionsList": ["localhost", "*.local"],
            "VendorKey": ["value": true],
        ])
        let disabled = try plistData(["HTTPEnable": 0])
        let store = FakeSystemProxyStore(states: [
            .init(
                serviceID: "wifi",
                serviceName: "Wi-Fi",
                isEnabled: true,
                protocolIsEnabled: true,
                configuration: original
            ),
            .init(
                serviceID: "ethernet",
                serviceName: "Ethernet",
                isEnabled: false,
                protocolIsEnabled: true,
                configuration: disabled
            ),
        ])
        let manager = SystemProxyManager(
            store: store,
            snapshotURL: snapshotURL,
            now: { Date(timeIntervalSince1970: 123) }
        )

        let snapshot = try await manager.enable(endpoint: ProxyEndpoint(host: "127.0.0.1", port: 7890))

        XCTAssertEqual(snapshot.services.map(\.serviceID), ["wifi"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotURL.path))
        let state = try XCTUnwrap(store.states.first { $0.serviceID == "wifi" })
        let object = try plistObject(state.configuration)
        XCTAssertEqual(object["HTTPProxy"] as? String, "127.0.0.1")
        XCTAssertEqual(object["HTTPPort"] as? Int, 7890)
        XCTAssertEqual(object["HTTPEnable"] as? Int, 1)
        XCTAssertEqual(object["SOCKSEnable"] as? Int, 1)
        XCTAssertEqual(object["ProxyAutoConfigEnable"] as? Int, 0)
        XCTAssertEqual(object["ProxyAutoConfigURLString"] as? String, "https://pac.example/pac")
        XCTAssertEqual(object["VendorKey"] as? [String: Bool], ["value": true])
        XCTAssertEqual(store.states.first { $0.serviceID == "ethernet" }?.configuration, disabled)
    }

    func testDisableRestoresExactPayloadAndProtocolState() async throws {
        let (manager, store, snapshotURL, original) = try makeManager()
        _ = try await manager.enable(endpoint: ProxyEndpoint(host: "127.0.0.1", port: 7890))

        let report = try await manager.disable()

        XCTAssertEqual(report.restoredServiceIDs, ["wifi"])
        XCTAssertFalse(report.changedByUser)
        XCTAssertEqual(store.states.first?.configuration, original)
        XCTAssertEqual(store.states.first?.protocolIsEnabled, false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path))
    }

    func testDisableTreatsXMLReserializationAsTheSameAppliedConfiguration() async throws {
        let (manager, store, snapshotURL, original) = try makeManager()
        _ = try await manager.enable(endpoint: ProxyEndpoint(host: "127.0.0.1", port: 7890))
        let applied = try XCTUnwrap(store.states.first?.configuration)
        let appliedObject = try PropertyListSerialization.propertyList(
            from: applied,
            options: [],
            format: nil
        )
        let xmlRepresentation = try PropertyListSerialization.data(
            fromPropertyList: appliedObject,
            format: .xml,
            options: 0
        )
        XCTAssertNotEqual(applied, xmlRepresentation)
        store.replaceState(
            SystemProxyServiceState(
                serviceID: "wifi",
                serviceName: "Wi-Fi",
                isEnabled: true,
                protocolIsEnabled: true,
                configuration: xmlRepresentation
            ))

        let report = try await manager.disable()

        XCTAssertEqual(report.restoredServiceIDs, ["wifi"])
        XCTAssertTrue(report.skippedExternallyModifiedServiceIDs.isEmpty)
        XCTAssertEqual(store.states.first?.configuration, original)
        XCTAssertEqual(store.states.first?.protocolIsEnabled, false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path))
    }

    func testDisableDoesNotOverwriteAnExternalChange() async throws {
        let (manager, store, _, _) = try makeManager()
        _ = try await manager.enable(endpoint: ProxyEndpoint(host: "127.0.0.1", port: 7890))
        let external = try plistData(["HTTPEnable": 1, "HTTPProxy": "other-app"])
        store.replaceState(
            .init(
                serviceID: "wifi",
                serviceName: "Wi-Fi",
                isEnabled: true,
                protocolIsEnabled: true,
                configuration: external
            )
        )

        let report = try await manager.disable()

        XCTAssertEqual(report.skippedExternallyModifiedServiceIDs, ["wifi"])
        XCTAssertEqual(store.states.first?.configuration, external)
    }

    func testFailedApplyRollsBackAndRemovesSnapshot() async throws {
        let (manager, store, snapshotURL, original) = try makeManager()
        store.failNextApply = true

        do {
            _ = try await manager.enable(endpoint: ProxyEndpoint(host: "127.0.0.1", port: 7890))
            XCTFail("Expected the transaction to fail")
        } catch let error as SystemProxyManagerError {
            guard case .transactionFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(store.states.first?.configuration, original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path))
    }

    func testRecoveryCompletesAStaleSnapshot() async throws {
        let (manager, store, snapshotURL, original) = try makeManager()
        _ = try await manager.enable(endpoint: ProxyEndpoint(host: "127.0.0.1", port: 7890))
        let recoveredManager = SystemProxyManager(store: store, snapshotURL: snapshotURL)

        let report = try await recoveredManager.recoverIfNeeded()

        XCTAssertEqual(report.restoredServiceIDs, ["wifi"])
        XCTAssertEqual(store.states.first?.configuration, original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path))
    }

    func testRecoveryRejectsSymbolicLinkSnapshotWithoutFollowingTarget() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("viasix-system-proxy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let outside = root.appendingPathComponent("outside-snapshot.json")
        let snapshotURL = root.appendingPathComponent("system-proxy.json")
        let planted = Data(
            #"{"version":1,"sessionID":"00000000-0000-0000-0000-000000000001","createdAt":0,"endpoint":{"host":"127.0.0.1","port":1},"services":[]}"#
                .utf8)
        try planted.write(to: outside)
        try FileManager.default.createSymbolicLink(at: snapshotURL, withDestinationURL: outside)

        let store = FakeSystemProxyStore(states: [
            .init(
                serviceID: "wifi",
                serviceName: "Wi-Fi",
                isEnabled: true,
                protocolIsEnabled: true,
                configuration: nil
            )
        ])
        let manager = SystemProxyManager(store: store, snapshotURL: snapshotURL)

        do {
            _ = try await manager.recoverIfNeeded()
            XCTFail("Expected symbolic-link snapshot to be rejected")
        } catch let error as SystemProxyManagerError {
            guard case .snapshotUnreadable(let reason) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(reason.contains("符号链接"))
        }
        XCTAssertEqual(try Data(contentsOf: outside), planted)
    }

    func testEnableRejectsInvalidEndpointAndNoEnabledService() async throws {
        let (manager, _, _, _) = try makeManager()
        do {
            _ = try await manager.enable(endpoint: ProxyEndpoint(host: "", port: 0))
            XCTFail("Expected invalid endpoint")
        } catch let error as SystemProxyManagerError {
            XCTAssertEqual(error, .invalidEndpoint)
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("viasix-system-proxy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let emptyStore = FakeSystemProxyStore(states: [
            .init(
                serviceID: "wifi",
                serviceName: "Wi-Fi",
                isEnabled: false,
                protocolIsEnabled: true,
                configuration: nil
            )
        ])
        let emptyManager = SystemProxyManager(
            store: emptyStore,
            snapshotURL: root.appendingPathComponent("system-proxy.json")
        )
        do {
            _ = try await emptyManager.enable(endpoint: ProxyEndpoint())
            XCTFail("Expected no enabled service")
        } catch let error as SystemProxyManagerError {
            XCTAssertEqual(error, .noEnabledServices)
        }
    }

    private func makeManager() throws -> (
        SystemProxyManager,
        FakeSystemProxyStore,
        URL,
        Data
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("viasix-system-proxy-\(UUID().uuidString)")
        let snapshotURL = root.appendingPathComponent("system-proxy.json")
        let original = try plistData([
            "HTTPEnable": 0,
            "ProxyAutoConfigEnable": 1,
            "ProxyAutoConfigURLString": "https://pac.example/pac",
            "ExceptionsList": ["localhost", "*.local"],
        ])
        let store = FakeSystemProxyStore(states: [
            .init(
                serviceID: "wifi",
                serviceName: "Wi-Fi",
                isEnabled: true,
                protocolIsEnabled: false,
                configuration: original
            )
        ])
        return (
            SystemProxyManager(store: store, snapshotURL: snapshotURL),
            store,
            snapshotURL,
            original
        )
    }
}

private final class FakeSystemProxyStore: SystemProxyStore, @unchecked Sendable {
    private(set) var states: [SystemProxyServiceState]
    var failNextApply = false

    init(states: [SystemProxyServiceState]) {
        self.states = states
    }

    func readServices() throws -> [SystemProxyServiceState] { states }

    func apply(_ changes: [SystemProxyServiceChange]) throws {
        if failNextApply {
            failNextApply = false
            throw FakeError.applyFailed
        }
        var indexed = Dictionary(uniqueKeysWithValues: states.map { ($0.serviceID, $0) })
        for change in changes {
            guard let current = indexed[change.serviceID] else { throw FakeError.missing }
            if let expected = change.expectedState, expected != current {
                throw FakeError.externalChange
            }
            indexed[change.serviceID] = SystemProxyServiceState(
                serviceID: current.serviceID,
                serviceName: current.serviceName,
                isEnabled: current.isEnabled,
                protocolIsEnabled: change.protocolIsEnabled,
                configuration: change.configuration
            )
        }
        states = states.map { indexed[$0.serviceID]! }
    }

    func replaceState(_ state: SystemProxyServiceState) {
        states = states.map { $0.serviceID == state.serviceID ? state : $0 }
    }
}

private enum FakeError: Error {
    case applyFailed
    case missing
    case externalChange
}

private func plistData(_ object: Any) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
}

private func plistObject(_ data: Data?) throws -> [String: Any] {
    guard let data else { return [:] }
    let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    return try XCTUnwrap(object as? [String: Any])
}
