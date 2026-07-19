import Foundation

public struct ProxyEndpoint: Equatable, Sendable {
    public let host: String
    public let port: Int

    public init(host: String = AppMetadata.proxyHost, port: Int = AppMetadata.proxyPort) {
        self.host = host
        self.port = port
    }
}

public struct ExitIPInfo: Codable, Equatable, Sendable {
    public let ip: String
    public let location: String

    public init(ip: String, location: String = "") {
        self.ip = ip
        self.location = location
    }
}

public enum ExitIPDetectionError: LocalizedError, Equatable, Sendable {
    case invalidResponse
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "出口 IP 服务返回了无法识别的数据"
        case .httpStatus(let code): "出口 IP 服务返回 HTTP \(code)"
        }
    }
}

public actor ExitIPDetector {
    private let endpoint: URL
    private let timeout: TimeInterval

    public init(
        endpoint: URL = URL(string: "https://api.myip.la/cn?json")!,
        timeout: TimeInterval = 15
    ) {
        self.endpoint = endpoint
        self.timeout = timeout
    }

    public func detect(proxy: ProxyEndpoint? = nil) async throws -> ExitIPInfo {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        if let proxy {
            configuration.connectionProxyDictionary = [
                "HTTPEnable": true,
                "HTTPProxy": proxy.host,
                "HTTPPort": proxy.port,
                "HTTPSEnable": true,
                "HTTPSProxy": proxy.host,
                "HTTPSPort": proxy.port,
            ]
        }

        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(from: endpoint)
        guard let response = response as? HTTPURLResponse else {
            throw ExitIPDetectionError.invalidResponse
        }
        guard (200...299).contains(response.statusCode) else {
            throw ExitIPDetectionError.httpStatus(response.statusCode)
        }
        return try ExitIPResponseParser.parse(data)
    }
}

public enum ExitIPResponseParser {
    public static func parse(_ data: Data) throws -> ExitIPInfo {
        if let response = try? JSONDecoder().decode(APIResponse.self, from: data) {
            let ip = response.ip.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ip.isEmpty else { throw ExitIPDetectionError.invalidResponse }
            let country = response.location?.countryName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let city = response.location?.city.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let location = [city, country].filter { !$0.isEmpty }.joined(separator: " ")
            return ExitIPInfo(ip: ip, location: location)
        }

        let raw = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !raw.contains(where: { $0.isWhitespace }) else {
            throw ExitIPDetectionError.invalidResponse
        }
        return ExitIPInfo(ip: raw)
    }

    private struct APIResponse: Decodable {
        let ip: String
        let location: Location?

        struct Location: Decodable {
            let countryName: String
            let city: String

            private enum CodingKeys: String, CodingKey {
                case countryName = "country_name"
                case city
            }
        }
    }
}

