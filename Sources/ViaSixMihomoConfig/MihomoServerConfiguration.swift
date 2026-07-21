import Darwin
import Foundation

public struct MihomoServerConfiguration: Equatable, Sendable {
    public static let placeholderCredential = "00000000-0000-0000-0000-000000000000"
    public static let placeholderServerName = "example.com"

    private static let retainedServerKeys = [
        "proxies",
        "proxy-providers",
        "proxy-groups",
        "rules",
        "rule-providers",
        "sub-rules",
    ]
    private let canonicalData: Data

    public init(data: Data) throws {
        let input = try MihomoYAML.mapping(from: data)
        if input["outbounds"] != nil || input["inbounds"] != nil {
            throw MihomoConfigurationError.legacyXrayConfiguration
        }
        let server = try Self.serverMapping(from: input)
        try Self.validateServerMapping(server)
        canonicalData = try MihomoYAML.data(from: server)
    }

    public init(profile: MihomoProxyProfile) throws {
        let proxy = try profile.mapping()
        let server: [String: Any] = ["proxies": [proxy]]
        try Self.validateServerMapping(server)
        canonicalData = try MihomoYAML.data(from: server)
    }

    public var data: Data { canonicalData }

    public var summary: MihomoProfileSummary {
        let root = rawMapping()
        let proxies = root.mappings("proxies") ?? []
        return MihomoProfileSummary(
            inlineProxyCount: proxies.count,
            providerCount: root.mapping("proxy-providers")?.count ?? 0,
            groupCount: root.mappings("proxy-groups")?.count ?? 0,
            ruleCount: (root["rules"] as? [String])?.count ?? 0,
            primaryProxyName: proxies.first?.string("name")
        )
    }

    /// Whether ViaSix can safely apply a speed-test result by replacing the
    /// first inline proxy's `server` value. Provider-only profiles remain
    /// launchable, but their remote contents are intentionally not rewritten.
    public var hasReplaceablePrimaryServer: Bool {
        rawMapping().mappings("proxies")?.contains(where: {
            $0.string("server")?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }) == true
    }

    /// Distinguishes provider-backed profiles without exposing their raw YAML
    /// representation to callers.
    public var isProviderOnly: Bool {
        let root = rawMapping()
        return !hasReplaceablePrimaryServer && !(root.mapping("proxy-providers") ?? [:]).isEmpty
    }

    public func formattedData() throws -> Data {
        try MihomoYAML.data(from: rawMapping())
    }

    public func primaryProfile() throws -> MihomoProxyProfile {
        guard
            let proxy = rawMapping().mappings("proxies")?.first(where: {
                $0.string("server")?.isEmpty == false
            })
        else {
            throw MihomoConfigurationError.missingInlineProxy
        }
        return try MihomoProxyProfile(mapping: proxy).validated()
    }

    public func replacingPrimaryServer(with address: String) throws -> Self {
        let normalized = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw MihomoConfigurationError.invalidProxy("服务器地址为空")
        }
        var root = rawMapping()
        guard var proxies = root.mappings("proxies"),
            let index = proxies.firstIndex(where: {
                $0.string("server")?.isEmpty == false
            })
        else {
            throw MihomoConfigurationError.missingInlineProxy
        }
        proxies[index]["server"] = normalized
        root["proxies"] = proxies
        return try Self(data: MihomoYAML.data(from: root))
    }

    public func runtimeConfiguration(
        options: MihomoRuntimeOptions,
        projection: MihomoRuntimeProjection = .user,
        replacingPrimaryServerWith address: String? = nil
    ) throws -> Data {
        try Self.runtimeConfiguration(
            server: self,
            options: options,
            projection: projection,
            replacingPrimaryServerWith: address
        )
    }

    public static func runtimeConfiguration(
        server: Self?,
        options: MihomoRuntimeOptions,
        projection: MihomoRuntimeProjection = .user,
        replacingPrimaryServerWith address: String? = nil
    ) throws -> Data {
        try validate(options: options, projection: projection)

        var serverRoot = server?.rawMapping() ?? [:]
        if let address {
            guard let server else {
                if options.routingMode != .direct {
                    throw MihomoConfigurationError.missingProxySource
                }
                return try composeRuntime(
                    server: [:],
                    options: options,
                    projection: projection
                )
            }
            serverRoot = try server.replacingPrimaryServer(with: address).rawMapping()
        }
        if options.routingMode != .direct {
            try validateServerMapping(serverRoot)
        } else {
            serverRoot = [:]
        }
        if projection == .privilegedTun {
            serverRoot = try privilegedServerMapping(from: serverRoot)
        }
        return try composeRuntime(
            server: serverRoot,
            options: options,
            projection: projection
        )
    }

    public static func proxyServerAddress(in data: Data) -> String? {
        guard let configuration = try? Self(data: data) else { return nil }
        return configuration.rawMapping().mappings("proxies")?
            .first(where: { $0.string("server")?.isEmpty == false })?
            .string("server")
    }

    private func rawMapping() -> [String: Any] {
        // `canonicalData` was produced by this module and failure here would
        // indicate a programmer error rather than malformed user input.
        (try? MihomoYAML.mapping(from: canonicalData)) ?? [:]
    }

    private static func serverMapping(from input: [String: Any]) throws -> [String: Any] {
        if input["name"] != nil,
            input["type"] != nil,
            retainedServerKeys.allSatisfy({ input[$0] == nil })
        {
            return ["proxies": [input]]
        }

        var server: [String: Any] = [:]
        for key in retainedServerKeys {
            if let value = input[key] {
                server[key] = value
            }
        }
        if let providers = input.mapping("proxy-providers") {
            server["proxy-providers"] = try sanitizedProviders(
                providers,
                directory: "providers"
            )
        }
        if let providers = input.mapping("rule-providers") {
            server["rule-providers"] = try sanitizedProviders(
                providers,
                directory: "rules"
            )
        }
        guard !server.isEmpty else {
            throw MihomoConfigurationError.missingProxySource
        }
        return server
    }

    private static func validateServerMapping(_ root: [String: Any]) throws {
        if let rawRules = root["rules"], !(rawRules is [String]) {
            throw MihomoConfigurationError.unsupportedValue("rules 必须是字符串列表")
        }

        let proxies = root.mappings("proxies") ?? []
        let providers = root.mapping("proxy-providers") ?? [:]
        guard !proxies.isEmpty || !providers.isEmpty else {
            throw MihomoConfigurationError.missingProxySource
        }

        var names = Set<String>()
        for proxy in proxies {
            guard let name = proxy.string("name")?.trimmingCharacters(in: .whitespacesAndNewlines),
                !name.isEmpty,
                let type = proxy.string("type")?.trimmingCharacters(in: .whitespacesAndNewlines),
                !type.isEmpty
            else {
                throw MihomoConfigurationError.invalidProxy("节点必须包含非空 name 和 type")
            }
            guard names.insert(name).inserted else {
                throw MihomoConfigurationError.invalidProxy("节点名称重复：\(name)")
            }

            let hasServer = proxy["server"] != nil
            let hasPort = proxy["port"] != nil
            if hasServer || hasPort {
                guard
                    let server = proxy.string("server")?.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                    !server.isEmpty,
                    let port = proxy.int("port"),
                    (1...65_535).contains(port)
                else {
                    throw MihomoConfigurationError.invalidProxy(
                        "节点必须包含 server 和有效 port"
                    )
                }
            }
            if proxyContainsPlaceholder(proxy) {
                throw MihomoConfigurationError.placeholderConfiguration
            }
        }
    }

    private static func composeRuntime(
        server: [String: Any],
        options: MihomoRuntimeOptions,
        projection: MihomoRuntimeProjection
    ) throws -> Data {
        var runtime: [String: Any] = [
            "mixed-port": options.mixedPort,
            "allow-lan": false,
            "bind-address": options.listenAddress,
            "mode": options.routingMode.rawValue,
            "log-level": options.logLevel.rawValue,
            "ipv6": options.ipv6Enabled,
            "unified-delay": true,
            "tcp-concurrent": true,
            "profile": [
                "store-selected": false,
                "store-fake-ip": projection == .privilegedTun,
            ],
        ]

        if projection == .user, let controller = options.externalController {
            runtime["external-controller"] = "127.0.0.1:\(controller.port)"
            runtime["secret"] = controller.secret
        }

        // Direct mode must be independent from every remote proxy and provider.
        // Besides reducing attack surface, this guarantees that selecting
        // direct cannot trigger subscription refreshes or outbound handshakes.
        if options.routingMode != .direct {
            for key in retainedServerKeys where server[key] != nil {
                runtime[key] = server[key]
            }
        }

        if var proxies = runtime.mappings("proxies") {
            for index in proxies.indices {
                proxies[index]["udp"] = options.udpEnabled
            }
            runtime["proxies"] = proxies
        }

        if options.sniffingEnabled {
            runtime["sniffer"] = [
                "enable": true,
                "force-dns-mapping": true,
                "parse-pure-ip": true,
                "override-destination": true,
                "sniff": [
                    "HTTP": [
                        "ports": ["80", "8080-8880"],
                        "override-destination": true,
                    ],
                    "TLS": ["ports": ["443", "8443"]],
                    "QUIC": ["ports": ["443", "8443"]],
                ],
            ]
        }

        try installManagedPolicy(in: &runtime, options: options)

        if projection == .privilegedTun {
            guard let tun = options.tun else {
                throw MihomoConfigurationError.missingTunConfiguration
            }
            var tunMapping: [String: Any] = [
                "enable": true,
                "stack": tun.stack.rawValue,
                "auto-route": true,
                "strict-route": tun.strictRoute,
                "auto-detect-interface": true,
                "dns-hijack": ["any:53", "tcp://any:53"],
                "mtu": tun.mtu,
            ]
            if !tun.routeExcludeAddresses.isEmpty {
                tunMapping["route-exclude-address"] = tun.routeExcludeAddresses
            }
            runtime["tun"] = tunMapping
            runtime["dns"] = [
                "enable": true,
                "ipv6": options.ipv6Enabled,
                "enhanced-mode": "fake-ip",
                "fake-ip-range": "198.18.0.1/16",
                "fake-ip-range6": "fdfe:dcba:9876::1/64",
                "respect-rules": true,
                "default-nameserver": ["1.1.1.1", "8.8.8.8"],
                "nameserver": [
                    "https://1.1.1.1/dns-query",
                    "https://8.8.8.8/dns-query",
                ],
                "proxy-server-nameserver": [
                    "https://1.1.1.1/dns-query",
                    "https://8.8.8.8/dns-query",
                ],
            ]
        } else {
            runtime["tun"] = ["enable": false]
        }

        return try MihomoYAML.data(from: runtime, header: "Generated by ViaSix for Mihomo")
    }

    private static func installManagedPolicy(
        in runtime: inout [String: Any],
        options: MihomoRuntimeOptions
    ) throws {
        guard options.routingMode == .rule else {
            if options.routingMode == .direct {
                runtime["rules"] = ["MATCH,DIRECT"]
            }
            return
        }

        let proxies = runtime.mappings("proxies") ?? []
        let providers = runtime.mapping("proxy-providers") ?? [:]
        var groups = runtime.mappings("proxy-groups") ?? []
        if groups.isEmpty {
            var managed: [String: Any] = [
                "name": "ViaSix",
                "type": "select",
            ]
            let names = proxies.compactMap { $0.string("name") }
            if !names.isEmpty {
                managed["proxies"] = names
            }
            let providerNames = providers.keys.sorted()
            if !providerNames.isEmpty {
                managed["use"] = providerNames
            }
            groups = [managed]
            runtime["proxy-groups"] = groups
        }

        let target =
            groups.first?.string("name")
            ?? proxies.first?.string("name")
        guard let target, !target.isEmpty else {
            throw MihomoConfigurationError.missingProxySource
        }

        let importedRules: [String]
        if let rawRules = runtime["rules"] {
            guard let rules = rawRules as? [String] else {
                throw MihomoConfigurationError.unsupportedValue("rules 必须是字符串列表")
            }
            importedRules = rules
        } else {
            importedRules = []
        }
        var rules = importedRules
        if options.bypassPrivateNetworks {
            let privateRules = [
                "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve",
                "IP-CIDR,100.64.0.0/10,DIRECT,no-resolve",
                "IP-CIDR,127.0.0.0/8,DIRECT,no-resolve",
                "IP-CIDR,169.254.0.0/16,DIRECT,no-resolve",
                "IP-CIDR,172.16.0.0/12,DIRECT,no-resolve",
                "IP-CIDR,192.168.0.0/16,DIRECT,no-resolve",
                "IP-CIDR6,::1/128,DIRECT,no-resolve",
                "IP-CIDR6,fc00::/7,DIRECT,no-resolve",
                "IP-CIDR6,fe80::/10,DIRECT,no-resolve",
            ]
            let existing = Set(rules)
            rules.insert(contentsOf: privateRules.filter { !existing.contains($0) }, at: 0)
        }
        let hasFinalRule = rules.contains { rule in
            let prefix = rule.split(separator: ",", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            return prefix == "MATCH" || prefix == "FINAL"
        }
        if !hasFinalRule {
            rules.append("MATCH,\(target)")
        }
        runtime["rules"] = rules
    }

    private static func validate(
        options: MihomoRuntimeOptions,
        projection: MihomoRuntimeProjection
    ) throws {
        guard isLoopbackHost(options.listenAddress) else {
            throw MihomoConfigurationError.invalidListenAddress
        }
        guard (1...65_535).contains(options.mixedPort) else {
            throw MihomoConfigurationError.invalidMixedPort
        }
        if let controller = options.externalController {
            guard (1...65_535).contains(controller.port), controller.port != options.mixedPort else {
                throw MihomoConfigurationError.invalidControllerPort
            }
            let secret = controller.secret.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !secret.isEmpty, secret.utf8.count <= 512 else {
                throw MihomoConfigurationError.invalidControllerSecret
            }
        }
        if projection == .privilegedTun {
            guard let tun = options.tun else {
                throw MihomoConfigurationError.missingTunConfiguration
            }
            guard (1_280...9_000).contains(tun.mtu) else {
                throw MihomoConfigurationError.invalidTunMTU
            }
            guard tun.routeExcludeAddresses.count <= 32 else {
                throw MihomoConfigurationError.tooManyTunRouteExclusions
            }
            for route in tun.routeExcludeAddresses {
                guard isSafeTunRouteExclusion(route) else {
                    throw MihomoConfigurationError.invalidTunRouteExclusion(route)
                }
            }
        }
    }

    private static func isLoopbackHost(_ value: String) -> Bool {
        let host = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host == "localhost" || host == "::1" { return true }

        var address = in_addr()
        let isIPv4 = host.withCString { inet_pton(AF_INET, $0, &address) == 1 }
        guard isIPv4 else { return false }
        return (UInt32(bigEndian: address.s_addr) >> 24) == 127
    }

    private static func proxyContainsPlaceholder(_ proxy: [String: Any]) -> Bool {
        for key in ["uuid", "password"] {
            if proxy.string(key)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                == placeholderCredential
            {
                return true
            }
        }
        for key in ["servername", "sni"] {
            if proxy.string(key)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                == placeholderServerName
            {
                return true
            }
        }
        return false
    }

    private static func sanitizedProviders(
        _ providers: [String: Any],
        directory: String
    ) throws -> [String: Any] {
        var sanitized: [String: Any] = [:]
        for name in providers.keys.sorted() {
            guard var provider = providers[name] as? [String: Any] else {
                throw MihomoConfigurationError.invalidProxy("Provider \(name) 不是映射")
            }
            let type = provider.string("type")?.lowercased() ?? "http"
            switch type {
            case "http":
                provider["path"] = "\(directory)/\(safeProviderFileName(name)).yaml"
            case "inline":
                provider.removeValue(forKey: "path")
            default:
                throw MihomoConfigurationError.unsupportedProviderType(
                    name: name,
                    type: type
                )
            }
            sanitized[name] = provider
        }
        return sanitized
    }

    private static func safeProviderFileName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let stem = String(
            name.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
        ).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in name.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        let prefix = stem.isEmpty ? "provider" : String(stem.prefix(64))
        return "\(prefix)-\(String(hash, radix: 16))"
    }
}

public struct MihomoProfileSummary: Equatable, Sendable {
    public let inlineProxyCount: Int
    public let providerCount: Int
    public let groupCount: Int
    public let ruleCount: Int
    public let primaryProxyName: String?

    public init(
        inlineProxyCount: Int,
        providerCount: Int,
        groupCount: Int,
        ruleCount: Int,
        primaryProxyName: String?
    ) {
        self.inlineProxyCount = inlineProxyCount
        self.providerCount = providerCount
        self.groupCount = groupCount
        self.ruleCount = ruleCount
        self.primaryProxyName = primaryProxyName
    }
}
