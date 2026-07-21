import Darwin
import Foundation
import XCTest

@testable import ViaSixTunHelperSupport

final class TunSessionJournalTests: XCTestCase {
    func testAtomicRoundTripUsesPrivatePermissionsAndRemovalIsIdempotent() throws {
        try withStore { store, root in
            let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
            let journal = TunSessionJournal(
                ownerUserIdentifier: UInt32(geteuid()),
                phase: .running,
                cleanupRequired: true,
                createdAt: createdAt
            )

            try store.save(journal)
            XCTAssertEqual(try store.load(), journal)

            let directoryMode = try fileMode(at: root)
            let journalMode = try fileMode(at: root.appendingPathComponent("tun-session.json"))
            XCTAssertEqual(directoryMode & 0o777, 0o700)
            XCTAssertEqual(journalMode & 0o777, 0o600)
            XCTAssertEqual(try fileGroup(at: root), UInt32(getegid()))
            XCTAssertEqual(
                try fileGroup(at: root.appendingPathComponent("tun-session.json")),
                UInt32(getegid())
            )

            try store.remove()
            try store.remove()
            XCTAssertNil(try store.load())
        }
    }

    func testLoadRejectsSymbolicLinkJournal() throws {
        try withStore { store, root in
            _ = try store.load()
            let target = root.deletingLastPathComponent().appendingPathComponent("outside.json")
            try Data("{}".utf8).write(to: target)
            try FileManager.default.createSymbolicLink(
                at: root.appendingPathComponent("tun-session.json"),
                withDestinationURL: target
            )

            XCTAssertThrowsError(try store.load()) { error in
                guard case .posix(let operation, let code) = error as? TunSessionJournalError else {
                    return XCTFail("Unexpected error: \(error)")
                }
                XCTAssertEqual(operation, "openat(journal)")
                XCTAssertEqual(code, ELOOP)
            }
        }
    }

    func testSecureLegacyRootGroupIsNormalized() throws {
        try withStore { store, root in
            _ = try store.load()
            guard let legacyGroup = supplementaryGroupDifferentFromEffectiveGroup() else {
                throw XCTSkip("No alternate supplementary group is available")
            }
            guard chown(root.path, uid_t.max, legacyGroup) == 0 else {
                throw XCTSkip("Cannot assign the simulated legacy group")
            }

            XCTAssertNil(try store.load())
            XCTAssertEqual(try fileGroup(at: root), UInt32(getegid()))
        }
    }

    func testControllerTransitionsAndClearsCompletedSession() throws {
        try withStore { store, _ in
            let controller = TunSessionJournalController(
                store: store,
                now: { Date(timeIntervalSince1970: 1_700_000_000) }
            )
            let preparing = try controller.begin(ownerUserIdentifier: UInt32(geteuid()))
            XCTAssertTrue(try controller.recoveryPending())

            let running = try controller.markRunning(
                sessionIdentifier: preparing.sessionIdentifier
            )
            XCTAssertEqual(running.phase, .running)

            try controller.complete(sessionIdentifier: preparing.sessionIdentifier)
            XCTAssertFalse(try controller.recoveryPending())
            XCTAssertNil(try controller.currentJournal())
        }
    }

    func testRecoveryPersistsFailureAndCanBeRetried() throws {
        enum CleanupError: LocalizedError {
            case failed

            var errorDescription: String? { "cleanup failed" }
        }

        try withStore { store, _ in
            let controller = TunSessionJournalController(store: store)
            _ = try controller.begin(ownerUserIdentifier: UInt32(geteuid()))

            XCTAssertThrowsError(
                try controller.recoverIfNeeded { _ in throw CleanupError.failed }
            )
            let failed = try XCTUnwrap(controller.currentJournal())
            XCTAssertEqual(failed.phase, .failed)
            XCTAssertTrue(failed.recoveryPending)
            XCTAssertEqual(failed.lastError, "cleanup failed")

            try controller.recoverIfNeeded { _ in }
            XCTAssertNil(try controller.currentJournal())
        }
    }

    func testUnavailableRecoveryBackendPreservesExistingJournalExactly() throws {
        enum CleanupError: LocalizedError {
            case failed

            var errorDescription: String? { "original cleanup failure" }
        }

        try withStore { store, _ in
            let controller = TunSessionJournalController(store: store)
            let pending = try controller.begin(ownerUserIdentifier: UInt32(geteuid()))
            try controller.markFailed(
                sessionIdentifier: pending.sessionIdentifier,
                error: CleanupError.failed
            )
            let before = try XCTUnwrap(controller.currentJournal())

            XCTAssertThrowsError(
                try controller.rejectPendingRecoveryWithoutBackend()
            ) { error in
                XCTAssertEqual(
                    error as? TunSessionJournalError,
                    .recoveryBackendUnavailable
                )
            }

            XCTAssertEqual(try controller.currentJournal(), before)
        }
    }

    func testFailureDescriptionIsBoundedByUTF8Bytes() throws {
        struct CleanupError: LocalizedError {
            let errorDescription: String?
        }

        try withStore { store, _ in
            let controller = TunSessionJournalController(store: store)
            let pending = try controller.begin(ownerUserIdentifier: UInt32(geteuid()))

            try controller.markFailed(
                sessionIdentifier: pending.sessionIdentifier,
                error: CleanupError(errorDescription: String(repeating: "\u{1F6A7}", count: 2_000))
            )

            let failed = try XCTUnwrap(controller.currentJournal())
            let lastError = try XCTUnwrap(failed.lastError)
            XCTAssertEqual(lastError.utf8.count, 4_096)
            XCTAssertEqual(lastError, String(repeating: "\u{1F6A7}", count: 1_024))
        }
    }

    func testStaleSessionCannotChangeNewJournal() throws {
        try withStore { store, _ in
            let controller = TunSessionJournalController(store: store)
            let current = try controller.begin(ownerUserIdentifier: UInt32(geteuid()))
            let stale = UUID()

            XCTAssertThrowsError(try controller.markRunning(sessionIdentifier: stale)) { error in
                XCTAssertEqual(
                    error as? TunSessionJournalError,
                    .staleSession(expected: stale, actual: current.sessionIdentifier)
                )
            }
        }
    }

    private func withStore(
        _ body: (TunSessionJournalStore, URL) throws -> Void
    ) throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ViaSix-TunJournal-\(UUID().uuidString)",
            isDirectory: true
        )
        let root = parent.appendingPathComponent("State", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: parent) }

        let store = TunSessionJournalStore(
            rootDirectoryURL: root,
            expectedOwnerUserIdentifier: UInt32(geteuid()),
            expectedOwnerGroupIdentifier: UInt32(getegid())
        )
        try body(store, root)
    }

    private func fileMode(at url: URL) throws -> mode_t {
        var metadata = stat()
        guard lstat(url.path, &metadata) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return metadata.st_mode
    }

    private func fileGroup(at url: URL) throws -> UInt32 {
        var metadata = stat()
        guard lstat(url.path, &metadata) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return metadata.st_gid
    }

    private func supplementaryGroupDifferentFromEffectiveGroup() -> gid_t? {
        var groups = [gid_t](repeating: 0, count: Int(NGROUPS_MAX))
        let count = getgroups(Int32(groups.count), &groups)
        guard count > 0 else { return nil }
        return groups.prefix(Int(count)).first { $0 != getegid() }
    }
}
