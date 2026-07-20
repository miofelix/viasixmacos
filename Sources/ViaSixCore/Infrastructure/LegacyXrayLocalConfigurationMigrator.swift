import Foundation

/// Reads only the local listener and routing preferences from a legacy Xray
/// document. It never produces an executable Xray configuration.
enum LegacyXrayLocalConfigurationMigrator {
    private static let maximumBytes = 8 * 1_024 * 1_024

    static func configuration(from data: Data) -> LocalProxyConfiguration? {
        guard data.count <= maximumBytes,
            let object = try? JSONSerialization.jsonObject(with: data),
            let root = object as? [String: Any],
            let inbounds = root["inbounds"] as? [[String: Any]],
            let inbound = inbounds.first(where: {
                ($0["protocol"] as? String)?.lowercased() == "mixed"
            })
        else { return nil }

        let listenAddress = inbound["listen"] as? String ?? AppMetadata.proxyHost
        let port = inbound["port"] as? Int ?? AppMetadata.proxyPort
        let settings = inbound["settings"] as? [String: Any]
        let sniffing = inbound["sniffing"] as? [String: Any]
        let rules = (root["routing"] as? [String: Any])?["rules"] as? [[String: Any]] ?? []
        let logLevel = migratedLogLevel(
            (root["log"] as? [String: Any])?["loglevel"] as? String
        )

        return try? LocalProxyConfiguration(
            listenAddress: listenAddress,
            port: port,
            udpEnabled: settings?["udp"] as? Bool ?? true,
            sniffingEnabled: sniffing?["enabled"] as? Bool ?? false,
            bypassPrivateNetworks: rules.contains(where: isPrivateNetworkDirectRule),
            logLevel: logLevel,
            routingMode: inferredRoutingMode(in: root, rules: rules)
        ).validated()
    }

    private static func migratedLogLevel(_ value: String?) -> ProxyLogLevel {
        let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized == "none" { return .silent }
        return normalized.flatMap(ProxyLogLevel.init(rawValue:)) ?? .warning
    }

    private static func inferredRoutingMode(
        in root: [String: Any],
        rules: [[String: Any]]
    ) -> ProxyRoutingMode {
        if rules.contains(where: { isCatchAllRule($0, outboundTag: "direct") }) {
            return .direct
        }
        if rules.contains(where: { isCatchAllRule($0, outboundTag: "proxy") }) {
            return .global
        }

        let outbounds = root["outbounds"] as? [[String: Any]] ?? []
        let hasProxy = outbounds.contains { $0["tag"] as? String == "proxy" }
        let hasDirect = outbounds.contains { $0["tag"] as? String == "direct" }
        return !hasProxy && hasDirect ? .direct : .rule
    }

    private static func isPrivateNetworkDirectRule(_ rule: [String: Any]) -> Bool {
        let addresses = rule["ip"] as? [String] ?? []
        return addresses.contains("geoip:private")
            && rule["outboundTag"] as? String == "direct"
    }

    private static func isCatchAllRule(
        _ rule: [String: Any],
        outboundTag: String
    ) -> Bool {
        guard rule["type"] as? String == "field",
            rule["outboundTag"] as? String == outboundTag,
            let network = rule["network"] as? String
        else { return false }

        let networks = Set(
            network.split(separator: ",").map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
        )
        guard networks.contains("tcp"), networks.contains("udp") else { return false }
        return Set(rule.keys).subtracting(["type", "network", "outboundTag"]).isEmpty
    }
}
