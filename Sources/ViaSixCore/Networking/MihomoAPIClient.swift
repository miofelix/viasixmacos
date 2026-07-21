import Foundation

public struct MihomoAPIConfiguration: Equatable, Sendable {
    public let host: String
    public let port: Int
    public let secret: String

    public init(host: String = "127.0.0.1", port: Int, secret: String) {
        self.host = host
        self.port = port
        self.secret = secret
    }

    public var displayAddress: String { "\(host):\(port)" }
}

public struct MihomoProxyDelay: Codable, Equatable, Sendable {
    public let time: String?
    public let delay: Int
}

public struct MihomoProxyGroup: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let type: String
    public let selected: String
    public let candidates: [String]
    public let delays: [String: Int]
    public let candidateTypes: [String: String]

    public init(
        name: String,
        type: String,
        selected: String,
        candidates: [String],
        delays: [String: Int] = [:],
        candidateTypes: [String: String] = [:]
    ) {
        self.name = name
        self.type = type
        self.selected = selected
        self.candidates = candidates
        self.delays = delays
        self.candidateTypes = candidateTypes
    }
}

public struct MihomoConnection: Identifiable, Codable, Equatable, Sendable {
    public struct Metadata: Codable, Equatable, Sendable {
        public let network: String?
        public let type: String?
        public let sourceIP: String?
        public let destinationIP: String?
        public let sourcePort: String?
        public let destinationPort: String?
        public let host: String?
        public let dnsMode: String?
        public let processPath: String?
        public let process: String?

        public var destination: String {
            let address = nonEmpty(host) ?? nonEmpty(destinationIP) ?? "未知目标"
            guard let port = nonEmpty(destinationPort) else { return address }
            return "\(address):\(port)"
        }

        public var applicationName: String? {
            if let process = nonEmpty(process) { return process }
            guard let path = nonEmpty(processPath) else { return nil }
            return URL(fileURLWithPath: path).lastPathComponent
        }

        private func nonEmpty(_ value: String?) -> String? {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty
            else { return nil }
            return value
        }
    }

    public let id: String
    public let metadata: Metadata
    public let upload: Int64
    public let download: Int64
    public let start: String?
    public let chains: [String]
    public let rule: String?
    public let rulePayload: String?

    public var route: String {
        chains.isEmpty ? "DIRECT" : chains.joined(separator: " -> ")
    }
}

public struct MihomoRule: Identifiable, Codable, Equatable, Sendable {
    public var id: String { "\(index)-\(type)-\(payload)-\(proxy)" }
    public let index: Int
    public let type: String
    public let payload: String
    public let proxy: String
    public let size: Int?

    private enum CodingKeys: String, CodingKey {
        case type, payload, proxy, size
    }

    public init(index: Int, type: String, payload: String, proxy: String, size: Int? = nil) {
        self.index = index
        self.type = type
        self.payload = payload
        self.proxy = proxy
        self.size = size
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = 0
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "UNKNOWN"
        payload = try container.decodeIfPresent(String.self, forKey: .payload) ?? ""
        proxy = try container.decodeIfPresent(String.self, forKey: .proxy) ?? "DIRECT"
        size = try container.decodeIfPresent(Int.self, forKey: .size)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(payload, forKey: .payload)
        try container.encode(proxy, forKey: .proxy)
        try container.encodeIfPresent(size, forKey: .size)
    }

    fileprivate func withIndex(_ index: Int) -> Self {
        Self(index: index, type: type, payload: payload, proxy: proxy, size: size)
    }
}

public struct MihomoRuntimeSnapshot: Equatable, Sendable {
    public let version: String
    public let proxyGroups: [MihomoProxyGroup]
    public let connections: [MihomoConnection]
    public let rules: [MihomoRule]
    public let uploadTotal: Int64
    public let downloadTotal: Int64
    public let memoryUsage: Int64
    public let fetchedAt: Date

    public init(
        version: String,
        proxyGroups: [MihomoProxyGroup],
        connections: [MihomoConnection],
        rules: [MihomoRule],
        uploadTotal: Int64,
        downloadTotal: Int64,
        memoryUsage: Int64 = 0,
        fetchedAt: Date = Date()
    ) {
        self.version = version
        self.proxyGroups = proxyGroups
        self.connections = connections
        self.rules = rules
        self.uploadTotal = uploadTotal
        self.downloadTotal = downloadTotal
        self.memoryUsage = memoryUsage
        self.fetchedAt = fetchedAt
    }
}

public struct MihomoRuntimeMetadata: Equatable, Sendable {
    public let version: String
    public let proxyGroups: [MihomoProxyGroup]
    public let rules: [MihomoRule]
    public let fetchedAt: Date

    public init(
        version: String,
        proxyGroups: [MihomoProxyGroup],
        rules: [MihomoRule],
        fetchedAt: Date = Date()
    ) {
        self.version = version
        self.proxyGroups = proxyGroups
        self.rules = rules
        self.fetchedAt = fetchedAt
    }
}

public struct MihomoConnectionsSnapshot: Decodable, Equatable, Sendable {
    public let downloadTotal: Int64
    public let uploadTotal: Int64
    public let memoryUsage: Int64
    public let connections: [MihomoConnection]
    public let fetchedAt: Date

    public init(
        downloadTotal: Int64,
        uploadTotal: Int64,
        memoryUsage: Int64,
        connections: [MihomoConnection],
        fetchedAt: Date = Date()
    ) {
        self.downloadTotal = downloadTotal
        self.uploadTotal = uploadTotal
        self.memoryUsage = memoryUsage
        self.connections = connections
        self.fetchedAt = fetchedAt
    }

    private enum CodingKeys: String, CodingKey {
        case downloadTotal, uploadTotal, memory, connections
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        downloadTotal = try container.decodeIfPresent(Int64.self, forKey: .downloadTotal) ?? 0
        uploadTotal = try container.decodeIfPresent(Int64.self, forKey: .uploadTotal) ?? 0
        memoryUsage = try container.decodeIfPresent(Int64.self, forKey: .memory) ?? 0
        connections =
            try container.decodeIfPresent([MihomoConnection].self, forKey: .connections) ?? []
        fetchedAt = Date()
    }
}

public struct MihomoProviderSubscriptionInfo: Equatable, Sendable {
    public let upload: Int64
    public let download: Int64
    public let total: Int64
    public let expire: Int64

    public var used: Int64 { max(0, upload + download) }
}

public struct MihomoProxyProvider: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let type: String
    public let vehicleType: String
    public let proxyCount: Int
    public let testURL: String
    public let expectedStatus: String
    public let updatedAt: String?
    public let subscriptionInfo: MihomoProviderSubscriptionInfo?
}

public struct MihomoRuleProvider: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let type: String
    public let vehicleType: String
    public let behavior: String
    public let format: String
    public let ruleCount: Int
    public let updatedAt: String?
}

public struct MihomoProviderSnapshot: Equatable, Sendable {
    public let proxyProviders: [MihomoProxyProvider]
    public let ruleProviders: [MihomoRuleProvider]
    public let fetchedAt: Date

    public init(
        proxyProviders: [MihomoProxyProvider],
        ruleProviders: [MihomoRuleProvider],
        fetchedAt: Date = Date()
    ) {
        self.proxyProviders = proxyProviders
        self.ruleProviders = ruleProviders
        self.fetchedAt = fetchedAt
    }
}

public enum MihomoAPIError: LocalizedError, Equatable, Sendable {
    case invalidEndpoint
    case invalidDelayTestParameters
    case invalidResponse
    case rejected(status: Int, message: String)
    case responseTooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "Mihomo Controller 地址无效"
        case .invalidDelayTestParameters:
            "代理延迟测试参数无效"
        case .invalidResponse:
            "Mihomo Controller 返回了无法识别的数据"
        case .rejected(let status, let message):
            message.isEmpty ? "Mihomo Controller 请求失败（HTTP \(status)）" : message
        case .responseTooLarge:
            "Mihomo Controller 返回的数据超过安全限制"
        }
    }
}

public actor MihomoAPIClient {
    private static let maximumResponseBytes = 32 * 1_024 * 1_024

    public let configuration: MihomoAPIConfiguration
    private let session: URLSession
    private let webSocketSession: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(configuration: MihomoAPIConfiguration, session: URLSession? = nil) {
        self.configuration = configuration
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 4
            config.timeoutIntervalForResource = 8
            config.waitsForConnectivity = false
            config.urlCache = nil
            self.session = URLSession(configuration: config)
        }

        let webSocketConfig = URLSessionConfiguration.ephemeral
        webSocketConfig.timeoutIntervalForRequest = 4
        webSocketConfig.timeoutIntervalForResource = 7 * 24 * 60 * 60
        webSocketConfig.waitsForConnectivity = false
        webSocketConfig.urlCache = nil
        webSocketSession = URLSession(configuration: webSocketConfig)
    }

    public func snapshot() async throws -> MihomoRuntimeSnapshot {
        async let metadata = runtimeMetadata()
        async let connections: MihomoConnectionsSnapshot = get(["connections"])
        let (metadataValue, connectionsValue) = try await (metadata, connections)
        return MihomoRuntimeSnapshot(
            version: metadataValue.version,
            proxyGroups: metadataValue.proxyGroups,
            connections: connectionsValue.connections,
            rules: metadataValue.rules,
            uploadTotal: connectionsValue.uploadTotal,
            downloadTotal: connectionsValue.downloadTotal,
            memoryUsage: connectionsValue.memoryUsage
        )
    }

    public func runtimeMetadata() async throws -> MihomoRuntimeMetadata {
        async let version: VersionEnvelope = get(["version"])
        async let proxies: ProxiesEnvelope = get(["proxies"])
        async let rules: RulesEnvelope = get(["rules"])
        let (versionValue, proxiesValue, rulesValue) = try await (version, proxies, rules)
        return MihomoRuntimeMetadata(
            version: versionValue.version,
            proxyGroups: proxiesValue.groups,
            rules: rulesValue.rules.enumerated().map { $0.element.withIndex($0.offset) }
        )
    }

    public func connectionSnapshots()
        -> AsyncThrowingStream<MihomoConnectionsSnapshot, Error>
    {
        do {
            let request = try request(path: ["connections"], queryItems: [], scheme: "ws")
            let socket = webSocketSession.webSocketTask(with: request)
            return AsyncThrowingStream { continuation in
                let receiveTask = Task {
                    socket.resume()
                    do {
                        while !Task.isCancelled {
                            let message = try await socket.receive()
                            let data: Data
                            switch message {
                            case .data(let value):
                                data = value
                            case .string(let value):
                                data = Data(value.utf8)
                            @unknown default:
                                throw MihomoAPIError.invalidResponse
                            }
                            guard data.count <= Self.maximumResponseBytes else {
                                throw MihomoAPIError.responseTooLarge
                            }
                            let snapshot = try JSONDecoder().decode(
                                MihomoConnectionsSnapshot.self,
                                from: data
                            )
                            continuation.yield(snapshot)
                        }
                        continuation.finish()
                    } catch is CancellationError {
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { @Sendable _ in
                    receiveTask.cancel()
                    socket.cancel(with: .goingAway, reason: nil)
                }
            }
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }
    }

    public func providerSnapshot() async throws -> MihomoProviderSnapshot {
        async let proxyProviders: ProxyProvidersEnvelope = get(["providers", "proxies"])
        async let ruleProviders: RuleProvidersEnvelope = get(["providers", "rules"])
        let (proxyValue, ruleValue) = try await (proxyProviders, ruleProviders)
        return MihomoProviderSnapshot(
            proxyProviders: proxyValue.summaries,
            ruleProviders: ruleValue.summaries
        )
    }

    public func testProxyGroup(
        group: String,
        url: String,
        timeoutMilliseconds: Int
    ) async throws -> [String: Int] {
        guard let testURL = URL(string: url),
            ["http", "https"].contains(testURL.scheme?.lowercased()),
            (100...6_000).contains(timeoutMilliseconds)
        else {
            throw MihomoAPIError.invalidDelayTestParameters
        }
        return try await get(
            ["group", group, "delay"],
            queryItems: [
                URLQueryItem(name: "url", value: testURL.absoluteString),
                URLQueryItem(name: "timeout", value: String(timeoutMilliseconds)),
            ],
            timeoutInterval: Double(timeoutMilliseconds) / 1_000 + 2
        )
    }

    public func selectProxy(group: String, proxy: String) async throws {
        try await send(
            method: "PUT",
            path: ["proxies", group],
            body: try encoder.encode(ProxySelection(name: proxy))
        )
    }

    public func closeConnection(id: String) async throws {
        try await send(method: "DELETE", path: ["connections", id])
    }

    public func closeAllConnections() async throws {
        try await send(method: "DELETE", path: ["connections"])
    }

    public func updateProxyProvider(name: String) async throws {
        try await send(method: "PUT", path: ["providers", "proxies", name])
    }

    public func updateRuleProvider(name: String) async throws {
        try await send(method: "PUT", path: ["providers", "rules", name])
    }

    private func get<Value: Decodable>(
        _ path: [String],
        queryItems: [URLQueryItem] = [],
        timeoutInterval: TimeInterval? = nil
    ) async throws -> Value {
        let data = try await data(
            method: "GET",
            path: path,
            queryItems: queryItems,
            timeoutInterval: timeoutInterval
        )
        do {
            return try decoder.decode(Value.self, from: data)
        } catch {
            throw MihomoAPIError.invalidResponse
        }
    }

    private func send(method: String, path: [String], body: Data? = nil) async throws {
        _ = try await data(method: method, path: path, body: body)
    }

    private func data(
        method: String,
        path: [String],
        queryItems: [URLQueryItem] = [],
        timeoutInterval: TimeInterval? = nil,
        body: Data? = nil
    ) async throws -> Data {
        var request = try request(path: path, queryItems: queryItems)
        request.httpMethod = method
        request.httpBody = body
        if let timeoutInterval { request.timeoutInterval = timeoutInterval }
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }

        let (data, response) = try await session.data(for: request)
        guard data.count <= Self.maximumResponseBytes else {
            throw MihomoAPIError.responseTooLarge
        }
        guard let response = response as? HTTPURLResponse else {
            throw MihomoAPIError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? decoder.decode(ErrorEnvelope.self, from: data).message) ?? ""
            throw MihomoAPIError.rejected(status: response.statusCode, message: message)
        }
        return data
    }

    private func request(
        path: [String],
        queryItems: [URLQueryItem],
        scheme: String = "http"
    ) throws -> URLRequest {
        let allowedCharacters = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        )
        let encodedPath = try path.map { segment in
            guard let encoded = segment.addingPercentEncoding(withAllowedCharacters: allowedCharacters)
            else { throw MihomoAPIError.invalidEndpoint }
            return encoded
        }.joined(separator: "/")
        var components = URLComponents()
        components.scheme = scheme
        components.host = configuration.host
        components.port = configuration.port
        components.percentEncodedPath = "/" + encodedPath
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else { throw MihomoAPIError.invalidEndpoint }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(configuration.secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

private struct VersionEnvelope: Decodable {
    let version: String
}

private struct ProxySelection: Encodable {
    let name: String
}

private struct ErrorEnvelope: Decodable {
    let message: String
}

private struct ProxiesEnvelope: Decodable {
    struct ProxyValue: Decodable {
        let name: String?
        let type: String?
        let now: String?
        let all: [String]?
        let history: [MihomoProxyDelay]?
    }

    let proxies: [String: ProxyValue]

    var groups: [MihomoProxyGroup] {
        proxies.compactMap { key, value in
            guard let candidates = value.all, !candidates.isEmpty else { return nil }
            var delays: [String: Int] = [:]
            var candidateTypes: [String: String] = [:]
            for candidate in candidates {
                if let delay = proxies[candidate]?.history?.last?.delay, delay > 0 {
                    delays[candidate] = delay
                }
                if let type = proxies[candidate]?.type, !type.isEmpty {
                    candidateTypes[candidate] = type
                }
            }
            return MihomoProxyGroup(
                name: value.name ?? key,
                type: value.type ?? "Selector",
                selected: value.now ?? "",
                candidates: candidates,
                delays: delays,
                candidateTypes: candidateTypes
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

private struct RulesEnvelope: Decodable {
    let rules: [MihomoRule]
}

private struct ProxyProvidersEnvelope: Decodable {
    struct ProviderValue: Decodable {
        struct ProxyValue: Decodable {
            let name: String?
        }

        let name: String?
        let type: String?
        let vehicleType: String?
        let proxies: [ProxyValue]?
        let testUrl: String?
        let expectedStatus: String?
        let updatedAt: String?
        let subscriptionInfo: SubscriptionValue?
    }

    struct SubscriptionValue: Decodable {
        let upload: Int64?
        let download: Int64?
        let total: Int64?
        let expire: Int64?

        private enum CodingKeys: String, CodingKey {
            case upload = "Upload"
            case download = "Download"
            case total = "Total"
            case expire = "Expire"
        }

        var summary: MihomoProviderSubscriptionInfo {
            MihomoProviderSubscriptionInfo(
                upload: upload ?? 0,
                download: download ?? 0,
                total: total ?? 0,
                expire: expire ?? 0
            )
        }
    }

    let providers: [String: ProviderValue]

    var summaries: [MihomoProxyProvider] {
        providers.map { key, value in
            MihomoProxyProvider(
                name: value.name ?? key,
                type: value.type ?? "Proxy",
                vehicleType: value.vehicleType ?? "Unknown",
                proxyCount: value.proxies?.count ?? 0,
                testURL: value.testUrl ?? "",
                expectedStatus: value.expectedStatus ?? "",
                updatedAt: value.updatedAt,
                subscriptionInfo: value.subscriptionInfo?.summary
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

private struct RuleProvidersEnvelope: Decodable {
    struct ProviderValue: Decodable {
        let name: String?
        let type: String?
        let vehicleType: String?
        let behavior: String?
        let format: String?
        let ruleCount: Int?
        let updatedAt: String?
    }

    let providers: [String: ProviderValue]

    var summaries: [MihomoRuleProvider] {
        providers.map { key, value in
            MihomoRuleProvider(
                name: value.name ?? key,
                type: value.type ?? "Rule",
                vehicleType: value.vehicleType ?? "Unknown",
                behavior: value.behavior ?? "Unknown",
                format: value.format ?? "Unknown",
                ruleCount: value.ruleCount ?? 0,
                updatedAt: value.updatedAt
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
