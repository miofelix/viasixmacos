import Foundation

public enum ConfigTemplateError: LocalizedError, Equatable, Sendable {
    case invalidJSON
    case missingOutbounds
    case missingVnext

    public var errorDescription: String? {
        switch self {
        case .invalidJSON: "Xray 模板不是有效 JSON"
        case .missingOutbounds: "Xray 模板缺少 outbounds"
        case .missingVnext: "Xray 模板缺少 outbounds[0].settings.vnext"
        }
    }
}

public enum ConfigTemplate {
    public static func replacingAddress(in template: Data, with ip: String) throws -> Data {
        guard var config = try JSONSerialization.jsonObject(with: template) as? [String: Any] else {
            throw ConfigTemplateError.invalidJSON
        }
        guard var outbounds = config["outbounds"] as? [[String: Any]], !outbounds.isEmpty else {
            throw ConfigTemplateError.missingOutbounds
        }
        let proxyIndex = outbounds.firstIndex { $0["tag"] as? String == "proxy" } ?? 0
        guard var settings = outbounds[proxyIndex]["settings"] as? [String: Any],
              var vnext = settings["vnext"] as? [[String: Any]], !vnext.isEmpty else {
            throw ConfigTemplateError.missingVnext
        }

        vnext[0]["address"] = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        settings["vnext"] = vnext
        outbounds[proxyIndex]["settings"] = settings
        config["outbounds"] = outbounds

        guard JSONSerialization.isValidJSONObject(config) else {
            throw ConfigTemplateError.invalidJSON
        }
        return try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
    }

    public static func write(
        ip: String,
        templateURL: URL,
        destinationURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let template = try Data(contentsOf: templateURL)
        let output = try replacingAddress(in: template, with: ip)
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try output.write(to: destinationURL, options: .atomic)
    }

    public static func address(in config: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: config),
              let dictionary = object as? [String: Any],
              let outbounds = dictionary["outbounds"] as? [[String: Any]],
              let proxy = outbounds.first(where: { $0["tag"] as? String == "proxy" }) ?? outbounds.first,
              let settings = proxy["settings"] as? [String: Any],
              let vnext = settings["vnext"] as? [[String: Any]],
              let address = vnext.first?["address"] as? String else {
            return nil
        }
        return address
    }
}
