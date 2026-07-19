import Foundation

public actor AppBootstrapper {
    public let paths: AppPaths

    public init(paths: AppPaths = .live()) {
        self.paths = paths
    }

    public func prepareDefaults() throws {
        try DefaultResourceInstaller.install(into: paths)
        try removeStaleSpeedTestResults()
    }

    /// Removes only temporary result files created by an interrupted speed
    /// test. The data directory is application-owned, but names are still
    /// matched strictly so the persistent result and user files are never
    /// mistaken for cleanup artifacts.
    private func removeStaleSpeedTestResults() throws {
        let fileManager = FileManager.default
        let temporaryNames = try fileManager.contentsOfDirectory(
            at: paths.data,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: []
        )

        for fileURL in temporaryNames {
            guard Self.isTemporarySpeedTestResultName(fileURL.lastPathComponent) else {
                continue
            }

            let resourceValues = try fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard resourceValues.isRegularFile == true || resourceValues.isSymbolicLink == true else {
                continue
            }
            try fileManager.removeItem(at: fileURL)
        }
    }

    private static func isTemporarySpeedTestResultName(_ name: String) -> Bool {
        if uuidBetween(
            name,
            prefix: ".result.csv.",
            suffix: ".tmp"
        ) != nil {
            return true
        }

        if uuidBetween(
            name,
            prefix: ".current-test-",
            suffix: ".csv"
        ) != nil {
            return true
        }

        // CfstRunner adds one more leading dot and a temporary UUID when the
        // current-node test supplies `.current-test-<UUID>.csv` as its result
        // URL. Keep this pattern explicit instead of deleting arbitrary dot
        // files ending in `.tmp`.
        let currentTestPrefix = "..current-test-"
        let currentTestSuffix = ".tmp"
        guard name.hasPrefix(currentTestPrefix), name.hasSuffix(currentTestSuffix) else {
            return false
        }
        let body = name.dropFirst(currentTestPrefix.count)
            .dropLast(currentTestSuffix.count)
        guard let separator = body.range(of: ".csv.") else { return false }
        let runID = String(body[..<separator.lowerBound])
        let temporaryID = String(body[separator.upperBound...])
        return UUID(uuidString: runID) != nil && UUID(uuidString: temporaryID) != nil
    }

    private static func uuidBetween(
        _ name: String,
        prefix: String,
        suffix: String
    ) -> UUID? {
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return nil }
        let start = name.index(name.startIndex, offsetBy: prefix.count)
        let end = name.index(name.endIndex, offsetBy: -suffix.count)
        guard start <= end else { return nil }
        return UUID(uuidString: String(name[start..<end]))
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

    @discardableResult
    public func prepareConfigForLaunch(ip: String) throws -> ProxyEndpoint {
        let template = try Data(contentsOf: paths.templateConfig)
        let config = try ConfigTemplate.replacingAddress(in: template, with: ip)
        let endpoint = try ConfigTemplate.validateForLaunch(config)
        try config.write(to: paths.generatedConfig, options: .atomic)
        try FilePermissions.restrictFile(paths.generatedConfig)
        return endpoint
    }

    @discardableResult
    public func replaceTemplate(with data: Data, selectedIP: String? = nil) throws -> ProxyEndpoint {
        let endpoint = try ConfigTemplate.validateTemplate(data)
        let normalizedIP = selectedIP?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let validationIP = normalizedIP.isEmpty ? "2001:db8::2" : normalizedIP
        let generatedConfig = try ConfigTemplate.replacingAddress(in: data, with: validationIP)
        try ConfigTemplate.validateForLaunch(generatedConfig)

        try data.write(to: paths.templateConfig, options: .atomic)
        try FilePermissions.restrictFile(paths.templateConfig)
        if normalizedIP.isEmpty {
            if FileManager.default.fileExists(atPath: paths.generatedConfig.path) {
                try FileManager.default.removeItem(at: paths.generatedConfig)
            }
        } else {
            try generatedConfig.write(to: paths.generatedConfig, options: .atomic)
            try FilePermissions.restrictFile(paths.generatedConfig)
        }
        return endpoint
    }

    @discardableResult
    public func importTemplate(from sourceURL: URL, selectedIP: String? = nil) throws -> ProxyEndpoint {
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

    public func currentProxyEndpoint() throws -> ProxyEndpoint {
        try ConfigTemplate.proxyEndpoint(in: Data(contentsOf: paths.templateConfig))
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
