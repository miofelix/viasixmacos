import Darwin
import Foundation

/// Log verbosity shared by the application's proxy-core integrations.
///
/// Older releases persisted Xray's `none` spelling. Mihomo calls the same
/// level `silent`, so decoding accepts the old value while encoding always
/// writes the neutral, current spelling.
public enum ProxyLogLevel: String, Codable, CaseIterable, Sendable {
    case silent
    case error
    case warning
    case info
    case debug

    public var displayName: String {
        switch self {
        case .silent: "关闭"
        case .error: "仅错误"
        case .warning: "警告"
        case .info: "信息"
        case .debug: "调试"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch value {
        case "none", "off", "silent": self = .silent
        case "error": self = .error
        case "warning", "warn": self = .warning
        case "info": self = .info
        case "debug": self = .debug
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported proxy log level: \(value)"
            )
        }
    }
}

/// Determines how traffic entering the local mixed proxy is routed.
public enum ProxyRoutingMode: String, Codable, CaseIterable, Sendable {
    case rule
    case global
    case direct

    public var displayName: String {
        switch self {
        case .rule: "规则"
        case .global: "全局"
        case .direct: "直连"
        }
    }

    /// Accept common human-authored aliases while keeping the persisted value
    /// canonical (`rule`, `global`, or `direct`).
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch value {
        case "rule", "rules", "rule-based", "规则":
            self = .rule
        case "global", "全局":
            self = .global
        case "direct", "直连":
            self = .direct
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported proxy routing mode: \(value)"
            )
        }
    }
}

public enum LocalProxyConfigurationError: LocalizedError, Equatable, Sendable {
    case invalidListenAddress
    case invalidPort
    case invalidControllerPort
    case conflictingControllerPort

    public var errorDescription: String? {
        switch self {
        case .invalidListenAddress:
            "本地监听地址必须是 127.0.0.0/8、::1 或 localhost"
        case .invalidPort:
            "本地监听端口必须在 1–65535 之间"
        case .invalidControllerPort:
            "内核控制端口必须在 1–65535 之间"
        case .conflictingControllerPort:
            "内核控制端口不能与本地代理端口相同"
        }
    }
}

public struct LocalProxyConfiguration: Codable, Equatable, Sendable {
    public var listenAddress: String
    public var port: Int
    public var controllerPort: Int
    public var udpEnabled: Bool
    public var sniffingEnabled: Bool
    public var bypassPrivateNetworks: Bool
    public var logLevel: ProxyLogLevel
    public var routingMode: ProxyRoutingMode
    public var networkAccessMode: NetworkAccessMode

    public init(
        listenAddress: String = AppMetadata.proxyHost,
        port: Int = AppMetadata.proxyPort,
        controllerPort: Int = AppMetadata.controllerPort,
        udpEnabled: Bool = true,
        sniffingEnabled: Bool = true,
        bypassPrivateNetworks: Bool = true,
        logLevel: ProxyLogLevel = .warning,
        routingMode: ProxyRoutingMode = .rule,
        networkAccessMode: NetworkAccessMode = .localProxy
    ) {
        self.listenAddress = listenAddress
        self.port = port
        self.controllerPort = controllerPort
        self.udpEnabled = udpEnabled
        self.sniffingEnabled = sniffingEnabled
        self.bypassPrivateNetworks = bypassPrivateNetworks
        self.logLevel = logLevel
        self.routingMode = routingMode
        self.networkAccessMode = networkAccessMode
    }

    /// Source-compatible initializer for callers that have not yet adopted
    /// the mutually-exclusive network access mode.
    public init(
        listenAddress: String = AppMetadata.proxyHost,
        port: Int = AppMetadata.proxyPort,
        controllerPort: Int = AppMetadata.controllerPort,
        udpEnabled: Bool = true,
        sniffingEnabled: Bool = true,
        bypassPrivateNetworks: Bool = true,
        logLevel: ProxyLogLevel = .warning,
        routingMode: ProxyRoutingMode = .rule,
        systemProxyEnabled: Bool
    ) {
        self.init(
            listenAddress: listenAddress,
            port: port,
            controllerPort: controllerPort,
            udpEnabled: udpEnabled,
            sniffingEnabled: sniffingEnabled,
            bypassPrivateNetworks: bypassPrivateNetworks,
            logLevel: logLevel,
            routingMode: routingMode,
            networkAccessMode: systemProxyEnabled ? .systemProxy : .localProxy
        )
    }

    public static let `default` = Self()

    private enum CodingKeys: String, CodingKey {
        case listenAddress
        case port
        case controllerPort
        case udpEnabled
        case sniffingEnabled
        case bypassPrivateNetworks
        case logLevel
        case routingMode
        case networkAccessMode
        case systemProxyEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        listenAddress =
            try container.decodeIfPresent(String.self, forKey: .listenAddress)
            ?? AppMetadata.proxyHost
        port =
            try container.decodeIfPresent(Int.self, forKey: .port)
            ?? AppMetadata.proxyPort
        controllerPort =
            try container.decodeIfPresent(Int.self, forKey: .controllerPort)
            ?? AppMetadata.controllerPort
        udpEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .udpEnabled)
            ?? true
        sniffingEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .sniffingEnabled)
            ?? true
        bypassPrivateNetworks =
            try container.decodeIfPresent(Bool.self, forKey: .bypassPrivateNetworks)
            ?? true
        logLevel =
            try container.decodeIfPresent(ProxyLogLevel.self, forKey: .logLevel)
            ?? .warning
        routingMode =
            try container.decodeIfPresent(ProxyRoutingMode.self, forKey: .routingMode)
            ?? .rule
        if let mode = try container.decodeIfPresent(
            NetworkAccessMode.self,
            forKey: .networkAccessMode
        ) {
            networkAccessMode = mode
        } else {
            networkAccessMode =
                try container.decodeIfPresent(Bool.self, forKey: .systemProxyEnabled) == true
                ? .systemProxy : .localProxy
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(listenAddress, forKey: .listenAddress)
        try container.encode(port, forKey: .port)
        try container.encode(controllerPort, forKey: .controllerPort)
        try container.encode(udpEnabled, forKey: .udpEnabled)
        try container.encode(sniffingEnabled, forKey: .sniffingEnabled)
        try container.encode(bypassPrivateNetworks, forKey: .bypassPrivateNetworks)
        try container.encode(logLevel, forKey: .logLevel)
        try container.encode(routingMode, forKey: .routingMode)
        try container.encode(networkAccessMode, forKey: .networkAccessMode)
    }

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
        guard (1...65_535).contains(copy.controllerPort) else {
            throw LocalProxyConfigurationError.invalidControllerPort
        }
        guard copy.controllerPort != copy.port else {
            throw LocalProxyConfigurationError.conflictingControllerPort
        }
        return copy
    }

    public var endpoint: ProxyEndpoint {
        ProxyEndpoint(host: listenAddress, port: port)
    }

    /// Compatibility for code compiled against the old independent toggle.
    /// New persistence writes only `networkAccessMode`, preventing system proxy
    /// and virtual-interface mode from being requested simultaneously.
    public var systemProxyEnabled: Bool {
        get { networkAccessMode.usesSystemProxy }
        set {
            if newValue {
                networkAccessMode = .systemProxy
            } else if networkAccessMode == .systemProxy {
                networkAccessMode = .localProxy
            }
        }
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
