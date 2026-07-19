import Foundation

public actor AppBootstrapper {
    public let paths: AppPaths

    public init(paths: AppPaths = .live()) {
        self.paths = paths
    }

    public func prepareDefaults() throws {
        try DefaultResourceInstaller.install(into: paths)
    }

    public func loadResults() throws -> [SpeedTestResult] {
        guard FileManager.default.fileExists(atPath: paths.resultCSV.path) else {
            return []
        }
        return try SpeedTestResultParser.parse(data: Data(contentsOf: paths.resultCSV))
    }

    public func writeConfig(ip: String) throws {
        try ConfigTemplate.write(
            ip: ip,
            templateURL: paths.templateConfig,
            destinationURL: paths.generatedConfig
        )
    }

    public func currentConfigIP() throws -> String? {
        guard FileManager.default.fileExists(atPath: paths.generatedConfig.path) else {
            return nil
        }
        return ConfigTemplate.address(in: try Data(contentsOf: paths.generatedConfig))
    }

    public func resultForSelectedIP(_ selectedIP: String? = nil) throws -> SpeedTestResult? {
        let explicitIP = selectedIP?.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetIP: String?
        if let explicitIP, !explicitIP.isEmpty {
            targetIP = explicitIP
        } else {
            targetIP = try currentConfigIP()
        }

        guard let targetIP, !targetIP.isEmpty else {
            return nil
        }
        return try loadResults().first {
            $0.ip.trimmingCharacters(in: .whitespacesAndNewlines) == targetIP
        }
    }
}
