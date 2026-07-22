import XCTest

@testable import ViaSixCore

final class ByteRateFormatterTests: XCTestCase {
    func testFormatsByteBoundaries() {
        XCTAssertEqual(ByteRateFormatter.formatBytes(0), "0 B")
        XCTAssertEqual(ByteRateFormatter.formatBytes(999), "999 B")
        XCTAssertEqual(ByteRateFormatter.formatRate(0), "0 B/s")
        XCTAssertEqual(ByteRateFormatter.formatRate(1_024), "1.00 KB/s")
    }

    func testFormatsCompactRates() {
        XCTAssertEqual(ByteRateFormatter.formatCompactRate(0), "0B/s")
        XCTAssertEqual(ByteRateFormatter.formatCompactRate(999), "999B/s")
        XCTAssertEqual(ByteRateFormatter.formatCompactRate(1_024), "1.0K/s")
        XCTAssertEqual(ByteRateFormatter.formatCompactRate(10 * 1_024), "10K/s")
        XCTAssertEqual(ByteRateFormatter.formatCompactRate(1_024 * 1_024), "1.0M/s")
    }

    func testMenuBarTitleIsTwoLines() {
        let title = ByteRateFormatter.menuBarSpeedTitle(up: 1_024, down: 2 * 1_024 * 1_024)
        let lines = title.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("1.0K/s"))
        XCTAssertTrue(lines[1].contains("2.0M/s"))
    }

    func testParseBytesReturnsUnitParts() {
        let parsed = ByteRateFormatter.parseBytes(5 * 1_024 * 1_024)
        XCTAssertEqual(parsed.unit, "MB")
        XCTAssertFalse(parsed.value.isEmpty)
    }
}
