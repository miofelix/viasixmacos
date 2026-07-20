import Darwin
import Foundation

public enum ConfigTemplateError: LocalizedError, Equatable, Sendable {
    case invalidJSON
    case missingOutbounds
    case missingProxyOutbound
    case missingVnext
    case invalidLocalInbound
    case connectionNotConfigured

    public var errorDescription: String? {
        switch self {
        case .invalidJSON: "Xray 模板不是有效 JSON"
        case .missingOutbounds: "Xray 模板缺少 outbounds"
        case .missingProxyOutbound: "Xray 模板缺少 tag 为 proxy 的出站配置"
        case .missingVnext: "proxy 出站缺少可用的 settings.vnext 或 settings.servers"
        case .invalidLocalInbound:
            "Xray 模板必须仅监听本机回环地址，并包含端口有效的 mixed 入站"
        case .connectionNotConfigured: "代理连接尚未配置，请在“设置”中导入或编辑你自己的 Xray 模板"
        }
    }
}

public enum ConfigTemplate {
    public static let placeholderUserID = "00000000-0000-0000-0000-000000000000"
    public static let placeholderServerName = "example.com"

    public static func replacingAddress(in template: Data, with ip: String) throws -> Data {
        var config = try configurationObject(in: template)
        var outbounds = try outboundList(in: config)
        guard let proxyIndex = outbounds.firstIndex(where: { $0["tag"] as? String == "proxy" }) else {
            throw ConfigTemplateError.missingProxyOutbound
        }
        guard var settings = outbounds[proxyIndex]["settings"] as? [String: Any] else {
            throw ConfigTemplateError.missingVnext
        }
        let normalizedIP = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        if var vnext = settings["vnext"] as? [[String: Any]], !vnext.isEmpty {
            vnext[0]["address"] = normalizedIP
            settings["vnext"] = vnext
        } else if var servers = settings["servers"] as? [[String: Any]], !servers.isEmpty {
            servers[0]["address"] = normalizedIP
            settings["servers"] = servers
        } else {
            throw ConfigTemplateError.missingVnext
        }
        outbounds[proxyIndex]["settings"] = settings
        config["outbounds"] = outbounds

        guard JSONSerialization.isValidJSONObject(config) else {
            throw ConfigTemplateError.invalidJSON
        }
        return try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
    }

    @discardableResult
    public static func validateTemplate(_ template: Data) throws -> ProxyEndpoint {
        let object = try configurationObject(in: template)
        let endpoint = try validateLocalInbounds(in: object)
        if try isDirectConfiguration(object) {
            return endpoint
        }
        _ = try replacingAddress(in: template, with: "2001:db8::1")
        return endpoint
    }

    @discardableResult
    public static func validateForLaunch(_ config: Data) throws -> ProxyEndpoint {
        let object = try configurationObject(in: config)
        let endpoint = try validateLocalInbounds(in: object)
        let outbounds = try outboundList(in: object)
        if try isDirectConfiguration(object, outbounds: outbounds) {
            return endpoint
        }
        guard let proxy = outbounds.first(where: { $0["tag"] as? String == "proxy" }) else {
            throw ConfigTemplateError.missingProxyOutbound
        }
        guard let settings = proxy["settings"] as? [String: Any] else {
            throw ConfigTemplateError.missingVnext
        }
        let server: [String: Any]?
        if let vnext = settings["vnext"] as? [[String: Any]] {
            server = vnext.first
        } else if let servers = settings["servers"] as? [[String: Any]] {
            server = servers.first
        } else {
            server = nil
        }
        guard let server,
            let address = server["address"] as? String,
            !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw ConfigTemplateError.missingVnext
        }
        guard !containsPlaceholder(in: proxy) else {
            throw ConfigTemplateError.connectionNotConfigured
        }
        return endpoint
    }

    public static func write(
        ip: String,
        templateURL: URL,
        destinationURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let template = try Data(contentsOf: templateURL)
        let output = try replacingAddress(in: template, with: ip)
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try output.write(to: destinationURL, options: .atomic)
        try FilePermissions.restrictFile(destinationURL, using: fileManager)
    }

    public static func address(in config: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: config),
            let dictionary = object as? [String: Any]
        else { return nil }
        let proxy: [String: Any]?
        if let outbounds = dictionary["outbounds"] as? [[String: Any]] {
            proxy = outbounds.first(where: { $0["tag"] as? String == "proxy" })
        } else if dictionary["tag"] as? String == "proxy" {
            proxy = dictionary
        } else {
            proxy = nil
        }
        guard let settings = proxy?["settings"] as? [String: Any] else { return nil }
        if let vnext = settings["vnext"] as? [[String: Any]] {
            return vnext.first?["address"] as? String
        }
        if let servers = settings["servers"] as? [[String: Any]] {
            return servers.first?["address"] as? String
        }
        return nil
    }

    public static func proxyEndpoint(in config: Data) throws -> ProxyEndpoint {
        try validateLocalInbounds(in: configurationObject(in: config))
    }

    private static func configurationObject(in data: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data),
            let config = object as? [String: Any]
        else {
            throw ConfigTemplateError.invalidJSON
        }
        return config
    }

    private static func outboundList(in config: [String: Any]) throws -> [[String: Any]] {
        guard let outbounds = config["outbounds"] as? [[String: Any]], !outbounds.isEmpty else {
            throw ConfigTemplateError.missingOutbounds
        }
        return outbounds
    }

    /// Direct mode is valid without server credentials. It is recognized by
    /// either ViaSix's explicit direct catch-all route or by a direct-only
    /// outbound list, so generated configurations and concise advanced JSON
    /// documents share the same validation behavior.
    private static func isDirectConfiguration(
        _ config: [String: Any],
        outbounds suppliedOutbounds: [[String: Any]]? = nil
    ) throws -> Bool {
        let outbounds: [[String: Any]]
        if let suppliedOutbounds {
            outbounds = suppliedOutbounds
        } else {
            outbounds = try outboundList(in: config)
        }
        let hasDirect = outbounds.contains { outbound in
            outbound["tag"] as? String == "direct"
                && (outbound["protocol"] as? String)?.lowercased() == "freedom"
        }
        guard hasDirect else { return false }

        let hasProxy = outbounds.contains { $0["tag"] as? String == "proxy" }
        if !hasProxy { return true }

        let rules = (config["routing"] as? [String: Any])?["rules"] as? [[String: Any]] ?? []
        return rules.contains { rule in
            guard rule["type"] as? String == "field" else { return false }
            guard rule["outboundTag"] as? String == "direct" else { return false }
            guard let network = rule["network"] as? String else { return false }
            let networks = Set(
                network.split(separator: ",").map {
                    String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                })
            guard networks.contains("tcp") && networks.contains("udp") else { return false }
            return Set(rule.keys).subtracting(["type", "network", "outboundTag"]).isEmpty
        }
    }

    private static func validateLocalInbounds(in config: [String: Any]) throws -> ProxyEndpoint {
        guard let inbounds = config["inbounds"] as? [[String: Any]], !inbounds.isEmpty else {
            throw ConfigTemplateError.invalidLocalInbound
        }

        guard
            inbounds.allSatisfy({ inbound in
                guard let listen = inbound["listen"] as? String else { return false }
                return isLoopbackHost(listen)
            })
        else {
            throw ConfigTemplateError.invalidLocalInbound
        }

        guard
            let managedInbound = inbounds.first(where: { inbound in
                let listen = (inbound["listen"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                let protocolName = (inbound["protocol"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                let port = inbound["port"] as? Int
                return listen.map(isLoopbackHost) == true
                    && protocolName == "mixed"
                    && port.map({ (1...65_535).contains($0) }) == true
            }),
            let host = (managedInbound["listen"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
            let port = managedInbound["port"] as? Int
        else {
            throw ConfigTemplateError.invalidLocalInbound
        }
        return ProxyEndpoint(host: host, port: port)
    }

    private static func isLoopbackHost(_ value: String) -> Bool {
        let host = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host == "localhost" || host == "::1" { return true }

        var address = in_addr()
        let isIPv4 = host.withCString { inet_pton(AF_INET, $0, &address) == 1 }
        guard isIPv4 else { return false }
        return (UInt32(bigEndian: address.s_addr) >> 24) == 127
    }

    private static func containsPlaceholder(in value: Any) -> Bool {
        if let string = value as? String {
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized == placeholderUserID || normalized == placeholderServerName
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.values.contains(where: containsPlaceholder)
        }
        if let array = value as? [Any] {
            return array.contains(where: containsPlaceholder)
        }
        return false
    }
}
