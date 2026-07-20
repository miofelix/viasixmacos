import Foundation

public struct MihomoProxyProfile: Equatable, Sendable {
    public var name: String
    public var protocolName: MihomoProxyProtocol
    public var serverAddress: String
    public var serverPort: Int
    public var credential: String
    public var encryption: String
    public var flow: String
    public var alterID: Int
    public var vmessCipher: String
    public var transport: MihomoTransport
    public var security: MihomoTransportSecurity
    public var serverName: String
    public var host: String
    public var path: String
    public var serviceName: String
    public var allowInsecure: Bool
    public var fingerprint: String
    public var realityPublicKey: String
    public var realityShortID: String
    public var udpEnabled: Bool

    public init(
        name: String = "ViaSix Proxy",
        protocolName: MihomoProxyProtocol = .vless,
        serverAddress: String = "2001:db8::1",
        serverPort: Int = 443,
        credential: String = "",
        encryption: String = "none",
        flow: String = "",
        alterID: Int = 0,
        vmessCipher: String = "auto",
        transport: MihomoTransport = .websocket,
        security: MihomoTransportSecurity = .tls,
        serverName: String = "",
        host: String = "",
        path: String = "/",
        serviceName: String = "",
        allowInsecure: Bool = false,
        fingerprint: String = "chrome",
        realityPublicKey: String = "",
        realityShortID: String = "",
        udpEnabled: Bool = true
    ) {
        self.name = name
        self.protocolName = protocolName
        self.serverAddress = serverAddress
        self.serverPort = serverPort
        self.credential = credential
        self.encryption = encryption
        self.flow = flow
        self.alterID = alterID
        self.vmessCipher = vmessCipher
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
        self.udpEnabled = udpEnabled
    }

    public func validated() throws -> Self {
        var copy = self
        copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.serverAddress = copy.serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.credential = copy.credential.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.encryption = copy.encryption.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.flow = copy.flow.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.vmessCipher = copy.vmessCipher.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.serverName = copy.serverName.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.host = copy.host.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.path = copy.path.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.serviceName = copy.serviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.fingerprint = copy.fingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.realityPublicKey = copy.realityPublicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.realityShortID = copy.realityShortID.trimmingCharacters(in: .whitespacesAndNewlines)

        if copy.name.isEmpty { copy.name = "ViaSix Proxy" }
        if copy.protocolName == .vless, copy.encryption.isEmpty {
            copy.encryption = "none"
        }
        if copy.protocolName == .shadowsocks {
            copy.transport = .tcp
            copy.security = .none
        }
        guard (1...65_535).contains(copy.serverPort) else {
            throw MihomoConfigurationError.invalidServerPort
        }
        guard !copy.serverAddress.isEmpty else {
            throw MihomoConfigurationError.invalidProxy("缺少服务器地址")
        }
        guard !copy.credential.isEmpty,
            copy.credential != MihomoServerConfiguration.placeholderCredential
        else {
            throw MihomoConfigurationError.missingCredential
        }
        if copy.security != .none,
            copy.serverName.isEmpty
                || copy.serverName == MihomoServerConfiguration.placeholderServerName
        {
            throw MihomoConfigurationError.missingServerName
        }
        if copy.security == .reality, copy.realityPublicKey.isEmpty {
            throw MihomoConfigurationError.missingRealityPublicKey
        }
        if copy.transport == .websocket {
            if copy.path.isEmpty { copy.path = "/" }
            if copy.host.isEmpty { copy.host = copy.serverName }
        }
        return copy
    }

    public init(configuration data: Data) throws {
        let configuration = try MihomoServerConfiguration(data: data)
        self = try configuration.primaryProfile()
    }

    public func serverConfiguration() throws -> MihomoServerConfiguration {
        try MihomoServerConfiguration(profile: self)
    }
}

extension MihomoProxyProfile {
    init(mapping: [String: Any]) throws {
        guard let rawType = mapping.string("type")?.lowercased(),
            let protocolName = MihomoProxyProtocol(rawValue: rawType)
        else {
            throw MihomoConfigurationError.unsupportedProtocol(
                mapping.string("type") ?? "unknown"
            )
        }
        guard let server = mapping.string("server"), !server.isEmpty,
            let port = mapping.int("port")
        else {
            throw MihomoConfigurationError.invalidProxy("缺少 server 或 port")
        }

        let credential: String
        switch protocolName {
        case .vless, .vmess:
            credential = mapping.string("uuid") ?? ""
        case .trojan, .shadowsocks:
            credential = mapping.string("password") ?? ""
        }

        let reality = mapping.mapping("reality-opts")
        let tlsEnabled = mapping.bool("tls") ?? false
        let security: MihomoTransportSecurity
        if reality != nil {
            security = .reality
        } else if protocolName == .trojan || tlsEnabled {
            // TLS is intrinsic to Mihomo's Trojan outbound and therefore is
            // normally not represented by a separate `tls` key.
            security = .tls
        } else {
            security = .none
        }
        let network = mapping.string("network")?.lowercased() ?? "tcp"
        guard let transport = MihomoTransport(rawValue: network) else {
            throw MihomoConfigurationError.invalidProxy("不支持的传输方式：\(network)")
        }
        let webSocket = mapping.mapping("ws-opts") ?? [:]
        let headers = webSocket.mapping("headers") ?? [:]
        let grpc = mapping.mapping("grpc-opts") ?? [:]
        let http = mapping.mapping("http-opts") ?? [:]
        let httpHeaders = http.mapping("headers") ?? [:]
        let h2 = mapping.mapping("h2-opts") ?? [:]

        let host: String
        let path: String
        switch transport {
        case .websocket:
            host = Self.firstString(headers["Host"] ?? headers["host"]) ?? ""
            path = webSocket.string("path") ?? "/"
        case .grpc:
            host = ""
            path = "/"
        case .http:
            host = Self.firstString(httpHeaders["Host"] ?? httpHeaders["host"]) ?? ""
            path = Self.firstString(http["path"]) ?? "/"
        case .h2:
            host = Self.firstString(h2["host"]) ?? ""
            path = h2.string("path") ?? "/"
        case .tcp:
            host = ""
            path = "/"
        }

        let encryption: String
        switch protocolName {
        case .vless:
            encryption = mapping.string("encryption") ?? "none"
        case .shadowsocks:
            encryption = mapping.string("cipher") ?? ""
        case .vmess, .trojan:
            encryption = "none"
        }

        self.init(
            name: mapping.string("name") ?? protocolName.displayName,
            protocolName: protocolName,
            serverAddress: server,
            serverPort: port,
            credential: credential,
            encryption: encryption,
            flow: mapping.string("flow") ?? "",
            alterID: mapping.int("alterId") ?? mapping.int("alter-id") ?? 0,
            vmessCipher: mapping.string("cipher") ?? "auto",
            transport: transport,
            security: security,
            serverName: mapping.string("servername") ?? mapping.string("sni") ?? "",
            host: host,
            path: path,
            serviceName: grpc.string("grpc-service-name") ?? "",
            allowInsecure: mapping.bool("skip-cert-verify") ?? false,
            fingerprint: mapping.string("client-fingerprint") ?? "chrome",
            realityPublicKey: reality?.string("public-key") ?? "",
            realityShortID: reality?.string("short-id") ?? "",
            udpEnabled: mapping.bool("udp") ?? true
        )
    }

    func mapping() throws -> [String: Any] {
        let profile = try validated()
        var proxy: [String: Any] = [
            "name": profile.name,
            "type": profile.protocolName.rawValue,
            "server": profile.serverAddress,
            "port": profile.serverPort,
            "udp": profile.udpEnabled,
        ]

        switch profile.protocolName {
        case .vless:
            proxy["uuid"] = profile.credential
            proxy["encryption"] = profile.encryption
            if !profile.flow.isEmpty { proxy["flow"] = profile.flow }
        case .vmess:
            proxy["uuid"] = profile.credential
            proxy["alterId"] = profile.alterID
            proxy["cipher"] = profile.vmessCipher.isEmpty ? "auto" : profile.vmessCipher
        case .trojan:
            proxy["password"] = profile.credential
        case .shadowsocks:
            proxy["password"] = profile.credential
            proxy["cipher"] = profile.encryption
        }

        guard profile.protocolName != .shadowsocks else { return proxy }

        proxy["network"] = profile.transport.rawValue
        if profile.protocolName != .trojan {
            proxy["tls"] = profile.security != .none
        }
        if profile.security != .none {
            if profile.protocolName == .trojan {
                proxy["sni"] = profile.serverName
            } else {
                proxy["servername"] = profile.serverName
            }
            proxy["skip-cert-verify"] = profile.allowInsecure
            if !profile.fingerprint.isEmpty {
                proxy["client-fingerprint"] = profile.fingerprint
            }
        }
        if profile.security == .reality {
            proxy["reality-opts"] = [
                "public-key": profile.realityPublicKey,
                "short-id": profile.realityShortID,
            ]
        }
        switch profile.transport {
        case .websocket:
            var webSocket: [String: Any] = ["path": profile.path]
            if !profile.host.isEmpty {
                webSocket["headers"] = ["Host": profile.host]
            }
            proxy["ws-opts"] = webSocket
        case .grpc:
            proxy["grpc-opts"] = ["grpc-service-name": profile.serviceName]
        case .http:
            var options: [String: Any] = [
                "method": "GET",
                "path": [profile.path],
            ]
            if !profile.host.isEmpty {
                options["headers"] = ["Host": [profile.host]]
            }
            proxy["http-opts"] = options
        case .h2:
            var options: [String: Any] = ["path": profile.path]
            if !profile.host.isEmpty {
                options["host"] = [profile.host]
            }
            proxy["h2-opts"] = options
        case .tcp:
            break
        }
        return proxy
    }

    private static func firstString(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let values = value as? [String] { return values.first }
        if let values = value as? [Any] { return values.first as? String }
        return nil
    }
}
