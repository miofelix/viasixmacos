import Foundation

public struct AppPaths: Sendable, Equatable {
    public let root: URL
    public let data: URL
    public let runtime: URL
    public let logs: URL
    public let preferences: URL
    public let resultCSV: URL
    /// Compatibility mirror containing the complete generated Xray template.
    /// User-facing configuration is split between `serverConfig` and
    /// `localProxyConfig`; keeping this file lets older installations and
    /// advanced imports migrate without losing information.
    public let templateConfig: URL
    public let serverConfig: URL
    public let localProxyConfig: URL
    /// A crash-safe snapshot of the macOS proxy settings changed by ViaSix.
    public let systemProxySnapshot: URL
    public let generatedConfig: URL
    public let ipv4List: URL
    public let ipv6List: URL
    public let cfstBinary: URL
    public let xrayBinary: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL
        self.data = root.appendingPathComponent("Data", isDirectory: true)
        self.runtime = root.appendingPathComponent("Runtime", isDirectory: true)
        self.logs = root.appendingPathComponent("Logs", isDirectory: true)
        self.preferences = data.appendingPathComponent("preferences.json")
        self.resultCSV = data.appendingPathComponent("result.csv")
        self.templateConfig = data.appendingPathComponent("template.json")
        self.serverConfig = data.appendingPathComponent("server.json")
        self.localProxyConfig = data.appendingPathComponent("local-proxy.json")
        self.systemProxySnapshot = data.appendingPathComponent("system-proxy.json")
        self.generatedConfig = data.appendingPathComponent("config.json")
        self.ipv4List = data.appendingPathComponent("ip.txt")
        self.ipv6List = data.appendingPathComponent("ipv6.txt")
        self.cfstBinary = runtime.appendingPathComponent("cfst")
        self.xrayBinary = runtime.appendingPathComponent("xray")
    }

    public static func live(appName: String = "ViaSix") -> Self {
        let fileManager = FileManager.default
        let base =
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return Self(root: base.appendingPathComponent(appName, isDirectory: true))
    }

    public func prepare(using fileManager: FileManager = .default) throws {
        for directory in [root, data, runtime, logs] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try FilePermissions.restrictDirectory(directory, using: fileManager)
        }
    }
}
