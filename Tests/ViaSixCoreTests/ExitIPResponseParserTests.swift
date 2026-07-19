import XCTest

@testable import ViaSixCore

final class ExitIPResponseParserTests: XCTestCase {
    func testParsesMyIPLAJSONResponse() throws {
        let data = Data(#"{"ip":"2606::1","location":{"country_name":"美国","city":"圣何塞"}}"#.utf8)
        XCTAssertEqual(
            try ExitIPResponseParser.parse(data),
            ExitIPInfo(ip: "2606::1", location: "圣何塞 美国")
        )
    }

    func testFallsBackToPlainIP() throws {
        XCTAssertEqual(
            try ExitIPResponseParser.parse(Data("1.1.1.1\n".utf8)),
            ExitIPInfo(ip: "1.1.1.1")
        )
    }

    func testRejectsWhitespaceOnlyResponse() {
        XCTAssertThrowsError(try ExitIPResponseParser.parse(Data(" \n".utf8)))
    }

    func testRejectsNonIPAddressTokens() {
        XCTAssertThrowsError(try ExitIPResponseParser.parse(Data("service-unavailable".utf8)))
        XCTAssertThrowsError(try ExitIPResponseParser.parse(Data(#"{"ip":"error"}"#.utf8)))
    }

    func testAcceptsPartialLocationPayload() throws {
        let data = Data(#"{"ip":"1.1.1.1","location":{"country_name":"澳大利亚"}}"#.utf8)
        XCTAssertEqual(
            try ExitIPResponseParser.parse(data),
            ExitIPInfo(ip: "1.1.1.1", location: "澳大利亚")
        )
    }

    func testDetectorRejectsUnsupportedEndpointBeforeMakingRequest() async {
        let detector = ExitIPDetector()

        do {
            _ = try await detector.detect(endpoint: URL(string: "file:///tmp/exit-ip")!)
            XCTFail("Expected unsupported endpoint to be rejected")
        } catch {
            XCTAssertEqual(error as? ExitIPDetectionError, .invalidEndpoint)
        }
    }
}
