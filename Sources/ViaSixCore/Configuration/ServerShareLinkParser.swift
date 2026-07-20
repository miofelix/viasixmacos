import Foundation

public enum ServerShareLinkError: LocalizedError, Equatable, Sendable {
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

public enum ServerShareLinkParser {
    public static func profile(from text: String) throws -> XrayServerProfile {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let scheme = value.split(separator: ":", maxSplits: 1).first.map(String.init)?.lowercased() else {
            throw ServerShareLinkError.unsupportedScheme
        }
        switch scheme {
        case "vless":
            return try parseVLESS(value)
        case "vmess":
            return try parseVMess(value)
        case "trojan":
            return try parseTrojan(value)
        case "ss":
            return try parseShadowsocks(value)
        default:
            throw ServerShareLinkError.unsupportedScheme
        }
    }

    public static func serverConfiguration(from text: String) throws -> Data {
        try ConfigTemplate.serverConfiguration(for: profile(from: text))
    }

    private static func parseVLESS(_ value: String) throws -> XrayServerProfile {
        guard let components = URLComponents(string: value),
            let host = components.host,
            let port = components.port,
            let user = components.user?.removingPercentEncoding,
            !user.isEmpty
        else { throw ServerShareLinkError.malformedLink }
        let query = queryValues(components)
        let transport = XrayTransport(rawValue: query["type"]?.lowercased() ?? "tcp") ?? .tcp
        let security = XrayTransportSecurity(rawValue: query["security"]?.lowercased() ?? "none") ?? .none
        return XrayServerProfile(
            protocolName: .vless,
            serverAddress: host,
            serverPort: port,
            userID: user,
            encryption: query["encryption"] ?? "none",
            flow: query["flow"] ?? "",
            transport: transport,
            security: security,
            serverName: query["sni"] ?? query["servername"] ?? "",
            host: query["host"] ?? "",
            path: query["path"].flatMap { $0.removingPercentEncoding } ?? "/",
            serviceName: query["serviceName"] ?? query["servicename"] ?? "",
            allowInsecure: queryFlag(query, keys: ["allowinsecure", "insecure"]),
            fingerprint: query["fp"] ?? "chrome",
            realityPublicKey: query["pbk"] ?? "",
            realityShortID: query["sid"] ?? "",
            realitySpiderX: query["spx"].flatMap { $0.removingPercentEncoding } ?? ""
        )
    }

    private static func parseTrojan(_ value: String) throws -> XrayServerProfile {
        guard let components = URLComponents(string: value),
            let host = components.host,
            let port = components.port,
            let password = components.user?.removingPercentEncoding,
            !password.isEmpty
        else { throw ServerShareLinkError.malformedLink }
        let query = queryValues(components)
        let transport = XrayTransport(rawValue: query["type"]?.lowercased() ?? "tcp") ?? .tcp
        let security = XrayTransportSecurity(rawValue: query["security"]?.lowercased() ?? "tls") ?? .tls
        return XrayServerProfile(
            protocolName: .trojan,
            serverAddress: host,
            serverPort: port,
            userID: password,
            transport: transport,
            security: security,
            serverName: query["sni"] ?? query["servername"] ?? host,
            host: query["host"] ?? "",
            path: query["path"].flatMap { $0.removingPercentEncoding } ?? "/",
            serviceName: query["serviceName"] ?? query["servicename"] ?? "",
            allowInsecure: queryFlag(query, keys: ["allowinsecure", "insecure"]),
            fingerprint: query["fp"] ?? "chrome"
        )
    }

    private static func parseVMess(_ value: String) throws -> XrayServerProfile {
        let payload = String(value.dropFirst("vmess://".count))
        guard let data = decodeBase64(payload),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ServerShareLinkError.invalidBase64 }
        let host = object["add"] as? String ?? object["address"] as? String ?? ""
        let port = intValue(object["port"]) ?? 443
        let userID = object["id"] as? String ?? ""
        guard !host.isEmpty, !userID.isEmpty else { throw ServerShareLinkError.invalidPayload }
        let network = (object["net"] as? String ?? "tcp").lowercased()
        let transport = XrayTransport(rawValue: network == "http" ? "tcp" : network) ?? .tcp
        let tls = (object["tls"] as? String ?? "").lowercased()
        let security: XrayTransportSecurity = tls.isEmpty || tls == "none" ? .none : .tls
        let wsPath = object["path"] as? String ?? "/"
        let hostHeader = object["host"] as? String ?? ""
        return XrayServerProfile(
            protocolName: .vmess,
            serverAddress: host,
            serverPort: port,
            userID: userID,
            alterID: intValue(object["aid"]) ?? 0,
            vmessSecurity: object["scy"] as? String ?? "auto",
            transport: transport,
            security: security,
            serverName: object["sni"] as? String ?? (hostHeader.isEmpty ? host : hostHeader),
            host: hostHeader,
            path: wsPath,
            allowInsecure: boolValue(object["allowInsecure"] ?? object["allowinsecure"]) ?? false
        )
    }

    private static func parseShadowsocks(_ value: String) throws -> XrayServerProfile {
        let payload = String(value.dropFirst("ss://".count))
        let withoutFragment = payload.split(separator: "#", maxSplits: 1).first.map(String.init) ?? payload
        let withoutQuery = withoutFragment.split(separator: "?", maxSplits: 1).first.map(String.init) ?? withoutFragment
        let decoded: String
        if withoutQuery.contains("@") {
            let plain = withoutQuery.removingPercentEncoding ?? withoutQuery
            if let at = plain.lastIndex(of: "@") {
                let credentials = String(plain[..<at])
                if credentials.contains(":") {
                    decoded = plain
                } else if let data = decodeBase64(credentials), let text = String(data: data, encoding: .utf8) {
                    decoded = text + String(plain[at...])
                } else {
                    throw ServerShareLinkError.invalidBase64
                }
            } else {
                throw ServerShareLinkError.invalidPayload
            }
        } else if let data = decodeBase64(withoutQuery), let text = String(data: data, encoding: .utf8) {
            decoded = text
        } else {
            throw ServerShareLinkError.invalidBase64
        }
        guard let at = decoded.lastIndex(of: "@") else { throw ServerShareLinkError.invalidPayload }
        let credentials = String(decoded[..<at])
        var endpoint = String(decoded[decoded.index(after: at)...])
        if endpoint.hasSuffix("/") { endpoint.removeLast() }
        guard let credentialsColon = credentials.firstIndex(of: ":"),
            let endpointColon = endpoint.lastIndex(of: ":")
        else { throw ServerShareLinkError.invalidPayload }
        let method = String(credentials[..<credentialsColon])
        let password = String(credentials[credentials.index(after: credentialsColon)...])
        let host = String(endpoint[..<endpointColon]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard let port = Int(endpoint[endpoint.index(after: endpointColon)...]),
            !method.isEmpty, !password.isEmpty, !host.isEmpty
        else { throw ServerShareLinkError.malformedLink }
        return XrayServerProfile(
            protocolName: .shadowsocks,
            serverAddress: host,
            serverPort: port,
            userID: password,
            encryption: method,
            transport: .tcp,
            security: .none
        )
    }

    private static func queryValues(_ components: URLComponents) -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
                guard let value = item.value else { return nil }
                return (item.name.lowercased(), value)
            })
    }

    private static func queryFlag(_ query: [String: String], keys: [String]) -> Bool {
        keys.contains { key in
            guard let value = query[key]?.lowercased() else { return false }
            return value == "1" || value == "true" || value == "yes"
        }
    }

    private static func decodeBase64(_ value: String) -> Data? {
        var normalized = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        normalized += String(repeating: "=", count: (4 - normalized.count % 4) % 4)
        return Data(base64Encoded: normalized)
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? Int { return value != 0 }
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
