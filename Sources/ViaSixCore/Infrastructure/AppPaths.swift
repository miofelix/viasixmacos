import Foundation

public struct AppPaths: Sendable, Equatable {
    public let root: URL
    public let data: URL
    public let runtime: URL
    public let logs: URL
    public let preferences: URL
    public let resultCSV: URL
    public let templateConfig: URL
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
        self.generatedConfig = data.appendingPathComponent("config.json")
        self.ipv4List = data.appendingPathComponent("ip.txt")
        self.ipv6List = data.appendingPathComponent("ipv6.txt")
        self.cfstBinary = runtime.appendingPathComponent("cfst")
        self.xrayBinary = runtime.appendingPathComponent("xray")
    }

    public static func live(appName: String = "ViaSix") -> Self {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return Self(root: base.appendingPathComponent(appName, isDirectory: true))
    }

    public func prepare(using fileManager: FileManager = .default) throws {
        for directory in [root, data, runtime, logs] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}

