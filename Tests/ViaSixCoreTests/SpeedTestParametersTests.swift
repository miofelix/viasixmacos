import XCTest
@testable import ViaSixCore

final class SpeedTestParametersTests: XCTestCase {
    func testReferenceDefaultsAndArguments() throws {
        let parameters = SpeedTestParameters(ipFile: "/tmp/ipv6.txt")
        let args = try parameters.commandLineArguments(resultURL: URL(fileURLWithPath: "/tmp/result.csv"))

        XCTAssertEqual(Array(args.prefix(4)), ["-o", "/tmp/result.csv", "-tp", "443"])
        XCTAssertTrue(args.contains("-httping"))
        XCTAssertTrue(args.contains("-f"))
        XCTAssertTrue(args.contains("/tmp/ipv6.txt"))
        XCTAssertTrue(args.contains("-tlr"))
    }

    func testCustomRangeTakesPriorityOverFile() throws {
        let parameters = SpeedTestParameters(ipFile: "/tmp/ipv6.txt", ipRange: "1.1.1.1,2606:4700::/32")
        let args = try parameters.commandLineArguments(resultURL: URL(fileURLWithPath: "/tmp/result.csv"))
        XCTAssertTrue(args.contains("-ip"))
        XCTAssertFalse(args.contains("-f"))
    }

    func testValidationRejectsInvalidPort() {
        let parameters = SpeedTestParameters(ipFile: "/tmp/ip.txt", port: 65_536)
        XCTAssertThrowsError(try parameters.validated()) { error in
            XCTAssertEqual(error as? SpeedTestParameterError, .outOfRange("端口应在 1 到 65535 之间"))
        }
    }
}
