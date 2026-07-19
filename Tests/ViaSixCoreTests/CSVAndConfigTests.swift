import XCTest
@testable import ViaSixCore

final class CSVAndConfigTests: XCTestCase {
    func testCSVHandlesQuotedFieldsAndCRLF() throws {
        let csv = "IP,延迟,地区\r\n1.1.1.1,12.5,\"SJC, US\"\r\n"
        let rows = try CSVParser.parse(string: csv)
        XCTAssertEqual(rows, [["IP", "延迟", "地区"], ["1.1.1.1", "12.5", "SJC, US"]])
    }

    func testResultParserKeepsReferenceColumns() throws {
        let csv = "IP,Sent,Recv,Loss,Latency,Speed,Region\n2606::1,4,4,0.00,20.4,12.2,SJC\n"
        let result = try XCTUnwrap(SpeedTestResultParser.parse(data: Data(csv.utf8)).first)
        XCTAssertEqual(result.ip, "2606::1")
        XCTAssertEqual(result.latencyValue, 20.4)
        XCTAssertEqual(result.speedValue, 12.2)
        XCTAssertEqual(result.region, "SJC")
    }

    func testConfigWriterOnlyChangesProxyAddress() throws {
        let template = Data(#"{"outbounds":[{"settings":{"vnext":[{"address":"old","port":443}]},"tag":"proxy"}],"log":{"loglevel":"warning"}}"#.utf8)
        let output = try ConfigTemplate.replacingAddress(in: template, with: "2606::2")
        XCTAssertEqual(ConfigTemplate.address(in: output), "2606::2")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: output) as? [String: Any])
        XCTAssertNotNil(object["log"])
    }

    func testConfigWriterFindsProxyByTag() throws {
        let template = Data(#"{"outbounds":[{"tag":"direct","settings":{}},{"tag":"proxy","settings":{"vnext":[{"address":"old"}]}}]}"#.utf8)
        let output = try ConfigTemplate.replacingAddress(in: template, with: "2606::3")
        XCTAssertEqual(ConfigTemplate.address(in: output), "2606::3")

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: output) as? [String: Any])
        let outbounds = try XCTUnwrap(object["outbounds"] as? [[String: Any]])
        let settings = try XCTUnwrap(outbounds[1]["settings"] as? [String: Any])
        let vnext = try XCTUnwrap(settings["vnext"] as? [[String: Any]])
        XCTAssertEqual(vnext[0]["address"] as? String, "2606::3")
    }
}
