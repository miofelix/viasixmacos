import Foundation
import XCTest

@testable import ViaSixCore

final class MihomoAPIClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MihomoAPIURLProtocol.fixture.reset()
    }

    func testSnapshotDecodesRuntimeState() async throws {
        MihomoAPIURLProtocol.fixture.responses = [
            "/version": Data(#"{"meta":true,"version":"v1.19.29"}"#.utf8),
            "/proxies": Data(
                #"{"proxies":{"GLOBAL":{"name":"GLOBAL","type":"Selector","now":"edge","all":["edge","DIRECT"],"history":[]},"edge":{"name":"edge","type":"VLESS","history":[{"time":"2026-07-21T10:00:00Z","delay":128}]},"DIRECT":{"name":"DIRECT","type":"Direct","history":[]}}}"#
                    .utf8
            ),
            "/connections": Data(
                #"{"downloadTotal":4096,"uploadTotal":1024,"memory":8388608,"connections":[{"id":"abc","metadata":{"network":"tcp","type":"HTTP","sourceIP":"127.0.0.1","destinationIP":"1.1.1.1","sourcePort":"50000","destinationPort":"443","host":"example.com","dnsMode":"normal","processPath":"/Applications/Test.app/Contents/MacOS/Test","process":"Test"},"upload":100,"download":200,"start":"2026-07-21T10:00:00Z","chains":["edge","GLOBAL"],"rule":"Match","rulePayload":""}]}"#
                    .utf8
            ),
            "/rules": Data(
                #"{"rules":[{"index":0,"type":"DOMAIN-SUFFIX","payload":"example.com","proxy":"GLOBAL","size":-1}]}"#
                    .utf8
            ),
        ]
        let client = makeClient()

        let snapshot = try await client.snapshot()

        XCTAssertEqual(snapshot.version, "v1.19.29")
        XCTAssertEqual(snapshot.proxyGroups.map(\.name), ["GLOBAL"])
        XCTAssertEqual(snapshot.proxyGroups.first?.selected, "edge")
        XCTAssertEqual(snapshot.proxyGroups.first?.delays["edge"], 128)
        XCTAssertEqual(snapshot.proxyGroups.first?.candidateTypes["edge"], "VLESS")
        XCTAssertEqual(snapshot.connections.first?.metadata.destination, "example.com:443")
        XCTAssertEqual(snapshot.connections.first?.route, "edge -> GLOBAL")
        XCTAssertEqual(snapshot.rules.first?.index, 0)
        XCTAssertEqual(snapshot.downloadTotal, 4_096)
        XCTAssertEqual(snapshot.uploadTotal, 1_024)
        XCTAssertEqual(snapshot.memoryUsage, 8_388_608)
        XCTAssertTrue(
            MihomoAPIURLProtocol.fixture.authorizationHeaders.allSatisfy {
                $0 == "Bearer test-secret"
            })
    }

    func testMutationEndpointsUseExpectedMethodsAndBodies() async throws {
        MihomoAPIURLProtocol.fixture.responses = [
            "/proxies/GLOBAL": Data(),
            "/connections/abc": Data(),
            "/connections": Data(),
            "/providers/proxies/subscription": Data(),
            "/providers/rules/geosite": Data(),
        ]
        let client = makeClient()

        try await client.selectProxy(group: "GLOBAL", proxy: "edge")
        try await client.closeConnection(id: "abc")
        try await client.closeAllConnections()
        try await client.updateProxyProvider(name: "subscription")
        try await client.updateRuleProvider(name: "geosite")

        let requests = MihomoAPIURLProtocol.fixture.requests
        XCTAssertEqual(requests.map(\.method), ["PUT", "DELETE", "DELETE", "PUT", "PUT"])
        XCTAssertEqual(
            requests.map(\.path),
            [
                "/proxies/GLOBAL",
                "/connections/abc",
                "/connections",
                "/providers/proxies/subscription",
                "/providers/rules/geosite",
            ]
        )
    }

    func testProviderSnapshotDecodesProxyRuleAndSubscriptionMetadata() async throws {
        MihomoAPIURLProtocol.fixture.responses = [
            "/providers/proxies": Data(
                #"{"providers":{"subscription":{"name":"subscription","type":"Proxy","vehicleType":"HTTP","proxies":[{"name":"edge-a"},{"name":"edge-b"}],"testUrl":"https://example.com/generate_204","expectedStatus":"204","updatedAt":"2026-07-21T10:00:00Z","subscriptionInfo":{"Upload":1024,"Download":2048,"Total":8192,"Expire":1800000000}}}}"#
                    .utf8
            ),
            "/providers/rules": Data(
                #"{"providers":{"geosite":{"name":"geosite","type":"Rule","vehicleType":"HTTP","behavior":"Domain","format":"YamlRule","ruleCount":42,"updatedAt":"2026-07-21T11:00:00Z"}}}"#
                    .utf8
            ),
        ]
        let client = makeClient()

        let snapshot = try await client.providerSnapshot()

        XCTAssertEqual(snapshot.proxyProviders.first?.name, "subscription")
        XCTAssertEqual(snapshot.proxyProviders.first?.proxyCount, 2)
        XCTAssertEqual(snapshot.proxyProviders.first?.vehicleType, "HTTP")
        XCTAssertEqual(snapshot.proxyProviders.first?.subscriptionInfo?.used, 3_072)
        XCTAssertEqual(snapshot.proxyProviders.first?.subscriptionInfo?.total, 8_192)
        XCTAssertEqual(snapshot.ruleProviders.first?.name, "geosite")
        XCTAssertEqual(snapshot.ruleProviders.first?.ruleCount, 42)
        XCTAssertEqual(snapshot.ruleProviders.first?.behavior, "Domain")
    }

    func testRuntimeMetadataRefreshAvoidsConnectionsEndpoint() async throws {
        MihomoAPIURLProtocol.fixture.responses = [
            "/version": Data(#"{"meta":true,"version":"v1.19.29"}"#.utf8),
            "/proxies": Data(
                #"{"proxies":{"GLOBAL":{"name":"GLOBAL","type":"Selector","now":"DIRECT","all":["DIRECT"],"history":[]},"DIRECT":{"name":"DIRECT","type":"Direct","history":[]}}}"#
                    .utf8
            ),
            "/rules": Data(
                #"{"rules":[{"type":"MATCH","payload":"","proxy":"DIRECT"}]}"#.utf8
            ),
        ]
        let client = makeClient()

        let metadata = try await client.runtimeMetadata()

        XCTAssertEqual(metadata.version, "v1.19.29")
        XCTAssertEqual(metadata.proxyGroups.map(\.name), ["GLOBAL"])
        XCTAssertEqual(metadata.rules.map(\.proxy), ["DIRECT"])
        XCTAssertEqual(
            Set(MihomoAPIURLProtocol.fixture.requests.map(\.path)),
            Set(["/version", "/proxies", "/rules"])
        )
    }

    func testProxyGroupDelayUsesEncodedPathAndQueryParameters() async throws {
        MihomoAPIURLProtocol.fixture.responses = [
            "/group/Group%2F%E4%B8%BB/delay": Data(#"{"edge":128}"#.utf8)
        ]
        let client = makeClient()

        let delays = try await client.testProxyGroup(
            group: "Group/主",
            url: "https://example.com/generate_204?a=1",
            timeoutMilliseconds: 5_000
        )

        XCTAssertEqual(delays, ["edge": 128])
        let request = try XCTUnwrap(MihomoAPIURLProtocol.fixture.requests.first)
        XCTAssertEqual(request.path, "/group/Group%2F%E4%B8%BB/delay")
        let components = try XCTUnwrap(URLComponents(string: request.url))
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) }),
            ["url": "https://example.com/generate_204?a=1", "timeout": "5000"]
        )
    }

    func testDynamicEndpointValuesAreEncodedAsSinglePathSegments() async throws {
        MihomoAPIURLProtocol.fixture.responses = [
            "/proxies/Group%2F%E4%B8%BB": Data(),
            "/connections/id%2Fpart%3Fvalue": Data(),
        ]
        let client = makeClient()

        try await client.selectProxy(group: "Group/主", proxy: "edge")
        try await client.closeConnection(id: "id/part?value")

        XCTAssertEqual(
            MihomoAPIURLProtocol.fixture.requests.map(\.path),
            ["/proxies/Group%2F%E4%B8%BB", "/connections/id%2Fpart%3Fvalue"]
        )
    }

    private func makeClient() -> MihomoAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MihomoAPIURLProtocol.self]
        return MihomoAPIClient(
            configuration: MihomoAPIConfiguration(port: 9_090, secret: "test-secret"),
            session: URLSession(configuration: configuration)
        )
    }
}

private final class MihomoAPIURLProtocol: URLProtocol {
    static let fixture = MihomoAPIProtocolFixture()

    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let responseData = Self.fixture.response(for: request)
        guard let url = request.url,
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class MihomoAPIProtocolFixture: @unchecked Sendable {
    struct RecordedRequest: Sendable {
        let method: String
        let path: String
        let url: String
        let body: Data?
    }

    private let lock = NSLock()
    private var storedResponses: [String: Data] = [:]
    private var storedRequests: [RecordedRequest] = []
    private var storedAuthorizationHeaders: [String] = []

    var responses: [String: Data] {
        get { withLock { storedResponses } }
        set { withLock { storedResponses = newValue } }
    }

    var requests: [RecordedRequest] { withLock { storedRequests } }
    var authorizationHeaders: [String] { withLock { storedAuthorizationHeaders } }

    func response(for request: URLRequest) -> Data {
        withLock {
            let path =
                request.url.flatMap {
                    URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedPath
                } ?? ""
            storedRequests.append(
                RecordedRequest(
                    method: request.httpMethod ?? "GET",
                    path: path,
                    url: request.url?.absoluteString ?? "",
                    body: request.httpBody
                )
            )
            storedAuthorizationHeaders.append(
                request.value(forHTTPHeaderField: "Authorization") ?? ""
            )
            return storedResponses[path] ?? Data("{}".utf8)
        }
    }

    func reset() {
        withLock {
            storedResponses = [:]
            storedRequests = []
            storedAuthorizationHeaders = []
        }
    }

    @discardableResult
    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
