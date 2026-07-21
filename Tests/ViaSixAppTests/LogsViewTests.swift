import Foundation
import XCTest

@testable import ViaSixApp

final class LogsViewTests: XCTestCase {
    func testLeavingLatestPausesFollowingAndCountsMatchingNewRecords() {
        let olderID = UUID()
        let latestID = UUID()
        let firstNewID = UUID()
        let secondNewID = UUID()
        var state = LogFollowState()

        state.observeVisibleTarget(.entry(olderID), latestEntryID: latestID)
        state.observeMatchingLogIDs(
            previous: [olderID, latestID],
            current: [olderID, latestID, firstNewID, secondNewID]
        )

        XCTAssertEqual(state.mode, .pausedByScroll)
        XCTAssertEqual(state.pendingNewRecordCount, 2)
    }

    func testNonmatchingNewRecordsDoNotIncreaseTheFilteredCount() {
        let olderID = UUID()
        let latestID = UUID()
        var state = LogFollowState()

        state.observeVisibleTarget(.entry(olderID), latestEntryID: latestID)
        state.observeMatchingLogIDs(
            previous: [olderID, latestID],
            current: [olderID, latestID]
        )

        XCTAssertEqual(state.mode, .pausedByScroll)
        XCTAssertEqual(state.pendingNewRecordCount, 0)
    }

    func testReturningToLatestAfterScrollPauseResumesAndClearsCount() {
        let olderID = UUID()
        let latestID = UUID()
        let newID = UUID()
        var state = LogFollowState()

        state.observeVisibleTarget(.entry(olderID), latestEntryID: latestID)
        state.observeMatchingLogIDs(
            previous: [olderID, latestID],
            current: [olderID, latestID, newID]
        )
        state.observeVisibleTarget(.bottom(newID), latestEntryID: newID)

        XCTAssertEqual(state.mode, .following)
        XCTAssertEqual(state.pendingNewRecordCount, 0)
    }

    func testLatestTargetDoesNotOverrideExplicitPause() {
        let latestID = UUID()
        var state = LogFollowState()

        state.toggleExplicitFollowing(latestEntryID: latestID)
        state.observeVisibleTarget(.bottom(latestID), latestEntryID: latestID)

        XCTAssertEqual(state.mode, .pausedExplicitly)
        XCTAssertFalse(state.followsLatest)
    }

    func testExplicitFollowControlResumesAndTargetsLatest() {
        let latestID = UUID()
        let newID = UUID()
        var state = LogFollowState()

        state.toggleExplicitFollowing(latestEntryID: latestID)
        state.observeMatchingLogIDs(previous: [latestID], current: [latestID, newID])
        state.toggleExplicitFollowing(latestEntryID: newID)

        XCTAssertEqual(state.mode, .following)
        XCTAssertEqual(state.pendingNewRecordCount, 0)
        XCTAssertEqual(state.expectedAutomaticTargetID, newID)
    }

    func testAutomaticScrollEndsOnlyAfterExpectedBottomTargetArrives() {
        let olderID = UUID()
        let expectedID = UUID()
        var state = LogFollowState()

        XCTAssertTrue(state.beginMaintainingLatest(target: expectedID))
        state.observeVisibleTarget(.entry(olderID), latestEntryID: expectedID)

        XCTAssertEqual(state.mode, .following)
        XCTAssertEqual(state.expectedAutomaticTargetID, expectedID)

        state.observeVisibleTarget(.bottom(expectedID), latestEntryID: expectedID)

        XCTAssertEqual(state.mode, .following)
        XCTAssertNil(state.expectedAutomaticTargetID)

        state.observeVisibleTarget(.entry(olderID), latestEntryID: expectedID)

        XCTAssertEqual(state.mode, .pausedByScroll)
    }

    func testMaintainingLatestDoesNotLeaveExpectedTargetWhenAlreadyAtBottom() {
        let latestID = UUID()
        var state = LogFollowState()

        XCTAssertFalse(
            state.beginMaintainingLatest(
                target: latestID,
                visibleTarget: .bottom(latestID)
            )
        )
        XCTAssertNil(state.expectedAutomaticTargetID)

        state.observeVisibleTarget(.entry(UUID()), latestEntryID: latestID)

        XCTAssertEqual(state.mode, .pausedByScroll)
    }

    func testFilterChangeRebaselineClearsCountWithoutChangingPauseReason() {
        let latestID = UUID()
        let newID = UUID()
        var state = LogFollowState()

        state.toggleExplicitFollowing(latestEntryID: latestID)
        state.observeMatchingLogIDs(previous: [latestID], current: [latestID, newID])
        state.rebaselineMatchingRecords()

        XCTAssertEqual(state.mode, .pausedExplicitly)
        XCTAssertEqual(state.pendingNewRecordCount, 0)
    }

    func testClearingLogsRestoresFollowingAndClearsTransientState() {
        let latestID = UUID()
        let newID = UUID()
        var state = LogFollowState()

        state.toggleExplicitFollowing(latestEntryID: latestID)
        state.observeMatchingLogIDs(previous: [latestID], current: [latestID, newID])
        state.resetAfterClearingLogs()

        XCTAssertEqual(state.mode, .following)
        XCTAssertEqual(state.pendingNewRecordCount, 0)
        XCTAssertNil(state.expectedAutomaticTargetID)
    }

    func testCappedLogBufferCountsOnlyNewMatchingIDs() {
        let removedID = UUID()
        let retainedID = UUID()
        let newID = UUID()
        var state = LogFollowState()

        state.toggleExplicitFollowing(latestEntryID: retainedID)
        state.observeMatchingLogIDs(
            previous: [removedID, retainedID],
            current: [retainedID, newID]
        )

        XCTAssertEqual(state.pendingNewRecordCount, 1)
    }

    func testMissingScrollTargetDuringRelayoutDoesNotPauseFollowing() {
        let latestID = UUID()
        var state = LogFollowState()

        state.observeVisibleTarget(nil, latestEntryID: latestID)

        XCTAssertEqual(state.mode, .following)
    }
}
