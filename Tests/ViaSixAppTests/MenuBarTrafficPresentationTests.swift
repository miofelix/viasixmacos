import XCTest

@testable import ViaSixApp
@testable import ViaSixCore

final class MenuBarTrafficPresentationTests: XCTestCase {
    func testSpeedTitleHiddenWhenProxyStopped() {
        XCTAssertNil(
            MenuBarTrafficPresentation.speedTitle(
                isProxyRunning: false,
                snapshot: TrafficSnapshot(up: 1_024, down: 2_048, isLive: true)
            )
        )
    }

    func testSpeedTitleShownWhenProxyRunning() {
        let title = MenuBarTrafficPresentation.speedTitle(
            isProxyRunning: true,
            snapshot: TrafficSnapshot(up: 1_024, down: 2 * 1_024 * 1_024)
        )
        XCTAssertEqual(title?.split(separator: "\n").count, 2)
        XCTAssertTrue(title?.contains("1.0K/s") == true)
        XCTAssertTrue(title?.contains("2.0M/s") == true)
    }

    func testMenuSummaryFormatsBothDirections() {
        let summary = MenuBarTrafficPresentation.menuSummary(
            isProxyRunning: true,
            snapshot: TrafficSnapshot(up: 0, down: 512)
        )
        XCTAssertEqual(summary, "↑ 0 B/s  ↓ 512 B/s")
    }
}
