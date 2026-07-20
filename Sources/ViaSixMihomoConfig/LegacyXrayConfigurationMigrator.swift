import Foundation

public enum LegacyXrayMigrationError: LocalizedError, Equatable, Sendable {
    case invalidJSON
    case missingProxyOutbound
    case multipleProxyOutbounds
    case unsupportedProtocol(String)
    case unsupportedStructure(String)
    case unsupportedTransport(String)
    case unsupportedSecurity(String)
    case unsupportedRealitySpiderX

    public var errorDescription: String? {
        switch self {
        case .invalidJSON:
            "旧版 Xray 配置不是有效 JSON"
        case .missingProxyOutbound:
            "旧版 Xray 配置缺少 tag 为 proxy 的出站"
        case .multipleProxyOutbounds:
            "旧版 Xray 配置包含多个 proxy 出站，无法确定应迁移哪一个"
        case .unsupportedProtocol(let name):
            "旧版 Xray 协议 \(name) 不支持自动迁移"
        case .unsupportedStructure(let reason):
            "旧版 Xray 配置无法安全自动迁移：\(reason)"
        case .unsupportedTransport(let name):
            "旧版 Xray 传输方式 \(name) 不支持自动迁移"
        case .unsupportedSecurity(let name):
            "旧版 Xray 安全方式 \(name) 不支持自动迁移"
        case .unsupportedRealitySpiderX:
            "旧版 REALITY spiderX 无法无损映射到当前 Mihomo 配置"
        }
    }
}

public enum LegacyXrayConfigurationMigrator {
    private static let maximumBytes = 8 * 1_024 * 1_024

    public static func serverConfiguration(from data: Data) throws -> MihomoServerConfiguration {
        try MihomoServerConfiguration(profile: profile(from: data))
    }

    public static func profile(from data: Data) throws -> MihomoProxyProfile {
        guard data.count <= maximumBytes,
            let object = try? JSONSerialization.jsonObject(with: data),
            let root = object as? [String: Any]
        else {
            throw LegacyXrayMigrationError.invalidJSON
        }

        let outbound: [String: Any]
        if root["protocol"] != nil, root["settings"] != nil {
            outbound = root
        } else {
            guard let outbounds = root["outbounds"] as? [[String: Any]] else {
                throw LegacyXrayMigrationError.missingProxyOutbound
            }
            let proxies = outbounds.filter { ($0["tag"] as? String) == "proxy" }
            guard !proxies.isEmpty else {
                throw LegacyXrayMigrationError.missingProxyOutbound
            }
            guard proxies.count == 1 else {
                throw LegacyXrayMigrationError.multipleProxyOutbounds
            }
            outbound = proxies[0]
        }
        return try profile(fromOutbound: outbound).validated()
    }

    private static func profile(fromOutbound outbound: [String: Any]) throws -> MihomoProxyProfile {
        let rawProtocol = (outbound["protocol"] as? String)?.lowercased() ?? ""
        let protocolName: MihomoProxyProtocol
        switch rawProtocol {
        case "vless": protocolName = .vless
        case "vmess": protocolName = .vmess
        case "trojan": protocolName = .trojan
        case "shadowsocks": protocolName = .shadowsocks
        default: throw LegacyXrayMigrationError.unsupportedProtocol(rawProtocol)
        }

        guard let settings = outbound["settings"] as? [String: Any] else {
            throw LegacyXrayMigrationError.unsupportedStructure("proxy 缺少 settings")
        }
        let endpoint = try endpointAndCredential(protocolName, settings: settings)

        let stream = outbound["streamSettings"] as? [String: Any] ?? [:]
        if let mux = outbound["mux"] as? [String: Any], !mux.isEmpty {
            throw LegacyXrayMigrationError.unsupportedStructure("mux 需要手动迁移")
        }
        if let socket = stream["sockopt"] as? [String: Any], !socket.isEmpty {
            throw LegacyXrayMigrationError.unsupportedStructure("sockopt 属于本机网络设置")
        }

        let transportName = stream["network"] as? String ?? "tcp"
        let transport = try transport(transportName)
        guard transport != .http, transport != .h2 else {
            // Xray's legacy HTTP transports use transport-specific fields
            // whose semantics do not map one-to-one to Mihomo's http-opts and
            // h2-opts. Refuse automatic migration instead of discarding them.
            throw LegacyXrayMigrationError.unsupportedTransport(transportName)
        }
        let security = try security(stream["security"] as? String ?? "none")
        let tls = stream["tlsSettings"] as? [String: Any] ?? [:]
        let reality = stream["realitySettings"] as? [String: Any] ?? [:]
        if let spiderX = reality["spiderX"] as? String,
            !spiderX.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            throw LegacyXrayMigrationError.unsupportedRealitySpiderX
        }

        let webSocket = stream["wsSettings"] as? [String: Any] ?? [:]
        let headers = webSocket["headers"] as? [String: Any] ?? [:]
        let unsupportedHeaders = Set(headers.keys).subtracting(["Host", "host"])
        guard unsupportedHeaders.isEmpty else {
            throw LegacyXrayMigrationError.unsupportedStructure(
                "WebSocket 包含无法无损迁移的 headers：\(unsupportedHeaders.sorted().joined(separator: ", "))"
            )
        }
        if webSocket["maxEarlyData"] != nil || webSocket["earlyDataHeaderName"] != nil {
            throw LegacyXrayMigrationError.unsupportedStructure("WebSocket Early Data 需要手动迁移")
        }

        let grpc = stream["grpcSettings"] as? [String: Any] ?? [:]
        let serverName =
            (security == .reality ? reality["serverName"] : tls["serverName"])
            as? String ?? ""
        let host =
            headers["Host"] as? String
            ?? headers["host"] as? String
            ?? webSocket["host"] as? String
            ?? ""
        let name = (outbound["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let profileName = name?.isEmpty == false ? name! : "ViaSix Proxy"

        return MihomoProxyProfile(
            name: profileName,
            protocolName: protocolName,
            serverAddress: endpoint.address,
            serverPort: endpoint.port,
            credential: endpoint.credential,
            encryption: endpoint.encryption,
            flow: endpoint.flow,
            alterID: endpoint.alterID,
            vmessCipher: endpoint.vmessCipher,
            transport: transport,
            security: security,
            serverName: serverName,
            host: host,
            path: webSocket["path"] as? String ?? "/",
            serviceName: grpc["serviceName"] as? String ?? "",
            allowInsecure: tls["allowInsecure"] as? Bool ?? false,
            fingerprint: (security == .reality ? reality["fingerprint"] : tls["fingerprint"])
                as? String ?? "chrome",
            realityPublicKey: reality["publicKey"] as? String ?? "",
            realityShortID: reality["shortId"] as? String ?? "",
            udpEnabled: true
        )
    }

    private static func endpointAndCredential(
        _ protocolName: MihomoProxyProtocol,
        settings: [String: Any]
    ) throws -> (
        address: String,
        port: Int,
        credential: String,
        encryption: String,
        flow: String,
        alterID: Int,
        vmessCipher: String
    ) {
        switch protocolName {
        case .vless, .vmess:
            guard let vnext = settings["vnext"] as? [[String: Any]],
                vnext.count == 1,
                let users = vnext[0]["users"] as? [[String: Any]],
                users.count == 1,
                let address = vnext[0]["address"] as? String,
                let port = int(vnext[0]["port"]),
                let credential = users[0]["id"] as? String
            else {
                throw LegacyXrayMigrationError.unsupportedStructure(
                    "VLESS/VMess 必须只有一个 vnext 和一个用户"
                )
            }
            return (
                address,
                port,
                credential,
                users[0]["encryption"] as? String ?? "none",
                users[0]["flow"] as? String ?? "",
                int(users[0]["alterId"]) ?? 0,
                users[0]["security"] as? String ?? "auto"
            )
        case .trojan:
            guard let servers = settings["servers"] as? [[String: Any]],
                servers.count == 1,
                let address = servers[0]["address"] as? String,
                let port = int(servers[0]["port"]),
                let credential = servers[0]["password"] as? String
            else {
                throw LegacyXrayMigrationError.unsupportedStructure(
                    "Trojan 必须只有一个服务器"
                )
            }
            return (
                address,
                port,
                credential,
                "none",
                servers[0]["flow"] as? String ?? "",
                0,
                "auto"
            )
        case .shadowsocks:
            guard let servers = settings["servers"] as? [[String: Any]],
                servers.count == 1,
                let address = servers[0]["address"] as? String,
                let port = int(servers[0]["port"]),
                let credential = servers[0]["password"] as? String,
                let method = servers[0]["method"] as? String
            else {
                throw LegacyXrayMigrationError.unsupportedStructure(
                    "Shadowsocks 必须只有一个服务器并包含 method"
                )
            }
            return (address, port, credential, method, "", 0, "auto")
        }
    }

    private static func transport(_ value: String) throws -> MihomoTransport {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let transport = MihomoTransport(rawValue: normalized) else {
            throw LegacyXrayMigrationError.unsupportedTransport(value)
        }
        return transport
    }

    private static func security(_ value: String) throws -> MihomoTransportSecurity {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let security = MihomoTransportSecurity(rawValue: normalized) else {
            throw LegacyXrayMigrationError.unsupportedSecurity(value)
        }
        return security
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }
}
