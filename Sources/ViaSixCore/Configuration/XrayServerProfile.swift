import Foundation

public enum XrayTransport: String, CaseIterable, Sendable {
    case websocket = "ws"
    case grpc
    case tcp

    public var displayName: String {
        switch self {
        case .websocket: "WebSocket"
        case .grpc: "gRPC"
        case .tcp: "TCP"
        }
    }
}

public enum XrayTransportSecurity: String, CaseIterable, Sendable {
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

public enum XrayServerProtocol: String, CaseIterable, Sendable {
    case vless
    case vmess
    case trojan
    case shadowsocks

    public var displayName: String {
        switch self {
        case .vless: "VLESS"
        case .vmess: "VMess"
        case .trojan: "Trojan"
        case .shadowsocks: "Shadowsocks"
        }
    }
}

public enum XrayServerProfileError: LocalizedError, Equatable, Sendable {
    case unsupportedProtocol(String)
    case unsupportedStructure
    case invalidServerPort
    case missingUserID
    case missingServerName
    case missingRealityPublicKey

    public var errorDescription: String? {
        switch self {
        case .unsupportedProtocol(let name):
            "可视化编辑器暂不支持 \(name) 协议，请使用高级 JSON 编辑器"
        case .unsupportedStructure:
            "服务器出站结构无法由可视化编辑器识别，请使用高级 JSON 编辑器"
        case .invalidServerPort:
            "服务器端口必须在 1–65535 之间"
        case .missingUserID:
            "请输入服务器提供的 UUID 或密码"
        case .missingServerName:
            "TLS/REALITY 模式需要填写 Server Name"
        case .missingRealityPublicKey:
            "REALITY 模式需要填写公钥"
        }
    }
}

/// Common server fields used by ViaSix's guided editor. The raw Xray
/// outbound remains the source of truth, so unsupported/extra fields can still
/// be managed through the advanced JSON editor without narrowing compatibility.
public struct XrayServerProfile: Equatable, Sendable {
    public var protocolName: XrayServerProtocol
    public var serverAddress: String
    public var serverPort: Int
    public var userID: String
    public var encryption: String
    public var flow: String
    public var alterID: Int
    public var vmessSecurity: String
    public var transport: XrayTransport
    public var security: XrayTransportSecurity
    public var serverName: String
    public var host: String
    public var path: String
    public var serviceName: String
    public var allowInsecure: Bool
    public var fingerprint: String
    public var realityPublicKey: String
    public var realityShortID: String
    public var realitySpiderX: String

    public init(
        protocolName: XrayServerProtocol = .vless,
        serverAddress: String = "2001:db8::1",
        serverPort: Int = 443,
        userID: String = "",
        encryption: String = "none",
        flow: String = "",
        alterID: Int = 0,
        vmessSecurity: String = "auto",
        transport: XrayTransport = .websocket,
        security: XrayTransportSecurity = .tls,
        serverName: String = "",
        host: String = "",
        path: String = "/",
        serviceName: String = "",
        allowInsecure: Bool = false,
        fingerprint: String = "chrome",
        realityPublicKey: String = "",
        realityShortID: String = "",
        realitySpiderX: String = ""
    ) {
        self.protocolName = protocolName
        self.serverAddress = serverAddress
        self.serverPort = serverPort
        self.userID = userID
        self.encryption = encryption
        self.flow = flow
        self.alterID = alterID
        self.vmessSecurity = vmessSecurity
        self.transport = transport
        self.security = security
        self.serverName = serverName
        self.host = host
        self.path = path
        self.serviceName = serviceName
        self.allowInsecure = allowInsecure
        self.fingerprint = fingerprint
        self.realityPublicKey = realityPublicKey
        self.realityShortID = realityShortID
        self.realitySpiderX = realitySpiderX
    }

    public func validated() throws -> XrayServerProfile {
        var copy = self
        copy.userID = copy.userID.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.serverAddress = copy.serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.serverName = copy.serverName.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.host = copy.host.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.path = copy.path.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.serviceName = copy.serviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.flow = copy.flow.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.fingerprint = copy.fingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.realityPublicKey = copy.realityPublicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.realityShortID = copy.realityShortID.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.realitySpiderX = copy.realitySpiderX.trimmingCharacters(in: .whitespacesAndNewlines)

        if copy.protocolName == .shadowsocks {
            copy.transport = .tcp
            copy.security = .none
        }

        guard (1...65_535).contains(copy.serverPort) else {
            throw XrayServerProfileError.invalidServerPort
        }
        guard !copy.serverAddress.isEmpty else {
            throw XrayServerProfileError.unsupportedStructure
        }
        guard !copy.userID.isEmpty, copy.userID != ConfigTemplate.placeholderUserID else {
            throw XrayServerProfileError.missingUserID
        }
        if copy.security != .none,
            copy.serverName.isEmpty
                || copy.serverName == ConfigTemplate.placeholderServerName
        {
            throw XrayServerProfileError.missingServerName
        }
        if copy.security == .reality, copy.realityPublicKey.isEmpty {
            throw XrayServerProfileError.missingRealityPublicKey
        }
        if copy.transport == .websocket {
            if copy.path.isEmpty { copy.path = "/" }
            if copy.host.isEmpty { copy.host = copy.serverName }
        }
        return copy
    }
}
