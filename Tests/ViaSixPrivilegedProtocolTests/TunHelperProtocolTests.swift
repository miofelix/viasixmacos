import Foundation
import XCTest

@testable import ViaSixPrivilegedProtocol

final class TunHelperProtocolTests: XCTestCase {
    func testConfigurationEnvelopeAcceptsOnlyDigestedBinaryPropertyListDictionary() throws {
        let payload = try binaryPropertyList([
            "SchemaVersion": 1,
            "RoutingMode": "rule",
        ])
        let envelope = try TunConfigurationEnvelope(payload: payload)

        XCTAssertEqual(envelope.schemaVersion, TunConfigurationEnvelope.currentSchemaVersion)
        XCTAssertEqual(envelope.payload, payload)
        XCTAssertEqual(envelope.sha256, TunConfigurationEnvelope.sha256Hex(of: payload))
        XCTAssertNoThrow(try envelope.validate())
    }

    func testConfigurationEnvelopeRejectsRawYAMLXMLAndNonDictionaryRoots() throws {
        XCTAssertThrowsError(
            try TunConfigurationEnvelope(payload: Data("mode: rule\n".utf8))
        ) { error in
            XCTAssertEqual(
                error as? TunConfigurationEnvelopeError,
                .payloadIsNotBinaryPropertyList
            )
        }

        let xml = try PropertyListSerialization.data(
            fromPropertyList: ["SchemaVersion": 1],
            format: .xml,
            options: 0
        )
        XCTAssertThrowsError(try TunConfigurationEnvelope(payload: xml)) { error in
            XCTAssertEqual(
                error as? TunConfigurationEnvelopeError,
                .payloadIsNotBinaryPropertyList
            )
        }

        let array = try binaryPropertyList(["rule", "global"])
        XCTAssertThrowsError(try TunConfigurationEnvelope(payload: array)) { error in
            XCTAssertEqual(
                error as? TunConfigurationEnvelopeError,
                .payloadRootIsNotDictionary
            )
        }
    }

    func testConfigurationEnvelopeRejectsSchemaSizeAndDigestViolations() throws {
        let payload = try binaryPropertyList(["SchemaVersion": 1])
        XCTAssertThrowsError(
            try TunConfigurationEnvelope(
                schemaVersion: TunConfigurationEnvelope.currentSchemaVersion + 1,
                payload: payload,
                sha256: TunConfigurationEnvelope.sha256Hex(of: payload)
            )
        ) { error in
            XCTAssertEqual(
                error as? TunConfigurationEnvelopeError,
                .unsupportedSchemaVersion(2)
            )
        }

        XCTAssertThrowsError(
            try TunConfigurationEnvelope(
                schemaVersion: TunConfigurationEnvelope.currentSchemaVersion,
                payload: payload,
                sha256: String(repeating: "0", count: 64)
            )
        ) { error in
            XCTAssertEqual(error as? TunConfigurationEnvelopeError, .sha256Mismatch)
        }

        XCTAssertThrowsError(
            try TunConfigurationEnvelope(
                schemaVersion: TunConfigurationEnvelope.currentSchemaVersion,
                payload: Data(count: TunConfigurationEnvelope.maximumPayloadBytes + 1),
                sha256: String(repeating: "0", count: 64)
            )
        ) { error in
            XCTAssertEqual(
                error as? TunConfigurationEnvelopeError,
                .payloadTooLarge(TunConfigurationEnvelope.maximumPayloadBytes + 1)
            )
        }
    }

    func testSecureCodingRoundTripsEnvelopeAndStatusSnapshot() throws {
        let payload = try binaryPropertyList(["SchemaVersion": 1])
        let envelope = try TunConfigurationEnvelope(payload: payload)
        let envelopeArchive = try NSKeyedArchiver.archivedData(
            withRootObject: envelope,
            requiringSecureCoding: true
        )
        let decodedEnvelope = try XCTUnwrap(
            NSKeyedUnarchiver.unarchivedObject(
                ofClass: TunConfigurationEnvelope.self,
                from: envelopeArchive
            )
        )
        XCTAssertEqual(decodedEnvelope.payload, payload)
        XCTAssertEqual(decodedEnvelope.sha256, envelope.sha256)

        let sessionIdentifier = UUID()
        let observedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = try TunHelperStatusSnapshot(
            supportedFeatures: TunHelperFeature.allKnown.rawValue,
            runtimeState: .ready,
            runtimeVersion: "1.19.29",
            sessionPhase: .running,
            sessionIdentifier: sessionIdentifier,
            sessionOwnedByCaller: true,
            recoveryRequired: false,
            routingMode: .rule,
            observedAt: observedAt,
            lastError: nil
        )
        let snapshotArchive = try NSKeyedArchiver.archivedData(
            withRootObject: snapshot,
            requiringSecureCoding: true
        )
        let decodedSnapshot = try XCTUnwrap(
            NSKeyedUnarchiver.unarchivedObject(
                ofClass: TunHelperStatusSnapshot.self,
                from: snapshotArchive
            )
        )
        XCTAssertEqual(decodedSnapshot.features, .allKnown)
        XCTAssertEqual(decodedSnapshot.runtimeState, .ready)
        XCTAssertEqual(decodedSnapshot.runtimeVersion, "1.19.29")
        XCTAssertEqual(decodedSnapshot.sessionPhase, .running)
        XCTAssertEqual(decodedSnapshot.sessionIdentifier, sessionIdentifier)
        XCTAssertEqual(decodedSnapshot.routingMode, .rule)
        XCTAssertEqual(decodedSnapshot.observedAt, observedAt)
    }

    func testStatusSnapshotRejectsContradictoryOrUnredactedState() {
        XCTAssertThrowsError(
            try TunHelperStatusSnapshot(
                supportedFeatures: 0,
                runtimeState: .unavailable,
                runtimeVersion: nil,
                sessionPhase: .inactive,
                sessionIdentifier: UUID(),
                sessionOwnedByCaller: true,
                recoveryRequired: false,
                routingMode: nil,
                lastError: nil
            )
        ) { error in
            XCTAssertEqual(error as? TunHelperStatusSnapshotError, .invalidSessionState)
        }

        XCTAssertThrowsError(
            try TunHelperStatusSnapshot(
                supportedFeatures: 0,
                runtimeState: .unavailable,
                runtimeVersion: nil,
                sessionPhase: .recoveryRequired,
                sessionIdentifier: UUID(),
                sessionOwnedByCaller: false,
                recoveryRequired: true,
                routingMode: nil,
                lastError: "must be redacted"
            )
        ) { error in
            XCTAssertEqual(error as? TunHelperStatusSnapshotError, .invalidSessionState)
        }
    }

    func testXPCInterfaceDeclaresEnvelopeAndReplyClasses() {
        let interface = TunHelperXPCInterfaceFactory.make()
        let probeSelector = #selector(TunHelperXPCProtocol.probe(reply:))
        let startSelector = #selector(
            TunHelperXPCProtocol.startSession(configuration:reply:)
        )
        let statusSelector = #selector(TunHelperXPCProtocol.status(reply:))

        XCTAssertEqual(NSStringFromSelector(probeSelector), "probeWithReply:")

        let requestClasses = NSSet(
            set: interface.classes(
                for: startSelector,
                argumentIndex: 0,
                ofReply: false
            )
        )
        XCTAssertTrue(requestClasses.contains(TunConfigurationEnvelope.self))
        XCTAssertTrue(requestClasses.contains(NSData.self))

        let snapshotClasses = NSSet(
            set: interface.classes(
                for: statusSelector,
                argumentIndex: 0,
                ofReply: true
            )
        )
        XCTAssertTrue(snapshotClasses.contains(TunHelperStatusSnapshot.self))
        XCTAssertTrue(snapshotClasses.contains(NSUUID.self))

        let errorClasses = NSSet(
            set: interface.classes(
                for: statusSelector,
                argumentIndex: 1,
                ofReply: true
            )
        )
        XCTAssertTrue(errorClasses.contains(NSError.self))
        XCTAssertTrue(errorClasses.contains(NSDictionary.self))

        let probeErrorClasses = NSSet(
            set: interface.classes(
                for: probeSelector,
                argumentIndex: 4,
                ofReply: true
            )
        )
        XCTAssertTrue(probeErrorClasses.contains(NSError.self))
        XCTAssertTrue(probeErrorClasses.contains(NSDictionary.self))
    }

    private func binaryPropertyList(_ value: Any) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: value,
            format: .binary,
            options: 0
        )
    }
}
