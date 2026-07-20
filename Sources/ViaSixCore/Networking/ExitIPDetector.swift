import Foundation
import Network

public enum IPAddressFamily: String, Codable, Equatable, Sendable {
    case ipv4
    case ipv6

    public var displayName: String {
        switch self {
        case .ipv4: "IPv4"
        case .ipv6: "IPv6"
        }
    }
}

public struct ProxyEndpoint: Codable, Equatable, Sendable {
    public let host: String
    public let port: Int

    public init(host: String = AppMetadata.proxyHost, port: Int = AppMetadata.proxyPort) {
        self.host = host
        self.port = port
    }

    public var displayAddress: String {
        host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
    }
}

public struct ExitIPInfo: Codable, Equatable, Sendable {
    public let ip: String
    public let location: String
    public let details: String

    public init(ip: String, location: String = "", details: String = "") {
        self.ip = ip
        self.location = location
        self.details = details
    }

    public var addressFamily: IPAddressFamily? {
        if IPv4Address(ip) != nil { return .ipv4 }
        if IPv6Address(ip) != nil { return .ipv6 }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case ip, location, details
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            ip: try values.decode(String.self, forKey: .ip),
            location: try values.decodeIfPresent(String.self, forKey: .location) ?? "",
            details: try values.decodeIfPresent(String.self, forKey: .details) ?? ""
        )
    }
}

public enum ExitIPDetectionError: LocalizedError, Equatable, Sendable {
    case invalidEndpoint
    case invalidResponse
    case addressFamilyMismatch(IPAddressFamily)
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "出口 IP 服务地址必须是有效的 HTTP 或 HTTPS URL"
        case .invalidResponse: "出口 IP 服务返回了无法识别的数据"
        case .addressFamilyMismatch(let expected):
            "出口 IP 服务未返回预期的 \(expected.displayName) 地址"
        case .httpStatus(let code): "出口 IP 服务返回 HTTP \(code)"
        }
    }
}

public protocol ExitIPDetecting: Sendable {
    func detect(
        proxy: ProxyEndpoint?,
        endpoint: URL?,
        expectedFamily: IPAddressFamily?
    ) async throws -> ExitIPInfo

    func enrich(
        _ info: ExitIPInfo,
        proxy: ProxyEndpoint?
    ) async throws -> ExitIPInfo
}

public extension ExitIPDetecting {
    func enrich(
        _ info: ExitIPInfo,
        proxy _: ProxyEndpoint?
    ) async throws -> ExitIPInfo {
        info
    }
}

public actor ExitIPDetector: ExitIPDetecting {
    struct LoadedResponse: Sendable {
        let data: Data
        let statusCode: Int
    }

    typealias RequestLoader = @Sendable (URLRequest, URLSession) async throws -> LoadedResponse

    private static let userAgent = "ViaSix/1.0"
    private static let liveRequestLoader: RequestLoader = { request, session in
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ExitIPDetectionError.invalidResponse
        }
        return LoadedResponse(data: data, statusCode: response.statusCode)
    }

    private let endpoint: URL
    private let timeout: TimeInterval
    private let geolocationEndpoint: URL
    private let requestLoader: RequestLoader

    public init(
        endpoint: URL = URL(string: AppMetadata.defaultExitIPEndpoint)!,
        timeout: TimeInterval = 15
    ) {
        self.endpoint = endpoint
        self.timeout = timeout
        self.geolocationEndpoint = URL(string: AppMetadata.exitIPGeolocationEndpoint)!
        self.requestLoader = Self.liveRequestLoader
    }

    init(
        endpoint: URL,
        timeout: TimeInterval = 15,
        geolocationEndpoint: URL,
        requestLoader: @escaping RequestLoader
    ) {
        self.endpoint = endpoint
        self.timeout = timeout
        self.geolocationEndpoint = geolocationEndpoint
        self.requestLoader = requestLoader
    }

    public func detect(
        proxy: ProxyEndpoint? = nil,
        endpoint: URL? = nil,
        expectedFamily: IPAddressFamily? = nil
    ) async throws -> ExitIPInfo {
        let endpoint = endpoint ?? self.endpoint
        guard let scheme = endpoint.scheme?.lowercased(), ["http", "https"].contains(scheme),
            endpoint.host != nil
        else {
            throw ExitIPDetectionError.invalidEndpoint
        }
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
        let requestLoader = self.requestLoader

        let data = try await Self.load(
            endpoint,
            using: session,
            requestLoader: requestLoader
        )
        let info = try ExitIPResponseParser.parse(data)
        if let expectedFamily, info.addressFamily != expectedFamily {
            throw ExitIPDetectionError.addressFamilyMismatch(expectedFamily)
        }
        return info
    }

    public func enrich(
        _ info: ExitIPInfo,
        proxy: ProxyEndpoint? = nil
    ) async throws -> ExitIPInfo {
        guard let geolocationURL = geolocationURL(for: info.ip) else {
            return info
        }

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
        do {
            let data = try await Self.load(
                geolocationURL,
                using: session,
                requestLoader: requestLoader
            )
            guard
                let geolocation = try? ExitIPGeolocationResponseParser.parse(
                    data,
                    expectedIP: info.ip
                )
            else {
                return info
            }
            try Task.checkCancellation()
            return ExitIPInfo(
                ip: info.ip,
                location: geolocation.location.isEmpty ? info.location : geolocation.location,
                details: geolocation.details.isEmpty ? info.details : geolocation.details
            )
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw error
            }
            try Task.checkCancellation()
            return info
        }
    }

    private func geolocationURL(for ip: String) -> URL? {
        URLComponents(url: geolocationEndpoint, resolvingAgainstBaseURL: false)?.url?
            .appendingPathComponent(ip)
    }

    private static func load(
        _ url: URL,
        using session: URLSession,
        requestLoader: RequestLoader
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let response = try await requestLoader(request, session)
        guard (200...299).contains(response.statusCode) else {
            throw ExitIPDetectionError.httpStatus(response.statusCode)
        }
        return response.data
    }
}

public enum ExitIPResponseParser {
    public static func parse(_ data: Data) throws -> ExitIPInfo {
        if let response = try? JSONDecoder().decode(APIResponse.self, from: data) {
            guard let ip = normalizedIPAddress(response.ip) else {
                throw ExitIPDetectionError.invalidResponse
            }
            let country = response.location?.countryName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let city = response.location?.city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let location = [city, country].filter { !$0.isEmpty }.joined(separator: " ")
            return ExitIPInfo(ip: ip, location: location)
        }

        let raw = String(decoding: data, as: UTF8.self)
        guard let ip = normalizedIPAddress(raw) else {
            throw ExitIPDetectionError.invalidResponse
        }
        return ExitIPInfo(ip: ip)
    }

    private struct APIResponse: Decodable {
        let ip: String
        let location: Location?

        struct Location: Decodable {
            let countryName: String?
            let city: String?

            private enum CodingKeys: String, CodingKey {
                case countryName = "country_name"
                case city
            }
        }
    }
}

public enum ExitIPGeolocationResponseParser {
    public static func parse(_ data: Data, expectedIP: String) throws -> ExitIPInfo {
        let response: APIResponse
        do {
            response = try JSONDecoder().decode(APIResponse.self, from: data)
        } catch {
            throw ExitIPDetectionError.invalidResponse
        }

        guard response.success != false,
            let ip = normalizedIPAddress(expectedIP),
            addressesMatch(response.ip, ip)
        else {
            throw ExitIPDetectionError.invalidResponse
        }

        let location = joinedUniqueValues(
            [
                response.country,
                response.region,
                response.city,
                response.postalCode.map { "邮编 \($0)" },
            ],
            separator: " · "
        )
        let provider = firstNonEmptyValue([
            response.connection?.isp,
            response.connection?.organization,
            response.organization,
            response.isp,
            response.asnOrganization,
        ])
        let asn = response.asn ?? response.connection?.asn
        let details = joinedUniqueValues(
            [provider, asn.map { $0.hasPrefix("AS") ? $0 : "AS\($0)" }, response.timezone],
            separator: " · "
        )
        return ExitIPInfo(ip: ip, location: location, details: details)
    }

    private struct APIResponse: Decodable {
        let success: Bool?
        let ip: String
        let country: String?
        let region: String?
        let city: String?
        let postalCode: String?
        let organization: String?
        let isp: String?
        let asnOrganization: String?
        let asn: String?
        let timezone: String?
        let connection: Connection?

        private enum CodingKeys: String, CodingKey {
            case success, ip, country, region, city, postal
            case postalCode = "postal_code"
            case organization, isp, asn, timezone, connection
            case asnOrganization = "asn_organization"
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            self.success = try values.decodeIfPresent(Bool.self, forKey: .success)
            self.ip = try values.decode(String.self, forKey: .ip)
            self.country = try values.decodeIfPresent(String.self, forKey: .country)
            self.region = try values.decodeIfPresent(String.self, forKey: .region)
            self.city = try values.decodeIfPresent(String.self, forKey: .city)
            self.postalCode =
                (try? values.decode(String.self, forKey: .postal))
                ?? (try? values.decode(String.self, forKey: .postalCode))
                ?? Self.decodeIntegerString(values, forKey: .postal)
                ?? Self.decodeIntegerString(values, forKey: .postalCode)
            self.organization = try values.decodeIfPresent(String.self, forKey: .organization)
            self.isp = try values.decodeIfPresent(String.self, forKey: .isp)
            self.asnOrganization = try values.decodeIfPresent(
                String.self,
                forKey: .asnOrganization
            )
            if let asn = try? values.decode(Int.self, forKey: .asn) {
                self.asn = String(asn)
            } else {
                self.asn = try values.decodeIfPresent(String.self, forKey: .asn)
            }
            self.timezone = try Self.decodeTimezone(values)
            self.connection = try values.decodeIfPresent(Connection.self, forKey: .connection)
        }

        private static func decodeIntegerString(
            _ values: KeyedDecodingContainer<CodingKeys>,
            forKey key: CodingKeys
        ) -> String? {
            guard let value = try? values.decode(Int.self, forKey: key) else { return nil }
            return String(value)
        }

        private static func decodeTimezone(
            _ values: KeyedDecodingContainer<CodingKeys>
        ) throws -> String? {
            if let value = try? values.decode(String.self, forKey: .timezone) {
                return value
            }
            return try values.decodeIfPresent(Timezone.self, forKey: .timezone)?.id
        }

        private struct Timezone: Decodable {
            let id: String?
        }

        struct Connection: Decodable {
            let organization: String?
            let isp: String?
            let asn: String?

            private enum CodingKeys: String, CodingKey {
                case organization = "org"
                case isp
                case asn
            }

            init(from decoder: Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                self.organization = try values.decodeIfPresent(String.self, forKey: .organization)
                self.isp = try values.decodeIfPresent(String.self, forKey: .isp)
                if let value = try? values.decode(Int.self, forKey: .asn) {
                    self.asn = String(value)
                } else {
                    self.asn = try values.decodeIfPresent(String.self, forKey: .asn)
                }
            }
        }
    }
}

private func normalizedIPAddress(_ value: String) -> String? {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard IPv4Address(normalized) != nil || IPv6Address(normalized) != nil else {
        return nil
    }
    return normalized
}

private func addressesMatch(_ candidate: String, _ expected: String) -> Bool {
    let candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
    if let candidateAddress = IPv4Address(candidate),
        let expectedAddress = IPv4Address(expected)
    {
        return candidateAddress.rawValue == expectedAddress.rawValue
    }
    if let candidateAddress = IPv6Address(candidate),
        let expectedAddress = IPv6Address(expected)
    {
        return candidateAddress.rawValue == expectedAddress.rawValue
    }
    return false
}

private func joinedUniqueValues(_ values: [String?], separator: String) -> String {
    var seen = Set<String>()
    return values.compactMap { value in
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        let comparisonKey = normalized.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        guard seen.insert(comparisonKey).inserted else { return nil }
        return normalized
    }.joined(separator: separator)
}

private func firstNonEmptyValue(_ values: [String?]) -> String? {
    values.lazy.compactMap { value in
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }.first
}
