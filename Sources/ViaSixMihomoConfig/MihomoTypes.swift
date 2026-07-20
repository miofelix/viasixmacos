import Foundation

public enum MihomoRoutingMode: String, Codable, CaseIterable, Sendable {
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
}

public enum MihomoLogLevel: String, Codable, CaseIterable, Sendable {
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
}

public enum MihomoProxyProtocol: String, Codable, CaseIterable, Sendable {
    case vless
    case vmess
    case trojan
    case shadowsocks = "ss"

    public var displayName: String {
        switch self {
        case .vless: "VLESS"
        case .vmess: "VMess"
        case .trojan: "Trojan"
        case .shadowsocks: "Shadowsocks"
        }
    }
}

public enum MihomoTransport: String, Codable, CaseIterable, Sendable {
    case websocket = "ws"
    case grpc
    case tcp
    case http
    case h2

    public var displayName: String {
        switch self {
        case .websocket: "WebSocket"
        case .grpc: "gRPC"
        case .tcp: "TCP"
        case .http: "HTTP"
        case .h2: "HTTP/2"
        }
    }
}

public enum MihomoTransportSecurity: String, Codable, CaseIterable, Sendable {
    case tls
    case reality
    case none

    public var displayName: String {
        switch self {
        case .tls: "TLS"
        case .reality: "REALITY"
        case .none: "无"
        }
    }
}

public enum MihomoTunStack: String, Codable, CaseIterable, Sendable {
    case mixed
    case system
    case gvisor

    public var displayName: String {
        switch self {
        case .mixed: "Mixed"
        case .system: "System"
        case .gvisor: "gVisor"
        }
    }
}

public struct MihomoTunConfiguration: Equatable, Sendable {
    public var stack: MihomoTunStack
    public var device: String?
    public var autoRoute: Bool
    public var strictRoute: Bool
    public var autoDetectInterface: Bool
    public var dnsHijack: [String]
    public var mtu: Int
    public var routeExcludeAddresses: [String]

    public init(
        stack: MihomoTunStack = .mixed,
        device: String? = nil,
        autoRoute: Bool = true,
        strictRoute: Bool = false,
        autoDetectInterface: Bool = true,
        dnsHijack: [String] = ["any:53", "tcp://any:53"],
        mtu: Int = 1_500,
        routeExcludeAddresses: [String] = []
    ) {
        self.stack = stack
        self.device = device
        self.autoRoute = autoRoute
        self.strictRoute = strictRoute
        self.autoDetectInterface = autoDetectInterface
        self.dnsHijack = dnsHijack
        self.mtu = mtu
        self.routeExcludeAddresses = routeExcludeAddresses
    }
}

public struct MihomoRuntimeOptions: Equatable, Sendable {
    public var listenAddress: String
    public var mixedPort: Int
    public var routingMode: MihomoRoutingMode
    public var logLevel: MihomoLogLevel
    public var ipv6Enabled: Bool
    public var udpEnabled: Bool
    public var sniffingEnabled: Bool
    public var bypassPrivateNetworks: Bool
    public var tun: MihomoTunConfiguration?

    public init(
        listenAddress: String = "127.0.0.1",
        mixedPort: Int = 7_897,
        routingMode: MihomoRoutingMode = .rule,
        logLevel: MihomoLogLevel = .warning,
        ipv6Enabled: Bool = true,
        udpEnabled: Bool = true,
        sniffingEnabled: Bool = true,
        bypassPrivateNetworks: Bool = true,
        tun: MihomoTunConfiguration? = nil
    ) {
        self.listenAddress = listenAddress
        self.mixedPort = mixedPort
        self.routingMode = routingMode
        self.logLevel = logLevel
        self.ipv6Enabled = ipv6Enabled
        self.udpEnabled = udpEnabled
        self.sniffingEnabled = sniffingEnabled
        self.bypassPrivateNetworks = bypassPrivateNetworks
        self.tun = tun
    }
}

public enum MihomoConfigurationError: LocalizedError, Equatable, Sendable {
    case invalidUTF8
    case invalidYAML(String)
    case topLevelMustBeMapping
    case nonStringMappingKey
    case unsupportedValue(String)
    case missingProxySource
    case missingInlineProxy
    case invalidProxy(String)
    case unsupportedProtocol(String)
    case invalidServerPort
    case missingCredential
    case missingServerName
    case missingRealityPublicKey
    case placeholderConfiguration
    case invalidListenAddress
    case invalidMixedPort
    case invalidTunMTU
    case legacyXrayConfiguration
    case configurationTooLarge(Int)
    case configurationTooDeep
    case configurationTooComplex
    case unsupportedProviderType(name: String, type: String)

    public var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            "Mihomo 配置必须使用 UTF-8 编码"
        case .invalidYAML(let detail):
            "Mihomo YAML 无法解析：\(detail)"
        case .topLevelMustBeMapping:
            "Mihomo 配置顶层必须是 YAML 映射"
        case .nonStringMappingKey:
            "Mihomo 配置只允许字符串键名"
        case .unsupportedValue(let description):
            "Mihomo 配置包含不支持的值：\(description)"
        case .missingProxySource:
            "配置至少需要 proxies 或 proxy-providers"
        case .missingInlineProxy:
            "配置没有可由 ViaSix 更新地址的内联代理节点"
        case .invalidProxy(let reason):
            "代理节点配置无效：\(reason)"
        case .unsupportedProtocol(let name):
            "可视化编辑器暂不支持 \(name) 协议，请使用高级 YAML 编辑器"
        case .invalidServerPort:
            "服务器端口必须在 1–65535 之间"
        case .missingCredential:
            "请输入服务器提供的 UUID 或密码"
        case .missingServerName:
            "TLS/REALITY 模式需要填写 Server Name"
        case .missingRealityPublicKey:
            "REALITY 模式需要填写公钥"
        case .placeholderConfiguration:
            "代理连接仍包含示例凭据，请先填写真实服务器配置"
        case .invalidListenAddress:
            "本地监听地址必须是回环地址"
        case .invalidMixedPort:
            "本地 mixed 端口必须在 1–65535 之间"
        case .invalidTunMTU:
            "TUN MTU 必须在 576–9000 之间"
        case .legacyXrayConfiguration:
            "检测到旧版 Xray JSON，需要先迁移为 Mihomo YAML"
        case .configurationTooLarge(let size):
            "Mihomo 配置过大：\(size) 字节"
        case .configurationTooDeep:
            "Mihomo 配置嵌套层级过深"
        case .configurationTooComplex:
            "Mihomo 配置包含过多节点"
        case .unsupportedProviderType(let name, let type):
            "Provider \(name) 使用了不安全或不支持的类型：\(type)"
        }
    }
}
