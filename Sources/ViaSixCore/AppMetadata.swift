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
