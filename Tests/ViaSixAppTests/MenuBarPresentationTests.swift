import ViaSixCore
import XCTest

@testable import ViaSixApp

final class MenuBarPresentationTests: XCTestCase {
    func testSelectedNodeIsFirstAndKeepsItsMeasuredMetadata() {
        let selected = SpeedTestResult(
            ip: "2606::2",
            latency: "18",
            speed: "24",
            region: "HKG"
        )
        let results = [
            SpeedTestResult(ip: "2606::1", region: "NRT"),
            selected,
            SpeedTestResult(ip: "2606::3", region: "SJC"),
        ]

        let visible = MenuBarNodePresentation.visibleResults(
            from: results,
            selectedIP: "2606::2"
        )

        XCTAssertEqual(visible.map(\.ip), ["2606::2", "2606::1", "2606::3"])
        XCTAssertEqual(visible.first, selected)
    }

    func testSelectedNodeMissingFromResultsRemainsVisible() {
        let visible = MenuBarNodePresentation.visibleResults(
            from: [SpeedTestResult(ip: "2606::1")],
            selectedIP: " 2606::9 ",
            limit: 2
        )

        XCTAssertEqual(visible.map(\.ip), ["2606::9", "2606::1"])
    }

    func testVisibleNodesAreDeduplicatedAndBounded() {
        let results = [
            SpeedTestResult(ip: "2606::1"),
            SpeedTestResult(ip: "2606::1"),
            SpeedTestResult(ip: "2606::2"),
            SpeedTestResult(ip: "2606::3"),
        ]

        let visible = MenuBarNodePresentation.visibleResults(
            from: results,
            selectedIP: "",
            limit: 2
        )

        XCTAssertEqual(visible.map(\.ip), ["2606::1", "2606::2"])
        XCTAssertTrue(
            MenuBarNodePresentation.hasAdditionalResults(
                in: results,
                selectedIP: "",
                visibleLimit: 2
            )
        )
    }

    func testNodeTitleUsesRegionWhenAvailable() {
        XCTAssertEqual(
            MenuBarNodePresentation.title(
                for: SpeedTestResult(ip: " 2606::1 ", region: " HKG ")
            ),
            "HKG · 2606::1"
        )
        XCTAssertEqual(
            MenuBarNodePresentation.title(
                for: SpeedTestResult(ip: " 2606::2 ")
            ),
            "2606::2"
        )
    }
}
