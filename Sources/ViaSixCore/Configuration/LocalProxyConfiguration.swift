import Darwin
import Foundation

public enum XrayLogLevel: String, Codable, CaseIterable, Sendable {
    case none
    case error
    case warning
    case info
    case debug

    public var displayName: String {
        switch self {
        case .none: "关闭"
        case .error: "仅错误"
        case .warning: "警告"
        case .info: "信息"
        case .debug: "调试"
        }
    }
}

public enum LocalProxyConfigurationError: LocalizedError, Equatable, Sendable {
    case invalidListenAddress
    case invalidPort

    public var errorDescription: String? {
        switch self {
        case .invalidListenAddress:
            "本地监听地址必须是 127.0.0.0/8、::1 或 localhost"
        case .invalidPort:
            "本地监听端口必须在 1–65535 之间"
        }
    }
}

public struct LocalProxyConfiguration: Codable, Equatable, Sendable {
    public var listenAddress: String
    public var port: Int
    public var udpEnabled: Bool
    public var sniffingEnabled: Bool
    public var bypassPrivateNetworks: Bool
    public var logLevel: XrayLogLevel

    public init(
        listenAddress: String = AppMetadata.proxyHost,
        port: Int = AppMetadata.proxyPort,
        udpEnabled: Bool = true,
        sniffingEnabled: Bool = true,
        bypassPrivateNetworks: Bool = true,
        logLevel: XrayLogLevel = .warning
    ) {
        self.listenAddress = listenAddress
        self.port = port
        self.udpEnabled = udpEnabled
        self.sniffingEnabled = sniffingEnabled
        self.bypassPrivateNetworks = bypassPrivateNetworks
        self.logLevel = logLevel
    }

    public static let `default` = Self()

    public func validated() throws -> LocalProxyConfiguration {
        var copy = self
        copy.listenAddress = copy.listenAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard Self.isLoopbackHost(copy.listenAddress) else {
            throw LocalProxyConfigurationError.invalidListenAddress
        }
        guard (1...65_535).contains(copy.port) else {
            throw LocalProxyConfigurationError.invalidPort
        }
        return copy
    }

    public var endpoint: ProxyEndpoint {
        ProxyEndpoint(host: listenAddress, port: port)
    }

    static func isLoopbackHost(_ value: String) -> Bool {
        let host = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host == "localhost" || host == "::1" { return true }

        var address = in_addr()
        let isIPv4 = host.withCString { inet_pton(AF_INET, $0, &address) == 1 }
        guard isIPv4 else { return false }
        return (UInt32(bigEndian: address.s_addr) >> 24) == 127
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
