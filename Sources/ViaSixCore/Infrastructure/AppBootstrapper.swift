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

    public func prepareConfigForLaunch(ip: String) throws {
        let template = try Data(contentsOf: paths.templateConfig)
        let config = try ConfigTemplate.replacingAddress(in: template, with: ip)
        try ConfigTemplate.validateForLaunch(config)
        try config.write(to: paths.generatedConfig, options: .atomic)
    }

    public func replaceTemplate(with data: Data, selectedIP: String? = nil) throws {
        try ConfigTemplate.validateTemplate(data)
        let normalizedIP = selectedIP?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let validationIP = normalizedIP.isEmpty ? "2001:db8::2" : normalizedIP
        let generatedConfig = try ConfigTemplate.replacingAddress(in: data, with: validationIP)
        try ConfigTemplate.validateForLaunch(generatedConfig)

        try data.write(to: paths.templateConfig, options: .atomic)
        if normalizedIP.isEmpty {
            if FileManager.default.fileExists(atPath: paths.generatedConfig.path) {
                try FileManager.default.removeItem(at: paths.generatedConfig)
            }
        } else {
            try generatedConfig.write(to: paths.generatedConfig, options: .atomic)
        }
    }

    public func importTemplate(from sourceURL: URL, selectedIP: String? = nil) throws {
        try replaceTemplate(with: Data(contentsOf: sourceURL), selectedIP: selectedIP)
    }

    @discardableResult
    public func ensureConfig(ip: String) throws -> Bool {
        let normalizedIP = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIP.isEmpty else { return false }
        guard try currentConfigIP() != normalizedIP else { return false }
        try writeConfig(ip: normalizedIP)
        return true
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
