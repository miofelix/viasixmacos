import Foundation
import ViaSixCore
import XCTest

@testable import ViaSixApp

final class NodeResultSortingTests: XCTestCase {
    func testNoSortOrderPreservesSourceOrderAndEmptyInput() {
        let results = fixtures()

        XCTAssertEqual(
            NodeResultSorting.sorted(results, using: []).map(\.ip),
            results.map(\.ip)
        )
        XCTAssertTrue(NodeResultSorting.sorted([], using: []).isEmpty)
    }

    func testNumericColumnsUseNumericValuesAndKeepMissingValuesLast() {
        let results = [
            result("192.0.2.1", sent: "10", received: "8", loss: "0.25", latency: "100", speed: "9.5"),
            result("192.0.2.2", sent: "2", received: "12", loss: "0.05", latency: "9", speed: "12"),
            result("192.0.2.3", sent: "", received: "", loss: "", latency: "—", speed: ""),
        ]

        XCTAssertEqual(sortedIPs(results, by: .latency), ["192.0.2.2", "192.0.2.1", "192.0.2.3"])
        XCTAssertEqual(sortedIPs(results, by: .speed, order: .reverse), ["192.0.2.2", "192.0.2.1", "192.0.2.3"])
        XCTAssertEqual(sortedIPs(results, by: .loss), ["192.0.2.2", "192.0.2.1", "192.0.2.3"])
        XCTAssertEqual(sortedIPs(results, by: .sent), ["192.0.2.2", "192.0.2.1", "192.0.2.3"])
        XCTAssertEqual(sortedIPs(results, by: .received, order: .reverse), ["192.0.2.2", "192.0.2.1", "192.0.2.3"])
    }

    func testEqualValuesRemainInSourceOrder() {
        let results = [
            result("192.0.2.30", latency: "15"),
            result("192.0.2.10", latency: "15"),
            result("192.0.2.20", latency: "15"),
        ]
        let selectedID = results[1].id

        let sorted = NodeResultSorting.sorted(
            results,
            using: [NodeResultSortComparator(.latency)]
        )

        XCTAssertEqual(sorted.map(\.ip), results.map(\.ip))
        XCTAssertTrue(sorted.contains { $0.id == selectedID })
    }

    func testRegionSortIsNaturalAndMissingRegionStaysLast() {
        let results = [
            result("192.0.2.1", region: "HKG10"),
            result("192.0.2.2", region: ""),
            result("192.0.2.3", region: "hkg2"),
            result("192.0.2.4", region: "NRT"),
        ]

        XCTAssertEqual(
            sortedIPs(results, by: .region),
            ["192.0.2.3", "192.0.2.1", "192.0.2.4", "192.0.2.2"]
        )
        XCTAssertEqual(
            sortedIPs(results, by: .region, order: .reverse),
            ["192.0.2.4", "192.0.2.1", "192.0.2.3", "192.0.2.2"]
        )
    }

    func testIPSortsByAddressBytesInsteadOfDisplayedText() {
        let results = [
            result("2001:db8::10"),
            result("192.0.2.10"),
            result("2001:db8::2"),
            result("192.0.2.2"),
            result("not-an-ip"),
        ]

        XCTAssertEqual(
            sortedIPs(results, by: .ip),
            ["192.0.2.2", "192.0.2.10", "2001:db8::2", "2001:db8::10", "not-an-ip"]
        )
    }

    private func fixtures() -> [SpeedTestResult] {
        [
            result("192.0.2.2", latency: "20", speed: "8", region: "NRT"),
            result("192.0.2.1", latency: "10", speed: "12", region: "HKG"),
        ]
    }

    private func sortedIPs(
        _ results: [SpeedTestResult],
        by field: NodeResultSortField,
        order: SortOrder = .forward
    ) -> [String] {
        NodeResultSorting.sorted(
            results,
            using: [NodeResultSortComparator(field, order: order)]
        ).map(\.ip)
    }

    private func result(
        _ ip: String,
        sent: String = "4",
        received: String = "4",
        loss: String = "0",
        latency: String = "10",
        speed: String = "10",
        region: String = ""
    ) -> SpeedTestResult {
        SpeedTestResult(
            ip: ip,
            sent: sent,
            received: received,
            loss: loss,
            latency: latency,
            speed: speed,
            region: region
        )
    }
}
