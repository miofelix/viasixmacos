import XCTest
@testable import ViaSixCore

final class CSVAndConfigTests: XCTestCase {
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

    func testPlaceholderConnectionIsRejectedForLaunch() {
        let template = connectionTemplate(
            userID: ConfigTemplate.placeholderUserID,
            serverName: ConfigTemplate.placeholderServerName,
            path: "/"
        )

        XCTAssertThrowsError(try ConfigTemplate.validateForLaunch(template)) { error in
            XCTAssertEqual(error as? ConfigTemplateError, .connectionNotConfigured)
        }
    }

    func testConfiguredConnectionIsAcceptedForLaunch() {
        let template = connectionTemplate(
            userID: "7b602ceb-cc3f-4274-a79d-c1a38f0fb0da",
            serverName: "proxy.example.net",
            path: "/viasix"
        )

        XCTAssertNoThrow(try ConfigTemplate.validateForLaunch(template))
    }

    func testConfigWriterRequiresTaggedProxyAndLeavesDirectOutboundUntouched() throws {
        let template = Data(#"{"outbounds":[{"tag":"direct","settings":{"vnext":[{"address":"192.0.2.10"}]}}]}"#.utf8)

        XCTAssertThrowsError(try ConfigTemplate.replacingAddress(in: template, with: "2606::4")) { error in
            XCTAssertEqual(error as? ConfigTemplateError, .missingProxyOutbound)
        }

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: template) as? [String: Any])
        let outbounds = try XCTUnwrap(object["outbounds"] as? [[String: Any]])
        let settings = try XCTUnwrap(outbounds.first?["settings"] as? [String: Any])
        let vnext = try XCTUnwrap(settings["vnext"] as? [[String: Any]])
        XCTAssertEqual(vnext.first?["address"] as? String, "192.0.2.10")
        XCTAssertNil(ConfigTemplate.address(in: template))
    }

    private func connectionTemplate(userID: String, serverName: String, path: String) -> Data {
        Data(
            #"{"outbounds":[{"tag":"proxy","settings":{"vnext":[{"address":"2606::5","users":[{"id":"\#(userID)"}]}]},"streamSettings":{"tlsSettings":{"serverName":"\#(serverName)"},"wsSettings":{"host":"\#(serverName)","path":"\#(path)"}}}]}"#.utf8
        )
    }
}
