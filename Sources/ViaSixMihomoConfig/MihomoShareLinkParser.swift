import Foundation

public enum MihomoShareLinkError: LocalizedError, Equatable, Sendable {
    case unsupportedScheme
    case malformedLink
    case invalidBase64
    case invalidPayload

    public var errorDescription: String? {
        switch self {
        case .unsupportedScheme:
            "支持 vless://、vmess://、trojan:// 和 ss:// 分享链接"
        case .malformedLink:
            "分享链接缺少服务器地址、端口或认证信息"
        case .invalidBase64:
            "分享链接的 Base64 内容无效"
        case .invalidPayload:
            "分享链接内容无法识别"
        }
    }
}

public enum MihomoShareLinkParser {
    public static func profile(from text: String) throws -> MihomoProxyProfile {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let scheme = value.split(separator: ":", maxSplits: 1).first
                .map(String.init)?.lowercased()
        else {
            throw MihomoShareLinkError.unsupportedScheme
        }
        switch scheme {
        case "vless": return try parseVLESS(value)
        case "vmess": return try parseVMess(value)
        case "trojan": return try parseTrojan(value)
        case "ss": return try parseShadowsocks(value)
        default: throw MihomoShareLinkError.unsupportedScheme
        }
    }

    public static func serverConfiguration(from text: String) throws -> MihomoServerConfiguration {
        try MihomoServerConfiguration(profile: profile(from: text))
    }

    private static func parseVLESS(_ value: String) throws -> MihomoProxyProfile {
        guard let components = URLComponents(string: value),
            let rawHost = components.host,
            let port = components.port,
            let user = components.user?.removingPercentEncoding,
            !user.isEmpty
        else { throw MihomoShareLinkError.malformedLink }
        let host = normalizedHost(rawHost)
        let query = queryValues(components)
        let transport = try transport(query["type"] ?? "tcp")
        let security = try security(query["security"] ?? "none")
        let serverName = query["sni"] ?? query["servername"] ?? query["host"] ?? host
        return try MihomoProxyProfile(
            name: displayName(components, fallback: "VLESS"),
            protocolName: .vless,
            serverAddress: host,
            serverPort: port,
            credential: user,
            encryption: query["encryption"] ?? "none",
            flow: query["flow"] ?? "",
            transport: transport,
            security: security,
            serverName: serverName,
            host: query["host"] ?? "",
            path: query["path"] ?? "/",
            serviceName: query["servicename"] ?? "",
            allowInsecure: queryFlag(query, keys: ["allowinsecure", "insecure"]),
            fingerprint: query["fp"] ?? "chrome",
            realityPublicKey: query["pbk"] ?? "",
            realityShortID: query["sid"] ?? ""
        ).validated()
    }

    private static func parseTrojan(_ value: String) throws -> MihomoProxyProfile {
        guard let components = URLComponents(string: value),
            let rawHost = components.host,
            let port = components.port,
            let password = components.user?.removingPercentEncoding,
            !password.isEmpty
        else { throw MihomoShareLinkError.malformedLink }
        let host = normalizedHost(rawHost)
        let query = queryValues(components)
        let transport = try transport(query["type"] ?? "tcp")
        let security = try security(query["security"] ?? "tls")
        return try MihomoProxyProfile(
            name: displayName(components, fallback: "Trojan"),
            protocolName: .trojan,
            serverAddress: host,
            serverPort: port,
            credential: password,
            transport: transport,
            security: security,
            serverName: query["sni"] ?? query["servername"] ?? host,
            host: query["host"] ?? "",
            path: query["path"] ?? "/",
            serviceName: query["servicename"] ?? "",
            allowInsecure: queryFlag(query, keys: ["allowinsecure", "insecure"]),
            fingerprint: query["fp"] ?? "chrome"
        ).validated()
    }

    private static func parseVMess(_ value: String) throws -> MihomoProxyProfile {
        let payload = String(value.dropFirst("vmess://".count))
        guard let data = decodeBase64(payload),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw MihomoShareLinkError.invalidBase64 }
        let rawHost = object["add"] as? String ?? object["address"] as? String ?? ""
        let host = normalizedHost(rawHost)
        let port = intValue(object["port"]) ?? 443
        let credential = object["id"] as? String ?? ""
        guard !host.isEmpty, !credential.isEmpty else {
            throw MihomoShareLinkError.invalidPayload
        }
        let transport = try transport(object["net"] as? String ?? "tcp")
        let tls = (object["tls"] as? String ?? "").lowercased()
        let security: MihomoTransportSecurity = tls.isEmpty || tls == "none" ? .none : .tls
        let hostHeader = object["host"] as? String ?? ""
        let path = object["path"] as? String ?? "/"
        let serviceName =
            object["serviceName"] as? String
            ?? object["servicename"] as? String
            ?? (transport == .grpc ? path : "")
        return try MihomoProxyProfile(
            name: (object["ps"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty ?? "VMess",
            protocolName: .vmess,
            serverAddress: host,
            serverPort: port,
            credential: credential,
            alterID: intValue(object["aid"]) ?? 0,
            vmessCipher: object["scy"] as? String ?? "auto",
            transport: transport,
            security: security,
            serverName: object["sni"] as? String ?? (hostHeader.isEmpty ? host : hostHeader),
            host: hostHeader,
            path: path,
            serviceName: serviceName,
            allowInsecure: boolValue(object["allowInsecure"] ?? object["allowinsecure"])
                ?? false
        ).validated()
    }

    private static func parseShadowsocks(_ value: String) throws -> MihomoProxyProfile {
        guard let components = URLComponents(string: value) else {
            throw MihomoShareLinkError.malformedLink
        }
        let payload = String(value.dropFirst("ss://".count))
        let withoutFragment = payload.split(separator: "#", maxSplits: 1).first.map(String.init) ?? payload
        let withoutQuery = withoutFragment.split(separator: "?", maxSplits: 1).first.map(String.init) ?? withoutFragment
        let decoded: String
        if withoutQuery.contains("@") {
            let plain = withoutQuery.removingPercentEncoding ?? withoutQuery
            guard let at = plain.lastIndex(of: "@") else {
                throw MihomoShareLinkError.invalidPayload
            }
            let credentials = String(plain[..<at])
            if credentials.contains(":") {
                decoded = plain
            } else if let data = decodeBase64(credentials),
                let text = String(data: data, encoding: .utf8)
            {
                decoded = text + String(plain[at...])
            } else {
                throw MihomoShareLinkError.invalidBase64
            }
        } else if let data = decodeBase64(withoutQuery),
            let text = String(data: data, encoding: .utf8)
        {
            decoded = text
        } else {
            throw MihomoShareLinkError.invalidBase64
        }

        guard let at = decoded.lastIndex(of: "@") else {
            throw MihomoShareLinkError.invalidPayload
        }
        let credentials = String(decoded[..<at])
        var endpoint = String(decoded[decoded.index(after: at)...])
        if endpoint.hasSuffix("/") { endpoint.removeLast() }
        guard let credentialsColon = credentials.firstIndex(of: ":"),
            let endpointColon = endpoint.lastIndex(of: ":")
        else { throw MihomoShareLinkError.invalidPayload }
        let method = String(credentials[..<credentialsColon])
        let password = String(credentials[credentials.index(after: credentialsColon)...])
        let host = String(endpoint[..<endpointColon])
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard let port = Int(endpoint[endpoint.index(after: endpointColon)...]),
            !method.isEmpty, !password.isEmpty, !host.isEmpty
        else { throw MihomoShareLinkError.malformedLink }
        return try MihomoProxyProfile(
            name: displayName(components, fallback: "Shadowsocks"),
            protocolName: .shadowsocks,
            serverAddress: host,
            serverPort: port,
            credential: password,
            encryption: method,
            transport: .tcp,
            security: .none
        ).validated()
    }

    private static func queryValues(_ components: URLComponents) -> [String: String] {
        var values: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard let value = item.value else { continue }
            values[item.name.lowercased()] = value
        }
        return values
    }

    private static func queryFlag(_ query: [String: String], keys: [String]) -> Bool {
        keys.contains { key in
            guard let value = query[key]?.lowercased() else { return false }
            return value == "1" || value == "true" || value == "yes"
        }
    }

    private static func displayName(_ components: URLComponents, fallback: String) -> String {
        let decoded = components.fragment?.removingPercentEncoding ?? components.fragment
        return decoded?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? fallback
    }

    private static func normalizedHost(_ value: String) -> String {
        guard value.hasPrefix("["), value.hasSuffix("]") else { return value }
        let inner = String(value.dropFirst().dropLast())
        return inner.contains(":") ? inner : value
    }

    private static func transport(_ value: String) throws -> MihomoTransport {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let transport = MihomoTransport(rawValue: normalized) else {
            throw MihomoConfigurationError.invalidProxy("不支持的传输方式：\(value)")
        }
        return transport
    }

    private static func security(_ value: String) throws -> MihomoTransportSecurity {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let security = MihomoTransportSecurity(rawValue: normalized) else {
            throw MihomoConfigurationError.invalidProxy("不支持的安全方式：\(value)")
        }
        return security
    }

    private static func decodeBase64(_ value: String) -> Data? {
        var normalized = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        normalized += String(repeating: "=", count: (4 - normalized.count % 4) % 4)
        return Data(base64Encoded: normalized)
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            switch value.lowercased() {
            case "1", "true", "yes": return true
            case "0", "false", "no": return false
            default: return nil
            }
        }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
