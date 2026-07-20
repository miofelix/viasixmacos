import Foundation

/// Helpers for keeping the user-facing server and local settings separate
/// while still producing the complete Xray document required at runtime.
public extension ConfigTemplate {
    static func serverConfiguration(from data: Data) throws -> Data {
        let object = try configurationDictionary(from: data)
        let outbound = try proxyOutbound(from: object)
        return try prettyJSON(outbound)
    }

    static func localConfiguration(from data: Data) throws -> LocalProxyConfiguration? {
        let object = try configurationDictionary(from: data)
        guard let inbounds = object["inbounds"] as? [[String: Any]] else { return nil }
        guard
            let inbound = inbounds.first(where: {
                (($0["protocol"] as? String)?.lowercased() == "mixed")
            })
        else { return nil }

        let listen = (inbound["listen"] as? String) ?? AppMetadata.proxyHost
        let port = inbound["port"] as? Int ?? AppMetadata.proxyPort
        let settings = inbound["settings"] as? [String: Any]
        let sniffing = inbound["sniffing"] as? [String: Any]
        let routing = object["routing"] as? [String: Any]
        let rules = routing?["rules"] as? [[String: Any]] ?? []
        let bypassPrivate = rules.contains { rule in
            isPrivateNetworkDirectRule(rule)
        }
        let routingMode = inferredRoutingMode(in: object, rules: rules)
        return try LocalProxyConfiguration(
            listenAddress: listen,
            port: port,
            udpEnabled: settings?["udp"] as? Bool ?? true,
            sniffingEnabled: sniffing?["enabled"] as? Bool ?? false,
            bypassPrivateNetworks: bypassPrivate,
            logLevel: ProxyLogLevel(rawValue: (object["log"] as? [String: Any])?["loglevel"] as? String ?? "warning")
                ?? .warning,
            routingMode: routingMode
        ).validated()
    }

    static func runtimeConfiguration(
        server: Data,
        local: LocalProxyConfiguration,
        address: String
    ) throws -> Data {
        try runtimeConfiguration(server: Optional(server), local: local, address: address)
    }

    /// Builds the complete runtime document. Direct mode deliberately accepts
    /// no server configuration and omits the proxy outbound, while rule and
    /// global modes require a usable server.
    static func runtimeConfiguration(
        server: Data?,
        local: LocalProxyConfiguration,
        address: String
    ) throws -> Data {
        let local = try local.validated()
        guard local.routingMode != .direct else {
            return try composeTemplate(proxyOutbound: nil, local: local)
        }
        guard let server else {
            throw ConfigTemplateError.connectionNotConfigured
        }
        let serverObject = try configurationDictionary(from: server)
        let outbound = try replacingAddress(in: try proxyOutbound(from: serverObject), with: address)
        return try composeTemplate(proxyOutbound: outbound, local: local)
    }

    static func updatingServerConfiguration(
        in template: Data,
        with server: Data
    ) throws -> Data {
        var object = try configurationDictionary(from: template)
        let serverObject = try configurationDictionary(from: server)
        let outbound = try proxyOutbound(from: serverObject)
        var outbounds = object["outbounds"] as? [[String: Any]] ?? []
        if let index = outbounds.firstIndex(where: { $0["tag"] as? String == "proxy" }) {
            outbounds[index] = outbound
        } else {
            outbounds.insert(outbound, at: 0)
        }
        object["outbounds"] = outbounds
        return try prettyJSON(object)
    }

    static func updatingLocalConfiguration(
        in template: Data,
        with local: LocalProxyConfiguration
    ) throws -> Data {
        let validated = try local.validated()
        var object = try configurationDictionary(from: template)
        var inbounds = object["inbounds"] as? [[String: Any]] ?? []
        let inbound = inboundObject(for: validated)
        if let index = inbounds.firstIndex(where: {
            (($0["protocol"] as? String)?.lowercased() == "mixed")
        }) {
            inbounds[index] = inbound
        } else {
            inbounds.insert(inbound, at: 0)
        }
        object["inbounds"] = inbounds

        var log = object["log"] as? [String: Any] ?? [:]
        log["loglevel"] = validated.logLevel.rawValue
        object["log"] = log

        var routing = object["routing"] as? [String: Any] ?? [:]
        var rules = routing["rules"] as? [[String: Any]] ?? []
        switch validated.routingMode {
        case .rule:
            rules.removeAll(where: isManagedRoutingRule)
            if validated.bypassPrivateNetworks {
                rules.append(privateNetworkDirectRule)
            }
        case .global, .direct:
            // These modes intentionally bypass user routing rules. Keeping an
            // old rule ahead of the catch-all would make the selected mode
            // misleading and could leak traffic through an unexpected path.
            rules = [catchAllRule(for: validated.routingMode)]
        }

        if rules.isEmpty, routing.keys.allSatisfy({ $0 == "domainStrategy" || $0 == "rules" }) {
            object.removeValue(forKey: "routing")
        } else {
            routing["domainStrategy"] = routing["domainStrategy"] ?? "AsIs"
            routing["rules"] = rules
            object["routing"] = routing
        }
        return try prettyJSON(object)
    }

    static func serverProfile(in data: Data) throws -> XrayServerProfile {
        let object = try configurationDictionary(from: data)
        let outbound = try proxyOutbound(from: object)
        let parsedProtocol = XrayServerProtocol(rawValue: (outbound["protocol"] as? String ?? "vless").lowercased())
        guard let serverProtocol = parsedProtocol else {
            throw XrayServerProfileError.unsupportedProtocol(outbound["protocol"] as? String ?? "unknown")
        }
        let stream = outbound["streamSettings"] as? [String: Any] ?? [:]
        let transport =
            XrayTransport(rawValue: (stream["network"] as? String ?? "ws").lowercased())
            ?? .websocket
        let security =
            XrayTransportSecurity(rawValue: (stream["security"] as? String ?? "none").lowercased())
            ?? .none
        let tls = stream["tlsSettings"] as? [String: Any] ?? [:]
        let reality = stream["realitySettings"] as? [String: Any] ?? [:]
        let ws = stream["wsSettings"] as? [String: Any] ?? [:]
        let grpc = stream["grpcSettings"] as? [String: Any] ?? [:]

        let settings = outbound["settings"] as? [String: Any] ?? [:]
        let first: [String: Any]
        let serverAddress: String
        let userID: String
        let encryption: String
        let flow: String
        let alterID: Int
        let vmessSecurity: String
        switch serverProtocol {
        case .vless, .vmess:
            guard
                let vnext = settings["vnext"] as? [[String: Any]],
                let firstVNext = vnext.first,
                let users = firstVNext["users"] as? [[String: Any]],
                let user = users.first
            else { throw XrayServerProfileError.unsupportedStructure }
            first = firstVNext
            serverAddress = firstVNext["address"] as? String ?? "2001:db8::1"
            userID = user["id"] as? String ?? ""
            encryption = user["encryption"] as? String ?? "none"
            flow = user["flow"] as? String ?? ""
            alterID = user["alterId"] as? Int ?? 0
            vmessSecurity = user["security"] as? String ?? "auto"
        case .trojan:
            guard let servers = settings["servers"] as? [[String: Any]], let firstServer = servers.first else {
                throw XrayServerProfileError.unsupportedStructure
            }
            first = firstServer
            serverAddress = firstServer["address"] as? String ?? "2001:db8::1"
            userID = firstServer["password"] as? String ?? ""
            encryption = "none"
            flow = firstServer["flow"] as? String ?? ""
            alterID = 0
            vmessSecurity = "auto"
        case .shadowsocks:
            guard let servers = settings["servers"] as? [[String: Any]], let firstServer = servers.first else {
                throw XrayServerProfileError.unsupportedStructure
            }
            first = firstServer
            serverAddress = firstServer["address"] as? String ?? "2001:db8::1"
            userID = firstServer["password"] as? String ?? ""
            encryption = firstServer["method"] as? String ?? "chacha20-ietf-poly1305"
            flow = ""
            alterID = 0
            vmessSecurity = "auto"
        }

        return XrayServerProfile(
            protocolName: serverProtocol,
            serverAddress: serverAddress,
            serverPort: first["port"] as? Int ?? (Int(first["port"] as? String ?? "") ?? 443),
            userID: userID,
            encryption: encryption,
            flow: flow,
            alterID: alterID,
            vmessSecurity: vmessSecurity,
            transport: transport,
            security: security,
            serverName: (security == .reality ? reality["serverName"] : tls["serverName"]) as? String ?? "",
            host: (ws["headers"] as? [String: Any])?["Host"] as? String ?? "",
            path: ws["path"] as? String ?? "/",
            serviceName: grpc["serviceName"] as? String ?? "",
            allowInsecure: tls["allowInsecure"] as? Bool ?? false,
            fingerprint: (security == .reality ? reality["fingerprint"] : tls["fingerprint"]) as? String ?? "chrome",
            realityPublicKey: reality["publicKey"] as? String ?? "",
            realityShortID: reality["shortId"] as? String ?? "",
            realitySpiderX: reality["spiderX"] as? String ?? ""
        )
    }

    static func serverConfiguration(for profile: XrayServerProfile) throws -> Data {
        let profile = try profile.validated()
        if profile.protocolName == .trojan {
            return try trojanServerConfiguration(for: profile)
        }
        if profile.protocolName == .shadowsocks {
            return try shadowsocksServerConfiguration(for: profile)
        }
        var user: [String: Any] = [
            "id": profile.userID
        ]
        if profile.protocolName == .vless {
            user["encryption"] = profile.encryption
            if !profile.flow.isEmpty { user["flow"] = profile.flow }
        } else {
            user["alterId"] = profile.alterID
            user["security"] = profile.vmessSecurity
        }
        var outbound: [String: Any] = [
            "tag": "proxy",
            "protocol": profile.protocolName.rawValue,
            "settings": [
                "vnext": [
                    [
                        "address": profile.serverAddress,
                        "port": profile.serverPort,
                        "users": [user],
                    ]
                ]
            ],
        ]
        var stream: [String: Any] = [
            "network": profile.transport.rawValue,
            "security": profile.security.rawValue,
        ]
        switch profile.transport {
        case .websocket:
            stream["wsSettings"] = [
                "host": profile.host.isEmpty ? profile.serverName : profile.host,
                "path": profile.path.isEmpty ? "/" : profile.path,
                "headers": profile.host.isEmpty ? [:] : ["Host": profile.host],
            ]
        case .grpc:
            stream["grpcSettings"] = ["serviceName": profile.serviceName]
        case .tcp:
            break
        }
        switch profile.security {
        case .tls:
            stream["tlsSettings"] = [
                "serverName": profile.serverName,
                "allowInsecure": profile.allowInsecure,
                "fingerprint": profile.fingerprint,
            ]
        case .reality:
            stream["realitySettings"] = [
                "serverName": profile.serverName,
                "fingerprint": profile.fingerprint,
                "publicKey": profile.realityPublicKey,
                "shortId": profile.realityShortID,
                "spiderX": profile.realitySpiderX,
            ]
        case .none:
            break
        }
        outbound["streamSettings"] = stream
        return try prettyJSON(outbound)
    }

    private static func trojanServerConfiguration(for profile: XrayServerProfile) throws -> Data {
        var outbound: [String: Any] = [
            "tag": "proxy",
            "protocol": "trojan",
            "settings": [
                "servers": [
                    [
                        "address": profile.serverAddress,
                        "port": profile.serverPort,
                        "password": profile.userID,
                    ]
                ]
            ],
        ]
        var stream: [String: Any] = [
            "network": profile.transport.rawValue,
            "security": profile.security.rawValue,
        ]
        if profile.transport == .websocket {
            stream["wsSettings"] = [
                "path": profile.path.isEmpty ? "/" : profile.path,
                "headers": profile.host.isEmpty ? [:] : ["Host": profile.host],
            ]
        } else if profile.transport == .grpc {
            stream["grpcSettings"] = ["serviceName": profile.serviceName]
        }
        if profile.security == .tls {
            stream["tlsSettings"] = [
                "serverName": profile.serverName,
                "allowInsecure": profile.allowInsecure,
                "fingerprint": profile.fingerprint,
            ]
        }
        outbound["streamSettings"] = stream
        return try prettyJSON(outbound)
    }

    private static func shadowsocksServerConfiguration(for profile: XrayServerProfile) throws -> Data {
        let outbound: [String: Any] = [
            "tag": "proxy",
            "protocol": "shadowsocks",
            "settings": [
                "servers": [
                    [
                        "address": profile.serverAddress,
                        "port": profile.serverPort,
                        "method": profile.encryption,
                        "password": profile.userID,
                    ]
                ]
            ],
        ]
        return try prettyJSON(outbound)
    }

    private static func composeTemplate(
        proxyOutbound: [String: Any]?,
        local: LocalProxyConfiguration
    ) throws -> Data {
        let local = try local.validated()
        var outbounds: [[String: Any]] = []
        if let proxyOutbound {
            outbounds.append(proxyOutbound)
        }
        outbounds.append(["tag": "direct", "protocol": "freedom"])
        outbounds.append(["tag": "block", "protocol": "blackhole"])
        var object: [String: Any] = [
            "log": ["loglevel": local.logLevel.rawValue],
            "inbounds": [inboundObject(for: local)],
            "outbounds": outbounds,
        ]
        if let routing = routingObject(for: local) {
            object["routing"] = routing
        }
        return try prettyJSON(object)
    }

    private static func routingObject(for local: LocalProxyConfiguration) -> [String: Any]? {
        switch local.routingMode {
        case .rule:
            guard local.bypassPrivateNetworks else { return nil }
            return [
                "domainStrategy": "AsIs",
                "rules": [privateNetworkDirectRule],
            ]
        case .global, .direct:
            return [
                "domainStrategy": "AsIs",
                "rules": [catchAllRule(for: local.routingMode)],
            ]
        }
    }

    private static var privateNetworkDirectRule: [String: Any] {
        [
            "type": "field",
            "ip": ["geoip:private"],
            "outboundTag": "direct",
        ]
    }

    private static func catchAllRule(for mode: ProxyRoutingMode) -> [String: Any] {
        [
            "type": "field",
            "network": "tcp,udp",
            "outboundTag": mode == .direct ? "direct" : "proxy",
        ]
    }

    private static func isPrivateNetworkDirectRule(_ rule: [String: Any]) -> Bool {
        let ip = rule["ip"] as? [String] ?? []
        return ip.contains("geoip:private") && rule["outboundTag"] as? String == "direct"
    }

    private static func isCatchAllRule(_ rule: [String: Any], outboundTag: String) -> Bool {
        guard rule["outboundTag"] as? String == outboundTag else { return false }
        guard rule["type"] as? String == "field" else { return false }
        guard let network = rule["network"] as? String else { return false }
        let networks = Set(
            network.split(separator: ",").map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            })
        guard networks.contains("tcp") && networks.contains("udp") else { return false }
        // A rule with another matcher is not the mode marker; it may be a
        // legitimate user rule that happens to use both transports.
        let matchKeys = Set(rule.keys).subtracting(["type", "network", "outboundTag"])
        return matchKeys.isEmpty
    }

    private static func isManagedRoutingRule(_ rule: [String: Any]) -> Bool {
        isPrivateNetworkDirectRule(rule)
            || isCatchAllRule(rule, outboundTag: "proxy")
            || isCatchAllRule(rule, outboundTag: "direct")
    }

    private static func inferredRoutingMode(
        in object: [String: Any],
        rules: [[String: Any]]
    ) -> ProxyRoutingMode {
        if rules.contains(where: { isCatchAllRule($0, outboundTag: "direct") }) {
            return .direct
        }
        if rules.contains(where: { isCatchAllRule($0, outboundTag: "proxy") }) {
            return .global
        }
        let outbounds = object["outbounds"] as? [[String: Any]] ?? []
        let hasProxy = outbounds.contains { $0["tag"] as? String == "proxy" }
        if !hasProxy,
            outbounds.contains(where: { $0["tag"] as? String == "direct" })
        {
            return .direct
        }
        return .rule
    }

    private static func inboundObject(for local: LocalProxyConfiguration) -> [String: Any] {
        var inbound: [String: Any] = [
            "tag": "mixed-in",
            "listen": local.listenAddress,
            "port": local.port,
            "protocol": "mixed",
            "settings": ["auth": "noauth", "udp": local.udpEnabled],
        ]
        if local.sniffingEnabled {
            inbound["sniffing"] = [
                "enabled": true,
                "destOverride": ["http", "tls", "quic"],
            ]
        }
        return inbound
    }

    private static func proxyOutbound(from object: [String: Any]) throws -> [String: Any] {
        if let outbounds = object["outbounds"] as? [[String: Any]],
            let proxy = outbounds.first(where: { $0["tag"] as? String == "proxy" })
        {
            return proxy
        }
        if let outbound = object["outbound"] as? [String: Any] { return outbound }
        if object["tag"] as? String == "proxy" || object["protocol"] != nil { return object }
        throw ConfigTemplateError.missingProxyOutbound
    }

    private static func replacingAddress(
        in outbound: [String: Any],
        with address: String
    ) throws -> [String: Any] {
        var outbound = outbound
        guard var settings = outbound["settings"] as? [String: Any] else {
            throw ConfigTemplateError.missingVnext
        }
        let normalizedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if var vnext = settings["vnext"] as? [[String: Any]], !vnext.isEmpty {
            vnext[0]["address"] = normalizedAddress
            settings["vnext"] = vnext
        } else if var servers = settings["servers"] as? [[String: Any]], !servers.isEmpty {
            servers[0]["address"] = normalizedAddress
            settings["servers"] = servers
        } else {
            throw ConfigTemplateError.missingVnext
        }
        outbound["settings"] = settings
        return outbound
    }

    private static func configurationDictionary(from data: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any]
        else { throw ConfigTemplateError.invalidJSON }
        return dictionary
    }

    private static func prettyJSON(_ object: Any) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw ConfigTemplateError.invalidJSON
        }
        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }
}
