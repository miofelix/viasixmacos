import XCTest

@testable import ViaSixCore

final class CSVParserTests: XCTestCase {
    func testCSVHandlesQuotedFieldsAndCRLF() throws {
        let csv = "IP,延迟,地区\r\n1.1.1.1,12.5,\"SJC, US\"\r\n"
        let rows = try CSVParser.parse(string: csv)
        XCTAssertEqual(rows, [["IP", "延迟", "地区"], ["1.1.1.1", "12.5", "SJC, US"]])
    }

    func testResultParserMapsCFSTColumns() throws {
        let csv = "IP,Sent,Recv,Loss,Latency,Speed,Region\n2606::1,4,4,0.00,20.4,12.2,SJC\n"
        let result = try XCTUnwrap(SpeedTestResultParser.parse(data: Data(csv.utf8)).first)
        XCTAssertEqual(result.ip, "2606::1")
        XCTAssertEqual(result.latencyValue, 20.4)
        XCTAssertEqual(result.speedValue, 12.2)
        XCTAssertEqual(result.region, "SJC")
    }
}
