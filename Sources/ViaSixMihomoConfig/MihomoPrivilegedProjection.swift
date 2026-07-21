import Darwin
import Foundation

extension MihomoServerConfiguration {
    /// Rebuilds the profile subset accepted by a root-owned Mihomo process.
    /// This intentionally supports only the four protocols and fields emitted
    /// by ViaSix's editor/share-link parser; everything else fails closed.
    static func privilegedServerMapping(from root: [String: Any]) throws -> [String: Any] {
        guard !root.isEmpty else { return [:] }
        var result: [String: Any] = [:]

        if let raw = root["proxies"] {
            guard let proxies = raw as? [[String: Any]] else {
                throw MihomoConfigurationError.invalidProxy("proxies 必须是映射列表")
            }
            result["proxies"] = try privilegedProxies(proxies, context: "proxies")
        }
        if let raw = root["proxy-providers"] {
            guard let providers = raw as? [String: Any] else {
                throw MihomoConfigurationError.invalidProxy("proxy-providers 必须是映射")
            }
            result["proxy-providers"] = try privilegedProxyProviders(providers)
        }
        if let raw = root["proxy-groups"] {
            guard let groups = raw as? [[String: Any]] else {
                throw MihomoConfigurationError.invalidProxy("proxy-groups 必须是映射列表")
            }
            guard groups.count <= PrivilegedProjectionLimit.groups else {
                throw MihomoConfigurationError.configurationTooComplex
            }
            result["proxy-groups"] = try privilegedProxyGroups(groups)
        }
        if let raw = root["rule-providers"] {
            guard let providers = raw as? [String: Any] else {
                throw MihomoConfigurationError.invalidProxy("rule-providers 必须是映射")
            }
            result["rule-providers"] = try privilegedRuleProviders(providers)
        }
        if let raw = root["rules"] {
            result["rules"] = try privilegedRules(raw, context: "rules")
        }
        if let raw = root["sub-rules"] {
            guard let subRules = raw as? [String: Any],
                subRules.count <= PrivilegedProjectionLimit.providers
            else {
                throw MihomoConfigurationError.configurationTooComplex
            }
            var sanitized: [String: Any] = [:]
            for name in subRules.keys.sorted() {
                guard let rules = subRules[name] else { continue }
                try validatePrivilegedMappingKey(name, context: "sub-rule 名称")
                sanitized[name] = try privilegedRules(
                    rules,
                    context: "sub-rules.\(name)"
                )
            }
            result["sub-rules"] = sanitized
        }
        return result
    }

    static func isSafeTunRouteExclusion(_ source: String) -> Bool {
        guard let route = PrivilegedIPPrefix(source) else { return false }
        let forbidden = [
            PrivilegedIPPrefix("127.0.0.0/8"),
            PrivilegedIPPrefix("198.18.0.0/15"),
            PrivilegedIPPrefix("::1/128"),
            PrivilegedIPPrefix("fdfe:dcba:9876::/64"),
        ].compactMap { $0 }
        return forbidden.allSatisfy { !route.overlaps($0) }
    }
}

private enum PrivilegedProjectionLimit {
    static let proxies = 512
    static let providers = 128
    static let groups = 128
    static let rules = 20_000
    static let listItems = 1_024
    static let stringBytes = 4_096
}

private extension MihomoServerConfiguration {
    static func privilegedProxies(
        _ proxies: [[String: Any]],
        context: String
    ) throws -> [[String: Any]] {
        guard proxies.count <= PrivilegedProjectionLimit.proxies else {
            throw MihomoConfigurationError.configurationTooComplex
        }
        var names = Set<String>()
        return try proxies.enumerated().map { index, proxy in
            let sanitized = try privilegedProxy(proxy, context: "\(context)[\(index)]")
            let name = sanitized.string("name") ?? ""
            guard names.insert(name).inserted else {
                throw MihomoConfigurationError.invalidProxy("节点名称重复：\(name)")
            }
            return sanitized
        }
    }

    static func privilegedProxy(
        _ proxy: [String: Any],
        context: String
    ) throws -> [String: Any] {
        let rawType = try requiredPrivilegedString("type", in: proxy, context: context)
            .lowercased()
        guard let type = MihomoProxyProtocol(rawValue: rawType) else {
            throw MihomoConfigurationError.unsupportedProtocol(rawType)
        }

        var allowed: Set<String> = ["name", "type", "server", "port", "udp"]
        switch type {
        case .vless:
            allowed.formUnion([
                "uuid", "encryption", "flow", "network", "tls", "servername",
                "skip-cert-verify", "client-fingerprint", "reality-opts",
                "ws-opts", "grpc-opts", "http-opts", "h2-opts",
            ])
        case .vmess:
            allowed.formUnion([
                "uuid", "alterId", "alter-id", "cipher", "network", "tls",
                "servername", "skip-cert-verify", "client-fingerprint", "reality-opts",
                "ws-opts", "grpc-opts", "http-opts", "h2-opts",
            ])
        case .trojan:
            allowed.formUnion([
                "password", "network", "sni", "skip-cert-verify",
                "client-fingerprint", "reality-opts", "ws-opts", "grpc-opts",
                "http-opts", "h2-opts",
            ])
        case .shadowsocks:
            allowed.formUnion(["password", "cipher"])
        }
        try rejectPrivilegedUnknownKeys(in: proxy, allowed: allowed, context: context)

        _ = try requiredPrivilegedString("name", in: proxy, context: context)
        _ = try requiredPrivilegedString("server", in: proxy, context: context)
        guard let port = proxy.int("port"), (1...65_535).contains(port) else {
            throw MihomoConfigurationError.invalidProxy("\(context).port 无效")
        }
        try validatePrivilegedOptionalBools(
            ["udp", "tls", "skip-cert-verify"],
            in: proxy,
            context: context
        )
        try validatePrivilegedOptionalInts(["alterId", "alter-id"], in: proxy, context: context)
        for key in ["alterId", "alter-id"] {
            if let value = proxy.int(key), value < 0 {
                throw MihomoConfigurationError.invalidProxy("\(context).\(key) 不能为负数")
            }
        }
        try validatePrivilegedOptionalStrings(
            [
                "uuid", "password", "cipher", "encryption", "flow", "network",
                "servername", "sni", "client-fingerprint",
            ],
            in: proxy,
            context: context
        )
        try validatePrivilegedTransportOptions(in: proxy, protocolType: type, context: context)

        // The existing editor model performs protocol-specific validation and
        // emits a fresh mapping, so accepted input is never forwarded verbatim.
        return try MihomoProxyProfile(mapping: proxy).validated().mapping()
    }

    static func validatePrivilegedTransportOptions(
        in proxy: [String: Any],
        protocolType: MihomoProxyProtocol,
        context: String
    ) throws {
        guard protocolType != .shadowsocks else { return }
        let network = (proxy.string("network") ?? "tcp").lowercased()
        guard ["tcp", "ws", "grpc", "http", "h2"].contains(network) else {
            throw MihomoConfigurationError.invalidProxy("\(context).network 不受支持")
        }
        let optionKeys = ["ws": "ws-opts", "grpc": "grpc-opts", "http": "http-opts", "h2": "h2-opts"]
        for (transport, key) in optionKeys where proxy[key] != nil && network != transport {
            throw MihomoConfigurationError.invalidProxy("\(context).\(key) 与 network 不匹配")
        }

        if let rawReality = proxy["reality-opts"] {
            guard let reality = rawReality as? [String: Any] else {
                throw MihomoConfigurationError.invalidProxy("\(context).reality-opts 必须是映射")
            }
            try rejectPrivilegedUnknownKeys(
                in: reality,
                allowed: ["public-key", "short-id"],
                context: "\(context).reality-opts"
            )
            _ = try requiredPrivilegedString(
                "public-key",
                in: reality,
                context: "\(context).reality-opts"
            )
            try validatePrivilegedOptionalStrings(
                ["short-id"],
                in: reality,
                context: "\(context).reality-opts"
            )
        }

        switch network {
        case "ws":
            try validatePrivilegedWebSocketOptions(proxy["ws-opts"], context: context)
        case "grpc":
            try validatePrivilegedGRPCOptions(proxy["grpc-opts"], context: context)
        case "http":
            try validatePrivilegedHTTPOptions(proxy["http-opts"], context: context)
        case "h2":
            try validatePrivilegedHTTP2Options(proxy["h2-opts"], context: context)
        default:
            break
        }
    }

    static func validatePrivilegedWebSocketOptions(
        _ raw: Any?,
        context: String
    ) throws {
        guard let raw else { return }
        guard let options = raw as? [String: Any] else {
            throw MihomoConfigurationError.invalidProxy("\(context).ws-opts 必须是映射")
        }
        try rejectPrivilegedUnknownKeys(
            in: options,
            allowed: ["path", "headers"],
            context: "\(context).ws-opts"
        )
        try validatePrivilegedOptionalStrings(["path"], in: options, context: "\(context).ws-opts")
        if let rawHeaders = options["headers"] {
            try validatePrivilegedHostHeaders(rawHeaders, context: "\(context).ws-opts.headers")
        }
    }

    static func validatePrivilegedGRPCOptions(_ raw: Any?, context: String) throws {
        guard let raw else { return }
        guard let options = raw as? [String: Any] else {
            throw MihomoConfigurationError.invalidProxy("\(context).grpc-opts 必须是映射")
        }
        try rejectPrivilegedUnknownKeys(
            in: options,
            allowed: ["grpc-service-name"],
            context: "\(context).grpc-opts"
        )
        try validatePrivilegedOptionalStrings(
            ["grpc-service-name"],
            in: options,
            context: "\(context).grpc-opts"
        )
    }

    static func validatePrivilegedHTTPOptions(_ raw: Any?, context: String) throws {
        guard let raw else { return }
        guard let options = raw as? [String: Any] else {
            throw MihomoConfigurationError.invalidProxy("\(context).http-opts 必须是映射")
        }
        try rejectPrivilegedUnknownKeys(
            in: options,
            allowed: ["method", "path", "headers"],
            context: "\(context).http-opts"
        )
        try validatePrivilegedOptionalStrings(["method"], in: options, context: "\(context).http-opts")
        if let path = options["path"] {
            _ = try privilegedStringList(path, context: "\(context).http-opts.path")
        }
        if let headers = options["headers"] {
            try validatePrivilegedHostHeaders(headers, context: "\(context).http-opts.headers")
        }
    }

    static func validatePrivilegedHTTP2Options(_ raw: Any?, context: String) throws {
        guard let raw else { return }
        guard let options = raw as? [String: Any] else {
            throw MihomoConfigurationError.invalidProxy("\(context).h2-opts 必须是映射")
        }
        try rejectPrivilegedUnknownKeys(
            in: options,
            allowed: ["host", "path"],
            context: "\(context).h2-opts"
        )
        try validatePrivilegedOptionalStrings(["path"], in: options, context: "\(context).h2-opts")
        if let host = options["host"] {
            _ = try privilegedStringList(host, context: "\(context).h2-opts.host")
        }
    }

    static func validatePrivilegedHostHeaders(_ raw: Any, context: String) throws {
        guard let headers = raw as? [String: Any], headers.count <= 2 else {
            throw MihomoConfigurationError.invalidProxy("\(context) 必须是 Host 请求头映射")
        }
        for key in headers.keys {
            guard key == "Host" || key == "host", let value = headers[key] else {
                throw MihomoConfigurationError.invalidProxy("\(context) 只允许 Host 请求头")
            }
            _ = try privilegedStringList(value, context: "\(context).\(key)")
        }
    }

    static func privilegedProxyProviders(_ providers: [String: Any]) throws -> [String: Any] {
        guard providers.count <= PrivilegedProjectionLimit.providers else {
            throw MihomoConfigurationError.configurationTooComplex
        }
        var result: [String: Any] = [:]
        for name in providers.keys.sorted() {
            try validatePrivilegedMappingKey(name, context: "Provider 名称")
            guard let provider = providers[name] as? [String: Any] else {
                throw MihomoConfigurationError.invalidProxy("Provider \(name) 不是映射")
            }
            let type = provider.string("type")?.lowercased() ?? "http"
            guard type == "inline" else {
                throw MihomoConfigurationError.unsupportedProviderType(name: name, type: type)
            }
            try rejectPrivilegedUnknownKeys(
                in: provider,
                allowed: ["type", "payload"],
                context: "proxy-providers.\(name)"
            )
            guard let payload = provider["payload"] as? [[String: Any]], !payload.isEmpty else {
                throw MihomoConfigurationError.invalidProxy("Provider \(name) 缺少 inline payload")
            }
            result[name] = [
                "type": "inline",
                "payload": try privilegedProxies(
                    payload,
                    context: "proxy-providers.\(name).payload"
                ),
            ]
        }
        return result
    }

    static func privilegedProxyGroups(
        _ groups: [[String: Any]]
    ) throws -> [[String: Any]] {
        var names = Set<String>()
        return try groups.map { group in
            let sanitized = try privilegedProxyGroup(group)
            let name = sanitized.string("name") ?? ""
            guard names.insert(name).inserted else {
                throw MihomoConfigurationError.invalidProxy("代理组名称重复：\(name)")
            }
            return sanitized
        }
    }

    static func privilegedProxyGroup(_ group: [String: Any]) throws -> [String: Any] {
        let name = try requiredPrivilegedString("name", in: group, context: "proxy-group")
        let type = try requiredPrivilegedString("type", in: group, context: name).lowercased()
        guard type == "select" else {
            throw MihomoConfigurationError.invalidProxy("特权运行时只支持 select 代理组")
        }
        try rejectPrivilegedUnknownKeys(
            in: group,
            allowed: ["name", "type", "proxies", "use", "disable-udp"],
            context: "proxy-group.\(name)"
        )
        var result: [String: Any] = ["name": name, "type": type]
        for key in ["proxies", "use"] where group[key] != nil {
            guard let value = group[key] else { continue }
            result[key] = try privilegedStringList(value, context: "proxy-group.\(name).\(key)")
        }
        guard result["proxies"] != nil || result["use"] != nil else {
            throw MihomoConfigurationError.invalidProxy("代理组 \(name) 没有节点来源")
        }
        if group["disable-udp"] != nil {
            guard let value = group.bool("disable-udp") else {
                throw MihomoConfigurationError.invalidProxy("proxy-group.\(name).disable-udp 无效")
            }
            result["disable-udp"] = value
        }
        return result
    }

    static func privilegedRuleProviders(_ providers: [String: Any]) throws -> [String: Any] {
        guard providers.count <= PrivilegedProjectionLimit.providers else {
            throw MihomoConfigurationError.configurationTooComplex
        }
        var result: [String: Any] = [:]
        for name in providers.keys.sorted() {
            try validatePrivilegedMappingKey(name, context: "Rule Provider 名称")
            guard let provider = providers[name] as? [String: Any] else {
                throw MihomoConfigurationError.invalidProxy("Rule Provider \(name) 不是映射")
            }
            let type = provider.string("type")?.lowercased() ?? "http"
            guard type == "inline" else {
                throw MihomoConfigurationError.unsupportedProviderType(name: name, type: type)
            }
            try rejectPrivilegedUnknownKeys(
                in: provider,
                allowed: ["type", "behavior", "payload"],
                context: "rule-providers.\(name)"
            )
            let behavior = try requiredPrivilegedString(
                "behavior",
                in: provider,
                context: "rule-providers.\(name)"
            ).lowercased()
            guard ["domain", "ipcidr", "classical"].contains(behavior),
                let payload = provider["payload"]
            else {
                throw MihomoConfigurationError.invalidProxy("Rule Provider \(name) 无效")
            }
            let sanitizedPayload =
                behavior == "classical"
                ? try privilegedRules(payload, context: "rule-providers.\(name).payload")
                : try privilegedStringList(
                    payload,
                    context: "rule-providers.\(name).payload",
                    maximumItems: PrivilegedProjectionLimit.rules
                )
            result[name] = [
                "type": "inline",
                "behavior": behavior,
                "payload": sanitizedPayload,
            ]
        }
        return result
    }

    static func privilegedRules(_ raw: Any, context: String) throws -> [String] {
        let rules = try privilegedStringList(
            raw,
            context: context,
            maximumItems: PrivilegedProjectionLimit.rules
        )
        let allowed = Set([
            "DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "IP-CIDR", "IP-CIDR6",
            "SRC-IP-CIDR", "SRC-PORT", "DST-PORT", "NETWORK", "RULE-SET",
            "SUB-RULE", "MATCH", "FINAL",
        ])
        return try rules.map { rule in
            let parts = rule.split(separator: ",", omittingEmptySubsequences: false)
            let type =
                parts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased() ?? ""
            let minimumParts = type == "MATCH" || type == "FINAL" ? 2 : 3
            guard allowed.contains(type), parts.count >= minimumParts else {
                throw MihomoConfigurationError.invalidProxy(
                    "\(context) 包含不支持的规则：\(rule)"
                )
            }
            return rule
        }
    }

    static func requiredPrivilegedString(
        _ key: String,
        in mapping: [String: Any],
        context: String
    ) throws -> String {
        guard let value = mapping.string(key) else {
            throw MihomoConfigurationError.invalidProxy("\(context).\(key) 必须是字符串")
        }
        return try privilegedString(value, context: "\(context).\(key)")
    }

    static func privilegedString(_ raw: String, context: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !value.isEmpty,
            value.utf8.count <= PrivilegedProjectionLimit.stringBytes,
            !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            throw MihomoConfigurationError.invalidProxy("\(context) 包含无效字符串")
        }
        return value
    }

    static func privilegedStringList(
        _ raw: Any,
        context: String,
        maximumItems: Int = PrivilegedProjectionLimit.listItems
    ) throws -> [String] {
        let values: [String]
        if let value = raw as? String {
            values = [value]
        } else if let list = raw as? [String] {
            values = list
        } else {
            throw MihomoConfigurationError.invalidProxy("\(context) 必须是字符串列表")
        }
        guard !values.isEmpty, values.count <= maximumItems else {
            throw MihomoConfigurationError.configurationTooComplex
        }
        return try values.map { try privilegedString($0, context: context) }
    }

    static func validatePrivilegedMappingKey(_ raw: String, context: String) throws {
        let sanitized = try privilegedString(raw, context: context)
        guard sanitized == raw else {
            throw MihomoConfigurationError.invalidProxy("\(context) 不能包含首尾空白")
        }
    }

    static func rejectPrivilegedUnknownKeys(
        in mapping: [String: Any],
        allowed: Set<String>,
        context: String
    ) throws {
        let unknown = Set(mapping.keys).subtracting(allowed).sorted()
        guard unknown.isEmpty else {
            throw MihomoConfigurationError.invalidProxy(
                "\(context) 包含特权运行时不允许的字段：\(unknown.joined(separator: ", "))"
            )
        }
    }

    static func validatePrivilegedOptionalStrings(
        _ keys: [String],
        in mapping: [String: Any],
        context: String
    ) throws {
        for key in keys where mapping[key] != nil {
            _ = try requiredPrivilegedString(key, in: mapping, context: context)
        }
    }

    static func validatePrivilegedOptionalInts(
        _ keys: [String],
        in mapping: [String: Any],
        context: String
    ) throws {
        for key in keys where mapping[key] != nil {
            guard mapping.int(key) != nil else {
                throw MihomoConfigurationError.invalidProxy("\(context).\(key) 必须是整数")
            }
        }
    }

    static func validatePrivilegedOptionalBools(
        _ keys: [String],
        in mapping: [String: Any],
        context: String
    ) throws {
        for key in keys where mapping[key] != nil {
            guard mapping.bool(key) != nil else {
                throw MihomoConfigurationError.invalidProxy("\(context).\(key) 必须是布尔值")
            }
        }
    }
}

private struct PrivilegedIPPrefix {
    let bytes: [UInt8]
    let prefixLength: Int

    init?(_ source: String) {
        let parts = source.trimmingCharacters(in: .whitespacesAndNewlines).split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard parts.count == 2, let prefixLength = Int(parts[1]) else { return nil }
        let address = String(parts[0])

        var ipv4 = in_addr()
        if address.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 {
            guard (0...32).contains(prefixLength) else { return nil }
            self.bytes = withUnsafeBytes(of: &ipv4) { Array($0) }
            self.prefixLength = prefixLength
            return
        }

        var ipv6 = in6_addr()
        if address.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1 {
            guard (0...128).contains(prefixLength) else { return nil }
            self.bytes = withUnsafeBytes(of: &ipv6) { Array($0) }
            self.prefixLength = prefixLength
            return
        }
        return nil
    }

    func overlaps(_ other: Self) -> Bool {
        guard bytes.count == other.bytes.count else { return false }
        let sharedPrefix = min(prefixLength, other.prefixLength)
        let fullBytes = sharedPrefix / 8
        if fullBytes > 0, bytes[..<fullBytes] != other.bytes[..<fullBytes] { return false }
        let remainingBits = sharedPrefix % 8
        guard remainingBits > 0 else { return true }
        let mask = UInt8.max << (8 - remainingBits)
        return bytes[fullBytes] & mask == other.bytes[fullBytes] & mask
    }
}
