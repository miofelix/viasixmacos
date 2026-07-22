import Foundation

public enum AppMetadata {
    public static let name = "ViaSix"
    public static let defaultExitIPEndpoint = "https://api.myip.la/cn?json"
    public static let ipv4ExitIPEndpoint = "https://api-ipv4.ip.sb/ip"
    public static let ipv6ExitIPEndpoint = "https://api-ipv6.ip.sb/ip"
    /// Lookup endpoint used to add location and network context to a detected IP.
    /// The service accepts both IPv4 and IPv6 literals in the path and returns
    /// city/region/postal information for addresses that do not expose it from
    /// the primary exit-IP endpoint.
    public static let exitIPGeolocationEndpoint = "https://ipwho.is?lang=zh-CN"
    public static let proxyHost = "127.0.0.1"
    public static let proxyPort = 11_451
    public static let controllerPort = 9_090
    public static let proxyDelayTestURL = "https://www.gstatic.com/generate_204"
    public static let proxyDelayTimeoutMilliseconds = 5_000
    public static let repositoryURL = URL(string: "https://github.com/miofelix/ViaSix")!
    public static let issuesURL = URL(string: "https://github.com/miofelix/ViaSix/issues")!
    public static let fallbackVersion = "1.0.0"

    /// Marketing version from the app bundle, with a package fallback for `swift run`.
    public static var shortVersion: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return value
        }
        return fallbackVersion
    }

    /// Build number when available.
    public static var buildNumber: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static var displayVersion: String {
        if let buildNumber, buildNumber != shortVersion {
            return "\(shortVersion) (\(buildNumber))"
        }
        return shortVersion
    }

    public static func exitIPEndpoint(
        for mode: ExitIPDetectionMode,
        automaticEndpoint: String
    ) -> String {
        switch mode {
        case .automatic: automaticEndpoint
        case .ipv4: ipv4ExitIPEndpoint
        case .ipv6: ipv6ExitIPEndpoint
        }
    }

    public static func exitIPGeolocationURL(for ip: String) -> URL? {
        URL(string: exitIPGeolocationEndpoint)?.appendingPathComponent(ip)
    }
}
