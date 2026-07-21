import Foundation

public struct AppPaths: Sendable, Equatable {
    public let root: URL
    public let data: URL
    public let runtime: URL
    public let logs: URL

    public let preferences: URL
    public let resultCSV: URL
    public let profileConfig: URL
    public let localProxyConfig: URL
    /// A crash-safe snapshot of the macOS proxy settings changed by ViaSix.
    public let systemProxySnapshot: URL

    /// Mihomo's private home. Runtime configuration and provider caches are
    /// deliberately kept away from the user-editable server profile.
    public let mihomoHome: URL
    public let generatedConfig: URL
    /// Random bearer token for the loopback-only Mihomo Controller API.
    public let mihomoControllerSecret: URL
    public let mihomoProviders: URL
    public let mihomoRules: URL

    public let ipv4List: URL
    public let ipv6List: URL
    public let cfstBinary: URL
    public let mihomoBinary: URL

    /// Read-only migration inputs left behind by Xray-based releases.
    public let legacyServerConfig: URL
    public let legacyTemplateConfig: URL
    public let legacyGeneratedConfig: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL
        self.data = self.root.appendingPathComponent("Data", isDirectory: true)
        self.runtime = self.root.appendingPathComponent("Runtime", isDirectory: true)
        self.logs = self.root.appendingPathComponent("Logs", isDirectory: true)

        self.preferences = data.appendingPathComponent("preferences.json")
        self.resultCSV = data.appendingPathComponent("result.csv")
        self.profileConfig = data.appendingPathComponent("profile.yaml")
        self.localProxyConfig = data.appendingPathComponent("local-proxy.json")
        self.systemProxySnapshot = data.appendingPathComponent("system-proxy.json")

        self.mihomoHome = data.appendingPathComponent("Mihomo", isDirectory: true)
        self.generatedConfig = mihomoHome.appendingPathComponent("config.yaml")
        self.mihomoControllerSecret = mihomoHome.appendingPathComponent("controller.secret")
        self.mihomoProviders = mihomoHome.appendingPathComponent("providers", isDirectory: true)
        self.mihomoRules = mihomoHome.appendingPathComponent("rules", isDirectory: true)

        self.ipv4List = data.appendingPathComponent("ip.txt")
        self.ipv6List = data.appendingPathComponent("ipv6.txt")
        self.cfstBinary = runtime.appendingPathComponent("cfst")
        self.mihomoBinary = runtime.appendingPathComponent("mihomo")

        self.legacyServerConfig = data.appendingPathComponent("server.json")
        self.legacyTemplateConfig = data.appendingPathComponent("template.json")
        self.legacyGeneratedConfig = data.appendingPathComponent("config.json")
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
        for directory in [
            root,
            data,
            runtime,
            logs,
            mihomoHome,
            mihomoProviders,
            mihomoRules,
        ] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try FilePermissions.restrictDirectory(directory, using: fileManager)
        }
    }
}
