import Foundation

public enum AppBootstrapperError: LocalizedError, Equatable, Sendable {
    case configurationRollbackFailed(original: String, rollback: String)
    case configurationRecoveryFailed(String)
    case invalidConfigurationFile(URL)
    case templateChangedExternally

    public var errorDescription: String? {
        switch self {
        case .configurationRollbackFailed(let original, let rollback):
            "代理配置更新失败，恢复旧配置时也发生错误。原始错误：\(original)；恢复错误：\(rollback)"
        case .configurationRecoveryFailed(let message):
            "上次代理配置更新未完成，自动恢复失败：\(message)"
        case .invalidConfigurationFile(let url):
            "代理配置路径不是普通文件：\(url.path)"
        case .templateChangedExternally:
            "代理配置在编辑期间发生变化，请重新载入后再保存"
        }
    }
}

public struct BootstrapConfiguration: Equatable, Sendable {
    public let endpoint: ProxyEndpoint
    public let local: LocalProxyConfiguration
    public let effectiveIP: String?
    public let launchIssue: ConfigTemplateError?

    public init(
        endpoint: ProxyEndpoint,
        local: LocalProxyConfiguration = .default,
        effectiveIP: String?,
        launchIssue: ConfigTemplateError?
    ) {
        self.endpoint = endpoint
        self.local = local
        self.effectiveIP = effectiveIP
        self.launchIssue = launchIssue
    }
}

typealias ConfigurationFileWriter = @Sendable (Data, URL) throws -> Void

public actor AppBootstrapper {
    public let paths: AppPaths
    private let configurationFileWriter: ConfigurationFileWriter

    public init(paths: AppPaths = .live()) {
        self.paths = paths
        self.configurationFileWriter = { data, url in
            try Self.writeRestrictedConfigurationFile(data, to: url)
        }
    }

    init(
        paths: AppPaths,
        configurationFileWriter: @escaping ConfigurationFileWriter
    ) {
        self.paths = paths
        self.configurationFileWriter = configurationFileWriter
    }

    public func prepareDefaults() throws {
        try paths.prepare()
        try recoverPendingConfigurationTransaction()
        try migrateLegacySplitConfigurationIfNeeded()
        try DefaultResourceInstaller.install(into: paths)
        try migrateLegacySplitConfigurationIfNeeded()
        try removeStaleSpeedTestResults()
    }

    /// Older releases stored server and local settings together in
    /// template.json. Split that document once while retaining it as an
    /// internal compatibility mirror for advanced imports.
    private func migrateLegacySplitConfigurationIfNeeded() throws {
        let fileManager = FileManager.default
        let legacy = try Self.regularFileDataIfPresent(at: paths.templateConfig, using: fileManager)
        let server = try Self.regularFileDataIfPresent(at: paths.serverConfig, using: fileManager)
        let local = try Self.regularFileDataIfPresent(at: paths.localProxyConfig, using: fileManager)

        if let legacy {
            if server == nil {
                try Self.writeRestrictedConfigurationFile(
                    ConfigTemplate.serverConfiguration(from: legacy),
                    to: paths.serverConfig
                )
            }
            if local == nil, let extracted = try ConfigTemplate.localConfiguration(from: legacy) {
                try Self.writeRestrictedConfigurationFile(
                    JSONEncoder.pretty.encode(extracted),
                    to: paths.localProxyConfig
                )
            }
        }

        if let server,
            let extracted = try? ConfigTemplate.serverConfiguration(from: server),
            server != extracted
        {
            try Self.writeRestrictedConfigurationFile(extracted, to: paths.serverConfig)
        }
        if local == nil {
            try Self.writeRestrictedConfigurationFile(
                JSONEncoder.pretty.encode(LocalProxyConfiguration.default),
                to: paths.localProxyConfig
            )
        } else {
            _ = try loadLocalProxyConfiguration()
        }
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
        let template = try requiredConfigurationFileData(at: paths.templateConfig)
        let config = try ConfigTemplate.replacingAddress(in: template, with: ip)
        try replaceSingleConfigurationFile(config, at: paths.generatedConfig)
    }

    @discardableResult
    public func prepareConfigForLaunch(ip: String) throws -> ProxyEndpoint {
        let template = try requiredConfigurationFileData(at: paths.templateConfig)
        let config = try ConfigTemplate.replacingAddress(in: template, with: ip)
        let endpoint = try ConfigTemplate.validateForLaunch(config)
        try replaceSingleConfigurationFile(config, at: paths.generatedConfig)
        return endpoint
    }

    /// Validates whether the stored template can be launched without changing
    /// the generated runtime configuration. A documentation-only IP is used
    /// until the user has selected a node so placeholder credentials are still
    /// detected during bootstrap.
    @discardableResult
    public func validateTemplateForLaunch(selectedIP: String? = nil) throws -> ProxyEndpoint {
        let template = try requiredConfigurationFileData(at: paths.templateConfig)
        let normalizedIP = selectedIP?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let validationIP = normalizedIP.isEmpty ? "2001:db8::2" : normalizedIP
        let config = try ConfigTemplate.replacingAddress(in: template, with: validationIP)
        return try ConfigTemplate.validateForLaunch(config)
    }

    @discardableResult
    public func replaceTemplate(with data: Data, selectedIP: String? = nil) throws -> ProxyEndpoint {
        try replaceTemplateTransaction(
            with: data,
            selectedIP: selectedIP,
            expectedTemplateData: nil
        )
    }

    @discardableResult
    public func replaceTemplateIfUnchanged(
        with data: Data,
        selectedIP: String?,
        expectedTemplateData: Data?
    ) throws -> ProxyEndpoint {
        try replaceTemplateTransaction(
            with: data,
            selectedIP: selectedIP,
            expectedTemplateData: expectedTemplateData
        )
    }

    private func replaceTemplateTransaction(
        with data: Data,
        selectedIP: String?,
        expectedTemplateData: Data?
    ) throws -> ProxyEndpoint {
        let endpoint = try ConfigTemplate.validateTemplate(data)
        let normalizedIP = selectedIP?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let validationIP = normalizedIP.isEmpty ? "2001:db8::2" : normalizedIP
        let generatedConfig = try ConfigTemplate.replacingAddress(in: data, with: validationIP)
        try ConfigTemplate.validateForLaunch(generatedConfig)

        try commitConfiguration(
            template: data,
            generated: normalizedIP.isEmpty ? nil : generatedConfig,
            expectedTemplateData: expectedTemplateData
        )
        try synchronizeSplitFiles(from: data)
        return endpoint
    }

    @discardableResult
    public func importTemplate(from sourceURL: URL, selectedIP: String? = nil) throws -> ProxyEndpoint {
        try replaceTemplate(with: Data(contentsOf: sourceURL), selectedIP: selectedIP)
    }

    public func loadServerConfiguration() throws -> Data {
        try ConfigTemplate.serverConfiguration(
            from: requiredConfigurationFileData(at: paths.serverConfig)
        )
    }

    public func loadLocalProxyConfiguration() throws -> LocalProxyConfiguration {
        let data = try requiredConfigurationFileData(at: paths.localProxyConfig)
        return try JSONDecoder().decode(LocalProxyConfiguration.self, from: data).validated()
    }

    @discardableResult
    public func replaceServerConfiguration(
        with data: Data,
        selectedIP: String? = nil
    ) throws -> ProxyEndpoint {
        let server = try ConfigTemplate.serverConfiguration(from: data)
        let previousServer = try? loadServerConfiguration()
        let currentTemplate = try requiredConfigurationFileData(at: paths.templateConfig)
        let updatedTemplate = try ConfigTemplate.updatingServerConfiguration(
            in: currentTemplate,
            with: server
        )
        let result = try commitSplitConfiguration(
            template: updatedTemplate,
            selectedIP: selectedIP
        )
        do {
            try Self.writeRestrictedConfigurationFile(server, to: paths.serverConfig)
        } catch {
            if let previousServer {
                try? Self.writeRestrictedConfigurationFile(previousServer, to: paths.serverConfig)
            }
            throw error
        }
        return result
    }

    @discardableResult
    public func replaceLocalProxyConfiguration(
        with local: LocalProxyConfiguration,
        selectedIP: String? = nil
    ) throws -> ProxyEndpoint {
        let local = try local.validated()
        let previousLocal = try? loadLocalProxyConfiguration()
        let currentTemplate = try requiredConfigurationFileData(at: paths.templateConfig)
        let updatedTemplate = try ConfigTemplate.updatingLocalConfiguration(
            in: currentTemplate,
            with: local
        )
        let result = try commitSplitConfiguration(
            template: updatedTemplate,
            selectedIP: selectedIP
        )
        do {
            try Self.writeRestrictedConfigurationFile(
                JSONEncoder.pretty.encode(local),
                to: paths.localProxyConfig
            )
        } catch {
            if let previousLocal {
                try? Self.writeRestrictedConfigurationFile(
                    JSONEncoder.pretty.encode(previousLocal),
                    to: paths.localProxyConfig
                )
            }
            throw error
        }
        return result
    }

    private func commitSplitConfiguration(
        template: Data,
        selectedIP: String?
    ) throws -> ProxyEndpoint {
        let normalizedIP = selectedIP?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let validationIP = normalizedIP.isEmpty ? "2001:db8::2" : normalizedIP
        let validatedConfig = try ConfigTemplate.replacingAddress(in: template, with: validationIP)
        let endpoint = try ConfigTemplate.validateForLaunch(validatedConfig)
        try commitConfiguration(
            template: template,
            generated: normalizedIP.isEmpty ? nil : validatedConfig,
            expectedTemplateData: nil
        )
        return endpoint
    }

    private func synchronizeSplitFiles(from template: Data) throws {
        try Self.writeRestrictedConfigurationFile(
            ConfigTemplate.serverConfiguration(from: template),
            to: paths.serverConfig
        )
        if let local = try ConfigTemplate.localConfiguration(from: template) {
            try Self.writeRestrictedConfigurationFile(
                JSONEncoder.pretty.encode(local),
                to: paths.localProxyConfig
            )
        }
    }

    @discardableResult
    public func ensureConfig(ip: String) throws -> Bool {
        let normalizedIP = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIP.isEmpty else { return false }
        let template = try requiredConfigurationFileData(at: paths.templateConfig)
        let expectedConfig = try ConfigTemplate.replacingAddress(in: template, with: normalizedIP)
        if try configurationFileMatches(expectedConfig, at: paths.generatedConfig) {
            return false
        }
        try replaceSingleConfigurationFile(expectedConfig, at: paths.generatedConfig)
        return true
    }

    public func synchronizeConfiguration(selectedIP: String?) throws -> BootstrapConfiguration {
        try migrateLegacySplitConfigurationIfNeeded()
        let template = try requiredConfigurationFileData(at: paths.templateConfig)
        let local = try loadLocalProxyConfiguration()
        let endpoint = try ConfigTemplate.validateTemplate(template)
        let generatedData = try regularFileDataIfPresent(at: paths.generatedConfig)
        let configuredIP = generatedData.flatMap { ConfigTemplate.address(in: $0) }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedIP = selectedIP?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let effectiveIP = configuredIP?.isEmpty == false ? configuredIP : (selectedIP.isEmpty ? nil : selectedIP)
        let validationIP = effectiveIP ?? "2001:db8::2"
        let expectedConfig = try ConfigTemplate.replacingAddress(in: template, with: validationIP)
        let launchIssue: ConfigTemplateError?
        do {
            _ = try ConfigTemplate.validateForLaunch(expectedConfig)
            launchIssue = nil
        } catch let error as ConfigTemplateError {
            guard error == .connectionNotConfigured else { throw error }
            launchIssue = error
        }

        if effectiveIP != nil,
            try !configurationFileMatches(expectedConfig, at: paths.generatedConfig)
        {
            try replaceSingleConfigurationFile(expectedConfig, at: paths.generatedConfig)
        }
        return BootstrapConfiguration(
            endpoint: endpoint,
            local: local,
            effectiveIP: effectiveIP,
            launchIssue: launchIssue
        )
    }

    private func commitConfiguration(
        template: Data,
        generated: Data?,
        expectedTemplateData: Data?
    ) throws {
        let fileManager = FileManager.default
        try recoverPendingConfigurationTransaction()
        let transaction = ConfigurationTransactionPaths(root: configurationTransactionDirectory)
        try fileManager.createDirectory(
            at: transaction.root,
            withIntermediateDirectories: false
        )
        try FilePermissions.restrictDirectory(transaction.root, using: fileManager)
        var keepTransactionForRecovery = false
        defer {
            if !keepTransactionForRecovery {
                try? fileManager.removeItem(at: transaction.root)
            }
        }

        try configurationFileWriter(template, transaction.stagedTemplate)
        try Self.validateAndRestrictStagedFile(transaction.stagedTemplate, using: fileManager)
        if let generated {
            try configurationFileWriter(generated, transaction.stagedGenerated)
            try Self.validateAndRestrictStagedFile(transaction.stagedGenerated, using: fileManager)
        }

        let templateSnapshot = try ConfigurationFileSnapshot.capture(
            paths.templateConfig,
            backupURL: transaction.templateBackup,
            using: fileManager
        )
        let generatedSnapshot = try ConfigurationFileSnapshot.capture(
            paths.generatedConfig,
            backupURL: transaction.generatedBackup,
            using: fileManager
        )
        if let expectedTemplateData, templateSnapshot.data != expectedTemplateData {
            throw AppBootstrapperError.templateChangedExternally
        }

        let preparedManifest = ConfigurationTransactionManifest(
            state: .prepared,
            templateExisted: templateSnapshot.existed,
            generatedExisted: generatedSnapshot.existed
        )
        try Self.writeTransactionManifest(preparedManifest, to: transaction.manifest)
        try templateSnapshot.assertUnchanged(at: paths.templateConfig, using: fileManager)
        try generatedSnapshot.assertUnchanged(at: paths.generatedConfig, using: fileManager)

        do {
            if generated != nil {
                try Self.publishStagedFile(
                    transaction.stagedGenerated,
                    to: paths.generatedConfig,
                    using: fileManager
                )
            } else {
                try Self.removeRegularFileIfPresent(paths.generatedConfig, using: fileManager)
            }
            try Self.publishStagedFile(
                transaction.stagedTemplate,
                to: paths.templateConfig,
                using: fileManager
            )
            let committedManifest = ConfigurationTransactionManifest(
                state: .committed,
                templateExisted: templateSnapshot.existed,
                generatedExisted: generatedSnapshot.existed
            )
            try Self.writeTransactionManifest(committedManifest, to: transaction.manifest)
        } catch {
            let originalError = error
            let rollbackErrors = rollbackConfiguration(
                templateSnapshot: templateSnapshot,
                generatedSnapshot: generatedSnapshot,
                using: fileManager
            )
            if !rollbackErrors.isEmpty {
                keepTransactionForRecovery = true
                throw AppBootstrapperError.configurationRollbackFailed(
                    original: originalError.localizedDescription,
                    rollback: rollbackErrors.joined(separator: "；")
                )
            }
            throw originalError
        }
    }

    private func replaceSingleConfigurationFile(_ data: Data, at destination: URL) throws {
        let fileManager = FileManager.default
        let stagedURL = destination.deletingLastPathComponent().appendingPathComponent(
            ".\(destination.lastPathComponent)-stage-\(UUID().uuidString)"
        )
        defer { try? fileManager.removeItem(at: stagedURL) }
        try configurationFileWriter(data, stagedURL)
        try Self.validateAndRestrictStagedFile(stagedURL, using: fileManager)
        try Self.publishStagedFile(stagedURL, to: destination, using: fileManager)
    }

    private func configurationFileMatches(_ expected: Data, at url: URL) throws -> Bool {
        guard let current = try regularFileDataIfPresent(at: url), current == expected else {
            return false
        }
        try FilePermissions.restrictFile(url)
        return true
    }

    private func regularFileDataIfPresent(at url: URL) throws -> Data? {
        try Self.regularFileDataIfPresent(at: url, using: FileManager.default)
    }

    private func requiredConfigurationFileData(at url: URL) throws -> Data {
        guard let data = try regularFileDataIfPresent(at: url) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return data
    }

    private var configurationTransactionDirectory: URL {
        paths.data.appendingPathComponent(".configuration-transaction", isDirectory: true)
    }

    private func recoverPendingConfigurationTransaction() throws {
        let fileManager = FileManager.default
        let transaction = ConfigurationTransactionPaths(root: configurationTransactionDirectory)
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: transaction.root.path, isDirectory: &isDirectory) else {
            return
        }
        guard (try? fileManager.destinationOfSymbolicLink(atPath: transaction.root.path)) == nil,
            isDirectory.boolValue
        else {
            throw AppBootstrapperError.configurationRecoveryFailed(
                "事务路径不是可信目录：\(transaction.root.path)"
            )
        }

        let manifestData: Data
        do {
            guard
                let data = try Self.regularFileDataIfPresent(
                    at: transaction.manifest,
                    using: fileManager
                )
            else {
                try fileManager.removeItem(at: transaction.root)
                return
            }
            manifestData = data
        } catch {
            throw AppBootstrapperError.configurationRecoveryFailed(
                "事务记录不是可信文件：\(error.localizedDescription)"
            )
        }

        let manifest: ConfigurationTransactionManifest
        do {
            manifest = try JSONDecoder().decode(
                ConfigurationTransactionManifest.self,
                from: manifestData
            )
        } catch {
            throw AppBootstrapperError.configurationRecoveryFailed(
                "事务记录无法解析：\(error.localizedDescription)"
            )
        }
        if manifest.state == .committed {
            try fileManager.removeItem(at: transaction.root)
            return
        }

        let templateSnapshot = ConfigurationFileSnapshot(
            existed: manifest.templateExisted,
            data: nil,
            backupURL: transaction.templateBackup
        )
        let generatedSnapshot = ConfigurationFileSnapshot(
            existed: manifest.generatedExisted,
            data: nil,
            backupURL: transaction.generatedBackup
        )
        let errors = rollbackConfiguration(
            templateSnapshot: templateSnapshot,
            generatedSnapshot: generatedSnapshot,
            using: fileManager
        )
        guard errors.isEmpty else {
            throw AppBootstrapperError.configurationRecoveryFailed(
                errors.joined(separator: "；")
            )
        }
        try fileManager.removeItem(at: transaction.root)
    }

    private func rollbackConfiguration(
        templateSnapshot: ConfigurationFileSnapshot,
        generatedSnapshot: ConfigurationFileSnapshot,
        using fileManager: FileManager
    ) -> [String] {
        var errors: [String] = []
        for (label, snapshot, destination) in [
            ("template.json", templateSnapshot, paths.templateConfig),
            ("config.json", generatedSnapshot, paths.generatedConfig),
        ] {
            do {
                try snapshot.restore(to: destination, using: fileManager)
            } catch {
                errors.append("\(label)：\(error.localizedDescription)")
            }
        }
        return errors
    }

    private static func writeRestrictedConfigurationFile(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FilePermissions.restrictFile(url)
    }

    private static func writeTransactionManifest(
        _ manifest: ConfigurationTransactionManifest,
        to url: URL
    ) throws {
        try writeRestrictedConfigurationFile(try JSONEncoder().encode(manifest), to: url)
    }

    private static func validateAndRestrictStagedFile(
        _ url: URL,
        using fileManager: FileManager
    ) throws {
        guard try regularFileDataIfPresent(at: url, using: fileManager) != nil else {
            throw AppBootstrapperError.invalidConfigurationFile(url)
        }
        try FilePermissions.restrictFile(url, using: fileManager)
    }

    private static func publishStagedFile(
        _ stagedURL: URL,
        to destination: URL,
        using fileManager: FileManager
    ) throws {
        if try regularFileDataIfPresent(at: destination, using: fileManager) != nil {
            _ = try fileManager.replaceItemAt(
                destination,
                withItemAt: stagedURL,
                backupItemName: nil,
                options: []
            )
        } else {
            try fileManager.moveItem(at: stagedURL, to: destination)
        }
    }

    fileprivate static func regularFileDataIfPresent(
        at url: URL,
        using fileManager: FileManager
    ) throws -> Data? {
        if (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil {
            throw AppBootstrapperError.invalidConfigurationFile(url)
        }
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return nil
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard !isDirectory.boolValue,
            values.isRegularFile == true,
            values.isSymbolicLink != true
        else {
            throw AppBootstrapperError.invalidConfigurationFile(url)
        }
        return try Data(contentsOf: url)
    }

    fileprivate static func removeRegularFileIfPresent(
        _ url: URL,
        using fileManager: FileManager
    ) throws {
        if (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil {
            throw AppBootstrapperError.invalidConfigurationFile(url)
        }
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard !isDirectory.boolValue,
            values.isRegularFile == true,
            values.isSymbolicLink != true
        else {
            throw AppBootstrapperError.invalidConfigurationFile(url)
        }
        try fileManager.removeItem(at: url)
    }

    public func currentConfigIP() throws -> String? {
        guard let data = try regularFileDataIfPresent(at: paths.generatedConfig) else { return nil }
        return ConfigTemplate.address(in: data)
    }

    public func currentProxyEndpoint() throws -> ProxyEndpoint {
        try ConfigTemplate.proxyEndpoint(in: requiredConfigurationFileData(at: paths.templateConfig))
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

private struct ConfigurationTransactionPaths {
    let root: URL
    let manifest: URL
    let stagedTemplate: URL
    let stagedGenerated: URL
    let templateBackup: URL
    let generatedBackup: URL

    init(root: URL) {
        self.root = root
        manifest = root.appendingPathComponent("manifest.json")
        stagedTemplate = root.appendingPathComponent("template.stage.json")
        stagedGenerated = root.appendingPathComponent("config.stage.json")
        templateBackup = root.appendingPathComponent("template.backup.json")
        generatedBackup = root.appendingPathComponent("config.backup.json")
    }
}

private struct ConfigurationTransactionManifest: Codable, Sendable {
    enum State: String, Codable, Sendable {
        case prepared
        case committed
    }

    let state: State
    let templateExisted: Bool
    let generatedExisted: Bool
}

private struct ConfigurationFileSnapshot: Sendable {
    let existed: Bool
    let data: Data?
    let backupURL: URL

    static func capture(
        _ url: URL,
        backupURL: URL,
        using fileManager: FileManager
    ) throws -> Self {
        guard
            let data = try AppBootstrapper.regularFileDataIfPresent(
                at: url,
                using: fileManager
            )
        else {
            return Self(existed: false, data: nil, backupURL: backupURL)
        }
        try data.write(to: backupURL, options: .atomic)
        try FilePermissions.restrictFile(backupURL, using: fileManager)
        return Self(existed: true, data: data, backupURL: backupURL)
    }

    func assertUnchanged(at url: URL, using fileManager: FileManager) throws {
        let current = try AppBootstrapper.regularFileDataIfPresent(at: url, using: fileManager)
        guard current == data else {
            throw AppBootstrapperError.templateChangedExternally
        }
    }

    func restore(to url: URL, using fileManager: FileManager) throws {
        if !existed {
            try AppBootstrapper.removeRegularFileIfPresent(url, using: fileManager)
            return
        }
        guard
            let backupData = try AppBootstrapper.regularFileDataIfPresent(
                at: backupURL,
                using: fileManager
            )
        else {
            throw AppBootstrapperError.configurationRecoveryFailed(
                "缺少备份文件：\(backupURL.path)"
            )
        }
        let restoreURL = backupURL.deletingLastPathComponent().appendingPathComponent(
            ".restore-\(UUID().uuidString).json"
        )
        defer { try? fileManager.removeItem(at: restoreURL) }
        try backupData.write(to: restoreURL, options: .atomic)
        try FilePermissions.restrictFile(restoreURL, using: fileManager)
        if try AppBootstrapper.regularFileDataIfPresent(at: url, using: fileManager) != nil {
            _ = try fileManager.replaceItemAt(
                url,
                withItemAt: restoreURL,
                backupItemName: nil,
                options: []
            )
        } else {
            try fileManager.moveItem(at: restoreURL, to: url)
        }
    }
}
