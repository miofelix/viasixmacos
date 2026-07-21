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

    func testReportsParsedAddressFamily() throws {
        let ipv4 = try ExitIPResponseParser.parse(Data("1.1.1.1".utf8))
        let ipv6 = try ExitIPResponseParser.parse(Data("2606::1".utf8))

        XCTAssertEqual(ipv4.addressFamily, .ipv4)
        XCTAssertEqual(ipv6.addressFamily, .ipv6)
    }

    func testDetectionModesResolveToFamilySpecificEndpoints() {
        let custom = "https://status.example.test/ip"

        XCTAssertEqual(
            AppMetadata.exitIPEndpoint(for: .automatic, automaticEndpoint: custom),
            custom
        )
        XCTAssertEqual(
            AppMetadata.exitIPEndpoint(for: .ipv4, automaticEndpoint: custom),
            AppMetadata.ipv4ExitIPEndpoint
        )
        XCTAssertEqual(
            AppMetadata.exitIPEndpoint(for: .ipv6, automaticEndpoint: custom),
            AppMetadata.ipv6ExitIPEndpoint
        )
    }

    func testDefaultGeolocationEndpointAcceptsIPv4AndIPv6Literals() {
        XCTAssertEqual(
            AppMetadata.exitIPGeolocationURL(for: "1.1.1.1")?.absoluteString,
            "https://ipwho.is/1.1.1.1?lang=zh-CN"
        )
        XCTAssertEqual(
            AppMetadata.exitIPGeolocationURL(for: "2606:4700:4700::1111")?.absoluteString,
            "https://ipwho.is/2606:4700:4700::1111?lang=zh-CN"
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

    func testParsesDetailedIPSBGeolocationResponse() throws {
        let data = Data(
            #"{"ip":"2606:0000:0000:0000:0000:0000:0000:0001","country":"中国","region":"山东","city":"青岛","organization":"China Telecom","isp":"China Telecom","asn":4134,"timezone":"Asia/Shanghai"}"#
                .utf8
        )

        XCTAssertEqual(
            try ExitIPGeolocationResponseParser.parse(data, expectedIP: "2606::1"),
            ExitIPInfo(
                ip: "2606::1",
                location: "中国 · 山东 · 青岛",
                details: "China Telecom · AS4134 · Asia/Shanghai"
            )
        )
    }

    func testParsesDetailedIPWhoGeolocationResponse() throws {
        let data = Data(
            #"{"success":true,"ip":"1.1.1.1","country":"澳大利亚","region":"昆士兰州","city":"布里斯班","postal":"4000","timezone":{"id":"Australia/Brisbane","utc":"+10:00"},"connection":{"org":"Apnic Research And Development","isp":"Cloudflare, Inc.","asn":13335}}"#
                .utf8
        )

        XCTAssertEqual(
            try ExitIPGeolocationResponseParser.parse(data, expectedIP: "1.1.1.1"),
            ExitIPInfo(
                ip: "1.1.1.1",
                location: "澳大利亚 · 昆士兰州 · 布里斯班 · 邮编 4000",
                details: "Cloudflare, Inc. · AS13335 · Australia/Brisbane"
            )
        )
    }

    func testParsesDetailedIPWhoIPv6ResponseWithEquivalentAddressNotation() throws {
        let data = Data(
            #"{"success":true,"ip":"2606:4700:4700:0000:0000:0000:0000:1111","country":"美国","region":"加利福尼亚州","city":"圣何塞","postal":"95113","timezone":{"id":"America/Los_Angeles"},"connection":{"org":"Cloudflare, Inc.","isp":"Cloudflare, Inc.","asn":"13335"}}"#
                .utf8
        )

        XCTAssertEqual(
            try ExitIPGeolocationResponseParser.parse(
                data,
                expectedIP: "2606:4700:4700::1111"
            ),
            ExitIPInfo(
                ip: "2606:4700:4700::1111",
                location: "美国 · 加利福尼亚州 · 圣何塞 · 邮编 95113",
                details: "Cloudflare, Inc. · AS13335 · America/Los_Angeles"
            )
        )
    }

    func testRejectsUnsuccessfulIPWhoGeolocationResponse() {
        let data = Data(
            #"{"success":false,"message":"Rate limit exceeded","ip":"1.1.1.1"}"#.utf8
        )

        XCTAssertThrowsError(
            try ExitIPGeolocationResponseParser.parse(data, expectedIP: "1.1.1.1")
        ) { error in
            XCTAssertEqual(error as? ExitIPDetectionError, .invalidResponse)
        }
    }

    func testGeolocationParserAcceptsMissingOptionalFields() throws {
        let data = Data(#"{"ip":"1.1.1.1","isp":"Example ISP"}"#.utf8)

        XCTAssertEqual(
            try ExitIPGeolocationResponseParser.parse(data, expectedIP: "1.1.1.1"),
            ExitIPInfo(ip: "1.1.1.1", details: "Example ISP")
        )
    }

    func testGeolocationParserUsesASNOrganizationAsProviderFallback() throws {
        let data = Data(
            #"{"ip":"1.1.1.1","asn_organization":"Cloudflare, Inc.","asn":13335}"#.utf8
        )

        XCTAssertEqual(
            try ExitIPGeolocationResponseParser.parse(data, expectedIP: "1.1.1.1"),
            ExitIPInfo(ip: "1.1.1.1", details: "Cloudflare, Inc. · AS13335")
        )
    }

    func testGeolocationParserRejectsMismatchedIP() {
        let data = Data(#"{"ip":"1.0.0.1","country":"澳大利亚"}"#.utf8)

        XCTAssertThrowsError(
            try ExitIPGeolocationResponseParser.parse(data, expectedIP: "1.1.1.1")
        ) { error in
            XCTAssertEqual(error as? ExitIPDetectionError, .invalidResponse)
        }
    }

    func testGeolocationParserRejectsInvalidJSON() {
        XCTAssertThrowsError(
            try ExitIPGeolocationResponseParser.parse(
                Data("service-unavailable".utf8),
                expectedIP: "1.1.1.1"
            )
        ) { error in
            XCTAssertEqual(error as? ExitIPDetectionError, .invalidResponse)
        }
    }

    func testExitIPInfoDecodesPayloadWithoutDetails() throws {
        let decoded = try JSONDecoder().decode(
            ExitIPInfo.self,
            from: Data(#"{"ip":"1.1.1.1","location":"澳大利亚"}"#.utf8)
        )

        XCTAssertEqual(decoded, ExitIPInfo(ip: "1.1.1.1", location: "澳大利亚"))
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

    func testDetectorPublishesPrimaryResultWithoutRequestingGeolocation() async throws {
        let primaryURL = URL(string: "https://primary.example.test/ip")!
        let geolocationURL = URL(string: "https://api.ip.sb/geoip")!
        let recorder = ExitIPRequestRecorder()
        let detector = ExitIPDetector(
            endpoint: primaryURL,
            geolocationEndpoint: geolocationURL,
            requestLoader: { request, _ in
                await recorder.record(request)
                return ExitIPDetector.LoadedResponse(
                    data: Data("1.1.1.1\n".utf8),
                    statusCode: 200
                )
            }
        )

        let info = try await detector.detect(expectedFamily: .ipv4)

        XCTAssertEqual(info, ExitIPInfo(ip: "1.1.1.1"))
        let requestedURLs = await recorder.requestedURLs()
        XCTAssertEqual(requestedURLs, [primaryURL])
    }

    func testDetectorAcceptsForcedIPv4AndIPv6ResultsWithoutGeolocationRequests() async throws {
        let ipv4URL = URL(string: AppMetadata.ipv4ExitIPEndpoint)!
        let ipv6URL = URL(string: AppMetadata.ipv6ExitIPEndpoint)!
        let recorder = ExitIPRequestRecorder()
        let detector = ExitIPDetector(
            endpoint: URL(string: "https://primary.example.test/ip")!,
            geolocationEndpoint: URL(string: "https://api.ip.sb/geoip")!,
            requestLoader: { request, _ in
                await recorder.record(request)
                let response = request.url == ipv4URL ? "1.1.1.1" : "2606::1"
                return ExitIPDetector.LoadedResponse(
                    data: Data(response.utf8),
                    statusCode: 200
                )
            }
        )

        let ipv4 = try await detector.detect(endpoint: ipv4URL, expectedFamily: .ipv4)
        let ipv6 = try await detector.detect(endpoint: ipv6URL, expectedFamily: .ipv6)
        let requestedURLs = await recorder.requestedURLs()

        XCTAssertEqual(ipv4.addressFamily, .ipv4)
        XCTAssertEqual(ipv6.addressFamily, .ipv6)
        XCTAssertEqual(requestedURLs, [ipv4URL, ipv6URL])
    }

    func testEnrichmentUsesBaseGeolocationHostForIPv4AndIPv6() async throws {
        let primaryURL = URL(string: "https://primary.example.test/ip")!
        let geolocationURL = URL(string: "https://api.ip.sb/geoip")!
        let recorder = ExitIPRequestRecorder()
        let detector = ExitIPDetector(
            endpoint: primaryURL,
            geolocationEndpoint: geolocationURL,
            requestLoader: { request, _ in
                await recorder.record(request)
                let responseData: Data
                switch request.url?.path {
                case "/geoip/1.1.1.1":
                    responseData = Data(#"{"ip":"1.1.1.1","country":"澳大利亚"}"#.utf8)
                case "/geoip/2606::1":
                    responseData = Data(#"{"ip":"2606::1","country":"美国"}"#.utf8)
                default:
                    responseData = Data("unexpected-request".utf8)
                }
                return ExitIPDetector.LoadedResponse(data: responseData, statusCode: 200)
            }
        )

        let ipv4 = try await detector.enrich(ExitIPInfo(ip: "1.1.1.1"))
        let ipv6 = try await detector.enrich(ExitIPInfo(ip: "2606::1"))

        XCTAssertEqual(ipv4.location, "澳大利亚")
        XCTAssertEqual(ipv6.location, "美国")
        let requestedURLs = await recorder.requestedURLs().map(\.absoluteString)
        XCTAssertEqual(
            requestedURLs,
            [
                "https://api.ip.sb/geoip/1.1.1.1",
                "https://api.ip.sb/geoip/2606::1",
            ]
        )
    }

    func testEnrichmentMergesDetailedGeolocationIntoPrimaryResult() async throws {
        let recorder = ExitIPRequestRecorder()
        let detector = makeDetector { request, _ in
            await recorder.record(request)
            return ExitIPDetector.LoadedResponse(
                data: Data(
                    #"{"ip":"1.1.1.1","country":"澳大利亚","region":"昆士兰州","city":"布里斯班","organization":"Cloudflare","asn":13335,"timezone":"Australia/Brisbane"}"#
                        .utf8
                ),
                statusCode: 200
            )
        }
        let primary = ExitIPInfo(
            ip: "1.1.1.1",
            location: "澳大利亚",
            details: "原始网络信息"
        )

        let enriched = try await detector.enrich(primary)
        let requestedURLs = await recorder.requestedURLs()

        XCTAssertEqual(requestedURLs.map(\.absoluteString), ["https://api.ip.sb/geoip/1.1.1.1"])
        XCTAssertEqual(
            enriched,
            ExitIPInfo(
                ip: "1.1.1.1",
                location: "澳大利亚 · 昆士兰州 · 布里斯班",
                details: "Cloudflare · AS13335 · Australia/Brisbane"
            )
        )
    }

    func testEnrichmentKeepsPrimaryResultWhenGeolocationIPDoesNotMatch() async throws {
        let primary = ExitIPInfo(
            ip: "1.1.1.1",
            location: "已有位置",
            details: "已有网络信息"
        )
        let detector = makeDetector { _, _ in
            ExitIPDetector.LoadedResponse(
                data: Data(#"{"ip":"1.0.0.1","country":"错误位置"}"#.utf8),
                statusCode: 200
            )
        }

        let enriched = try await detector.enrich(primary)
        XCTAssertEqual(enriched, primary)
    }

    func testEnrichmentKeepsPrimaryResultWhenGeolocationRequestFails() async throws {
        let primary = ExitIPInfo(
            ip: "1.1.1.1",
            location: "已有位置",
            details: "已有网络信息"
        )
        let detector = makeDetector { _, _ in
            ExitIPDetector.LoadedResponse(
                data: Data("forbidden".utf8),
                statusCode: 403
            )
        }

        let enriched = try await detector.enrich(primary)
        XCTAssertEqual(enriched, primary)
    }

    func testSlowEnrichmentPropagatesCancellationWithoutChangingPrimaryResult() async throws {
        let primaryURL = URL(string: "https://primary.example.test/ip")!
        let geolocationURL = URL(string: "https://api.ip.sb/geoip")!
        let recorder = ExitIPRequestRecorder()
        let detector = ExitIPDetector(
            endpoint: primaryURL,
            geolocationEndpoint: geolocationURL,
            requestLoader: { request, _ in
                await recorder.record(request)
                if request.url == primaryURL {
                    return ExitIPDetector.LoadedResponse(
                        data: Data("1.1.1.1".utf8),
                        statusCode: 200
                    )
                }
                try await Task.sleep(for: .seconds(30))
                return ExitIPDetector.LoadedResponse(
                    data: Data(#"{"ip":"1.1.1.1","country":"澳大利亚"}"#.utf8),
                    statusCode: 200
                )
            }
        )
        let primary = try await detector.detect(expectedFamily: .ipv4)
        let enrichmentTask = Task {
            try await detector.enrich(primary)
        }

        try await waitForRequestCount(2, in: recorder)
        enrichmentTask.cancel()

        do {
            _ = try await enrichmentTask.value
            XCTFail("Expected slow geolocation enrichment to be cancelled")
        } catch {
            XCTAssertTrue(
                error is CancellationError || (error as? URLError)?.code == .cancelled,
                "Unexpected cancellation error: \(error)"
            )
        }
        XCTAssertEqual(primary, ExitIPInfo(ip: "1.1.1.1"))
    }

    private func makeDetector(
        requestLoader: @escaping ExitIPDetector.RequestLoader
    ) -> ExitIPDetector {
        ExitIPDetector(
            endpoint: URL(string: "https://primary.example.test/ip")!,
            geolocationEndpoint: URL(string: "https://api.ip.sb/geoip")!,
            requestLoader: requestLoader
        )
    }

    private func waitForRequestCount(
        _ expectedCount: Int,
        in recorder: ExitIPRequestRecorder
    ) async throws {
        for _ in 0..<100 {
            if await recorder.requestCount() >= expectedCount {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for \(expectedCount) exit IP requests")
    }
}

private actor ExitIPRequestRecorder {
    private var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        requests.append(request)
    }

    func requestedURLs() -> [URL] {
        requests.compactMap(\.url)
    }

    func requestCount() -> Int {
        requests.count
    }
}
