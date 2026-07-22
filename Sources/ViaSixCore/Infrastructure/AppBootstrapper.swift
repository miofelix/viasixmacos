import Foundation
import ViaSixMihomoConfig

public enum AppBootstrapperError: LocalizedError, Equatable, Sendable {
    case configurationRollbackFailed(original: String, rollback: String)
    case configurationRecoveryFailed(String)
    case invalidConfigurationFile(URL)
    case profileChangedExternally
    case virtualInterfaceRequiresPrivilegedService
    case invalidControllerSecret

    public var errorDescription: String? {
        switch self {
        case .configurationRollbackFailed(let original, let rollback):
            "代理配置更新失败，恢复旧配置时也发生错误。原始错误：\(original)；恢复错误：\(rollback)"
        case .configurationRecoveryFailed(let message):
            "上次代理配置更新未完成，自动恢复失败：\(message)"
        case .invalidConfigurationFile(let url):
            "代理配置路径不是普通文件：\(url.path)"
        case .profileChangedExternally:
            "代理配置在编辑期间发生变化，请重新载入后再保存"
        case .virtualInterfaceRequiresPrivilegedService:
            "虚拟网卡模式必须由受信任的系统服务启动"
        case .invalidControllerSecret:
            "Mihomo Controller 本机密钥缺失或无效"
        }
    }
}

public struct BootstrapConfiguration: Equatable, Sendable {
    public let endpoint: ProxyEndpoint
    public let local: LocalProxyConfiguration
    public let effectiveIP: String?
    public let supportsNodeSelection: Bool
    public let launchIssue: MihomoConfigurationError?

    public init(
        endpoint: ProxyEndpoint,
        local: LocalProxyConfiguration = .default,
        effectiveIP: String?,
        supportsNodeSelection: Bool = false,
        launchIssue: MihomoConfigurationError?
    ) {
        self.endpoint = endpoint
        self.local = local
        self.effectiveIP = effectiveIP
        self.supportsNodeSelection = supportsNodeSelection
        self.launchIssue = launchIssue
    }
}

typealias ConfigurationFileWriter = @Sendable (Data, URL) throws -> Void

private struct ConfigurationSources: Sendable {
    let profile: MihomoServerConfiguration?
    let local: LocalProxyConfiguration
}

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
        try prepareControllerSecret()
        try DefaultResourceInstaller.install(into: paths)
        try removeStaleSpeedTestResults()
    }

    private func prepareControllerSecret() throws {
        let fileManager = FileManager.default
        if let data = try Self.regularFileDataIfPresent(
            at: paths.mihomoControllerSecret,
            using: fileManager,
            maximumBytes: MihomoExternalControllerConfiguration.maximumSecretUTF8Bytes + 1
        ),
            (try? Self.validatedControllerSecret(from: data)) != nil
        {
            try FilePermissions.restrictFile(paths.mihomoControllerSecret, using: fileManager)
            return
        }

        // Missing or non-token-safe secrets are regenerated. Accepting CR/LF or
        // other control characters would allow Authorization header injection
        // when the secret is placed on the loopback controller API.
        let secret =
            UUID().uuidString.replacingOccurrences(of: "-", with: "")
            + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        try Self.writeRestrictedConfigurationFile(
            Data((secret + "\n").utf8),
            to: paths.mihomoControllerSecret
        )
    }

    public func mihomoAPIConfiguration() throws -> MihomoAPIConfiguration {
        let local = try loadLocalProxyConfiguration()
        return MihomoAPIConfiguration(
            host: "127.0.0.1",
            port: local.controllerPort,
            secret: try mihomoControllerSecret()
        )
    }

    private func mihomoControllerSecret() throws -> String {
        let data = try Self.regularFileDataIfPresent(
            at: paths.mihomoControllerSecret,
            using: .default,
            maximumBytes: MihomoExternalControllerConfiguration.maximumSecretUTF8Bytes + 1
        )
        guard let data else { throw AppBootstrapperError.invalidControllerSecret }
        return try Self.validatedControllerSecret(from: data)
    }

    private static func validatedControllerSecret(from data: Data) throws -> String {
        guard data.count <= MihomoExternalControllerConfiguration.maximumSecretUTF8Bytes + 1,
            let raw = String(data: data, encoding: .utf8)
        else {
            throw AppBootstrapperError.invalidControllerSecret
        }
        do {
            return try MihomoExternalControllerConfiguration.validatedSecret(raw)
        } catch {
            throw AppBootstrapperError.invalidControllerSecret
        }
    }

    /// Removes only temporary result files created by an interrupted speed
    /// test. Names are matched strictly so persistent and user-created files
    /// are never mistaken for cleanup artifacts.
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
            let values = try fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isRegularFile == true || values.isSymbolicLink == true else {
                continue
            }
            try fileManager.removeItem(at: fileURL)
        }
    }

    private static func isTemporarySpeedTestResultName(_ name: String) -> Bool {
        if uuidBetween(name, prefix: ".result.csv.", suffix: ".tmp") != nil {
            return true
        }
        if uuidBetween(name, prefix: ".current-test-", suffix: ".csv") != nil {
            return true
        }

        let prefix = "..current-test-"
        let suffix = ".tmp"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return false }
        let body = name.dropFirst(prefix.count).dropLast(suffix.count)
        guard let separator = body.range(of: ".csv.") else { return false }
        return UUID(uuidString: String(body[..<separator.lowerBound])) != nil
            && UUID(uuidString: String(body[separator.upperBound...])) != nil
    }

    private static func uuidBetween(_ name: String, prefix: String, suffix: String) -> UUID? {
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return nil }
        let start = name.index(name.startIndex, offsetBy: prefix.count)
        let end = name.index(name.endIndex, offsetBy: -suffix.count)
        guard start <= end else { return nil }
        return UUID(uuidString: String(name[start..<end]))
    }

    public func loadResults() throws -> [SpeedTestResult] {
        // Fail closed on symbolic links so a planted result.csv cannot redirect
        // bootstrap into parsing an attacker-chosen file.
        guard let data = try regularFileDataIfPresent(at: paths.resultCSV) else { return [] }
        return try SpeedTestResultParser.parse(data: data)
    }

    @discardableResult
    public func writeConfig(ip: String? = nil) throws -> Bool {
        let sources = try loadConfigurationSources()
        guard
            !Self.usesDirectRuntime(sources.local),
            sources.profile?.hasReplaceablePrimaryServer == true
        else { return false }
        let config = try runtimeConfiguration(
            profile: sources.profile,
            local: sources.local,
            selectedIP: ip
        )
        try replaceSingleConfigurationFile(config, at: paths.generatedConfig)
        return true
    }

    @discardableResult
    public func prepareConfigForLaunch(ip: String? = nil) throws -> ProxyEndpoint {
        let sources = try loadConfigurationSources()
        let config = try runtimeConfiguration(
            profile: sources.profile,
            local: sources.local,
            selectedIP: ip
        )
        try replaceSingleConfigurationFile(config, at: paths.generatedConfig)
        return sources.local.endpoint
    }

    @discardableResult
    public func validateProfileForLaunch(selectedIP: String? = nil) throws -> ProxyEndpoint {
        let sources = try loadConfigurationSources()
        _ = try runtimeConfiguration(
            profile: sources.profile,
            local: sources.local,
            selectedIP: selectedIP
        )
        return sources.local.endpoint
    }

    /// Builds the root-owned Mihomo configuration used for virtual-interface
    /// mode without publishing it into the user-writable runtime directory.
    /// The caller must hand this document to the privileged service as part of
    /// a single-owner core transition.
    public func privilegedTunConfiguration(
        selectedIP: String? = nil
    ) throws -> Data {
        let sources = try loadConfigurationSources()
        guard sources.local.networkAccessMode == .virtualInterface else {
            throw AppBootstrapperError.virtualInterfaceRequiresPrivilegedService
        }
        return try runtimeConfiguration(
            profile: sources.profile,
            local: sources.local,
            selectedIP: selectedIP,
            projection: .privilegedTun
        )
    }

    /// Builds the versioned binary-plist request consumed by the privileged
    /// helper. Unlike ``privilegedTunConfiguration(selectedIP:)``, this value
    /// is not runnable YAML; the helper must decode it and rebuild the runtime
    /// document through the same privileged projection before use.
    public func privilegedTunConfigurationEnvelope(
        selectedIP: String? = nil
    ) throws -> Data {
        let sources = try loadConfigurationSources()
        guard sources.local.networkAccessMode == .virtualInterface else {
            throw AppBootstrapperError.virtualInterfaceRequiresPrivilegedService
        }
        let local = try sources.local.validated()
        let replacement: String?
        if Self.usesDirectRuntime(local) {
            replacement = nil
        } else if sources.profile?.hasReplaceablePrimaryServer == true {
            replacement = Self.nonEmpty(
                selectedIP?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } else {
            replacement = nil
        }
        return try MihomoPrivilegedEnvelope.encode(
            server: sources.profile,
            options: mihomoRuntimeOptions(for: local, projection: .privilegedTun),
            replacingPrimaryServerWith: replacement
        )
    }

    @discardableResult
    public func replaceProfile(with data: Data, selectedIP: String? = nil) throws -> ProxyEndpoint {
        try replaceProfileTransaction(
            with: data,
            selectedIP: selectedIP,
            expectedProfileData: nil
        )
    }

    @discardableResult
    public func replaceProfileIfUnchanged(
        with data: Data,
        selectedIP: String?,
        expectedProfileData: Data?
    ) throws -> ProxyEndpoint {
        try replaceProfileTransaction(
            with: data,
            selectedIP: selectedIP,
            expectedProfileData: expectedProfileData
        )
    }

    private func replaceProfileTransaction(
        with data: Data,
        selectedIP: String?,
        expectedProfileData: Data?
    ) throws -> ProxyEndpoint {
        let profile = try MihomoServerConfiguration(data: data)
        let local = try localConfiguration(
            importing: profile.viaSixOptions,
            over: localConfigurationForProfileReplacement()
        )
        let generated = try runtimeConfiguration(
            profile: profile,
            local: local,
            selectedIP: selectedIP
        )
        try commitConfiguration(
            profile: profile.data,
            generated: generated,
            local: JSONEncoder.pretty.encode(local),
            expectedProfileData: expectedProfileData
        )
        return local.endpoint
    }

    private func localConfigurationForProfileReplacement() throws -> LocalProxyConfiguration {
        do {
            return try loadLocalProxyConfiguration()
        } catch is DecodingError {
            return .default
        } catch is LocalProxyConfigurationError {
            return .default
        }
    }

    private func localConfiguration(
        importing options: MihomoViaSixProfileOptions?,
        over current: LocalProxyConfiguration
    ) throws -> LocalProxyConfiguration {
        _ = options
        return try current.validated()
    }

    @discardableResult
    public func importProfile(from sourceURL: URL, selectedIP: String? = nil) throws -> ProxyEndpoint {
        try replaceProfile(with: Data(contentsOf: sourceURL), selectedIP: selectedIP)
    }

    public func loadProfileConfiguration() throws -> Data {
        let data = try requiredConfigurationFileData(at: paths.profileConfig)
        return try MihomoServerConfiguration(data: data).data
    }

    public func loadLocalProxyConfiguration() throws -> LocalProxyConfiguration {
        let data = try requiredConfigurationFileData(at: paths.localProxyConfig)
        return try JSONDecoder().decode(LocalProxyConfiguration.self, from: data).validated()
    }

    /// Persists a local preference and regenerates the user-owned Mihomo
    /// document. Virtual-interface preferences are stored here, but enabled
    /// TUN configuration is projected only through privilegedTunConfiguration.
    public func saveLocalProxyPreference(
        _ local: LocalProxyConfiguration,
        selectedIP: String? = nil
    ) throws {
        _ = try replaceLocalProxyConfiguration(
            with: local,
            selectedIP: selectedIP
        )
    }

    @discardableResult
    public func replaceLocalProxyConfiguration(
        with local: LocalProxyConfiguration,
        selectedIP: String? = nil
    ) throws -> ProxyEndpoint {
        let local = try local.validated()
        let profileData = try regularFileDataIfPresent(at: paths.profileConfig)
        let profile: MihomoServerConfiguration?
        if Self.usesDirectRuntime(local) {
            profile = profileData.flatMap { try? MihomoServerConfiguration(data: $0) }
        } else {
            profile = try profileData.map(MihomoServerConfiguration.init(data:))
        }
        if !Self.usesDirectRuntime(local), profile == nil {
            throw MihomoConfigurationError.missingProxySource
        }
        let generated = try runtimeConfiguration(
            profile: profile,
            local: local,
            selectedIP: selectedIP
        )
        try commitConfiguration(
            profile: profileData,
            generated: generated,
            local: JSONEncoder.pretty.encode(local),
            expectedProfileData: nil
        )
        return local.endpoint
    }

    @discardableResult
    public func ensureConfig(ip: String) throws -> Bool {
        let normalizedIP = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIP.isEmpty else { return false }
        let sources = try loadConfigurationSources()
        let expected = try runtimeConfiguration(
            profile: sources.profile,
            local: sources.local,
            selectedIP: normalizedIP
        )
        if try configurationFileMatches(expected, at: paths.generatedConfig) { return false }
        try replaceSingleConfigurationFile(expected, at: paths.generatedConfig)
        return true
    }

    public func synchronizeConfiguration(selectedIP: String?) throws -> BootstrapConfiguration {
        let local = try loadLocalProxyConfiguration()
        let profileData = try regularFileDataIfPresent(at: paths.profileConfig)
        let profile =
            Self.usesDirectRuntime(local)
            ? nil : try profileData.map(MihomoServerConfiguration.init(data:))

        guard Self.usesDirectRuntime(local) || profile != nil else {
            try Self.removeRegularFileIfPresent(paths.generatedConfig, using: .default)
            return BootstrapConfiguration(
                endpoint: local.endpoint,
                local: local,
                effectiveIP: nil,
                supportsNodeSelection: false,
                launchIssue: .missingProxySource
            )
        }

        let supportsNodeSelection =
            !Self.usesDirectRuntime(local) && profile?.hasReplaceablePrimaryServer == true
        let requestedIP = selectedIP?.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only an explicit persisted selection is an override. Reading the
        // generated profile's original server back as a selection would turn a
        // domain such as origin.example into a fake "selected IP" on relaunch.
        let effectiveIP = supportsNodeSelection ? Self.nonEmpty(requestedIP) : nil

        let expected: Data
        do {
            expected = try runtimeConfiguration(
                profile: profile,
                local: local,
                selectedIP: effectiveIP
            )
        } catch let issue as MihomoConfigurationError
            where issue == .selectedNodeMustBeIPv6
            || issue == .ipv6ManagedProfileRequired
        {
            try Self.removeRegularFileIfPresent(paths.generatedConfig, using: .default)
            return BootstrapConfiguration(
                endpoint: local.endpoint,
                local: local,
                effectiveIP: effectiveIP,
                supportsNodeSelection: supportsNodeSelection,
                launchIssue: issue
            )
        }
        if try !configurationFileMatches(expected, at: paths.generatedConfig) {
            try replaceSingleConfigurationFile(expected, at: paths.generatedConfig)
        }
        return BootstrapConfiguration(
            endpoint: local.endpoint,
            local: local,
            effectiveIP: effectiveIP,
            supportsNodeSelection: supportsNodeSelection,
            launchIssue: nil
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func usesDirectRuntime(_ local: LocalProxyConfiguration) -> Bool {
        local.routingMode == .direct
    }

    private func loadConfigurationSources() throws -> ConfigurationSources {
        let local = try loadLocalProxyConfiguration()
        let profileData = try regularFileDataIfPresent(at: paths.profileConfig)
        let profile: MihomoServerConfiguration?
        if Self.usesDirectRuntime(local) {
            profile = profileData.flatMap { try? MihomoServerConfiguration(data: $0) }
        } else {
            profile = try profileData.map(MihomoServerConfiguration.init(data:))
        }
        if !Self.usesDirectRuntime(local), profile == nil {
            throw MihomoConfigurationError.missingProxySource
        }
        return ConfigurationSources(profile: profile, local: local)
    }

    private func runtimeConfiguration(
        profile: MihomoServerConfiguration?,
        local: LocalProxyConfiguration,
        selectedIP: String?,
        projection: MihomoRuntimeProjection = .user
    ) throws -> Data {
        let local = try local.validated()
        let replacement: String?
        if profile?.hasReplaceablePrimaryServer == true {
            replacement = Self.nonEmpty(
                selectedIP?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } else {
            replacement = nil
        }
        return try MihomoServerConfiguration.runtimeConfiguration(
            server: profile,
            options: try mihomoRuntimeOptions(for: local, projection: projection),
            projection: projection,
            replacingPrimaryServerWith: replacement
        )
    }

    private func mihomoRuntimeOptions(
        for local: LocalProxyConfiguration,
        projection: MihomoRuntimeProjection
    ) throws -> MihomoRuntimeOptions {
        let externalController = MihomoExternalControllerConfiguration(
            port: local.controllerPort,
            secret: try mihomoControllerSecret()
        )
        return MihomoRuntimeOptions(
            listenAddress: local.listenAddress,
            mixedPort: local.port,
            routingMode: MihomoRoutingMode(rawValue: local.routingMode.rawValue) ?? .rule,
            logLevel: MihomoLogLevel(rawValue: local.logLevel.rawValue) ?? .warning,
            ipv6Enabled: true,
            udpEnabled: local.udpEnabled,
            sniffingEnabled: local.sniffingEnabled,
            bypassPrivateNetworks: local.bypassPrivateNetworks,
            externalController: externalController,
            tun: projection == .privilegedTun
                ? MihomoTunConfiguration(
                    stack: MihomoTunStack(rawValue: local.tunStack.rawValue) ?? .mixed,
                    strictRoute: local.tunStrictRoute,
                    mtu: local.tunMTU
                )
                : nil
        )
    }

    private func commitConfiguration(
        profile: Data?,
        generated: Data,
        local: Data,
        expectedProfileData: Data?
    ) throws {
        let fileManager = FileManager.default
        try recoverPendingConfigurationTransaction()
        let transaction = ConfigurationTransactionPaths(root: configurationTransactionDirectory)
        try fileManager.createDirectory(at: transaction.root, withIntermediateDirectories: false)
        try FilePermissions.restrictDirectory(transaction.root, using: fileManager)
        var keepTransactionForRecovery = false
        defer {
            if !keepTransactionForRecovery {
                try? fileManager.removeItem(at: transaction.root)
            }
        }

        if let profile {
            try configurationFileWriter(profile, transaction.stagedProfile)
            try Self.validateAndRestrictStagedFile(transaction.stagedProfile, using: fileManager)
        }
        try configurationFileWriter(generated, transaction.stagedConfig)
        try Self.validateAndRestrictStagedFile(transaction.stagedConfig, using: fileManager)
        try configurationFileWriter(local, transaction.stagedLocal)
        try Self.validateAndRestrictStagedFile(transaction.stagedLocal, using: fileManager)

        let profileSnapshot = try ConfigurationFileSnapshot.capture(
            paths.profileConfig,
            backupURL: transaction.profileBackup,
            using: fileManager
        )
        let configSnapshot = try ConfigurationFileSnapshot.capture(
            paths.generatedConfig,
            backupURL: transaction.configBackup,
            using: fileManager
        )
        let localSnapshot = try ConfigurationFileSnapshot.capture(
            paths.localProxyConfig,
            backupURL: transaction.localBackup,
            using: fileManager
        )
        if let expectedProfileData, profileSnapshot.data != expectedProfileData {
            throw AppBootstrapperError.profileChangedExternally
        }

        let prepared = ConfigurationTransactionManifest(
            version: 2,
            state: .prepared,
            profileExisted: profileSnapshot.existed,
            configExisted: configSnapshot.existed,
            localExisted: localSnapshot.existed
        )
        try Self.writeTransactionManifest(prepared, to: transaction.manifest)
        try profileSnapshot.assertUnchanged(at: paths.profileConfig, using: fileManager)
        try configSnapshot.assertUnchanged(at: paths.generatedConfig, using: fileManager)
        try localSnapshot.assertUnchanged(at: paths.localProxyConfig, using: fileManager)

        do {
            try Self.publishStagedFile(
                transaction.stagedConfig,
                to: paths.generatedConfig,
                using: fileManager
            )
            if profile != nil {
                try Self.publishStagedFile(
                    transaction.stagedProfile,
                    to: paths.profileConfig,
                    using: fileManager
                )
            } else {
                try Self.removeRegularFileIfPresent(paths.profileConfig, using: fileManager)
            }
            try Self.publishStagedFile(
                transaction.stagedLocal,
                to: paths.localProxyConfig,
                using: fileManager
            )
            let committed = ConfigurationTransactionManifest(
                version: 2,
                state: .committed,
                profileExisted: profileSnapshot.existed,
                configExisted: configSnapshot.existed,
                localExisted: localSnapshot.existed
            )
            try Self.writeTransactionManifest(committed, to: transaction.manifest)
        } catch {
            let originalError = error
            let rollbackErrors = rollbackCurrentConfiguration(
                profileSnapshot: profileSnapshot,
                configSnapshot: configSnapshot,
                localSnapshot: localSnapshot,
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
            manifest = try JSONDecoder().decode(ConfigurationTransactionManifest.self, from: manifestData)
        } catch {
            throw AppBootstrapperError.configurationRecoveryFailed(
                "事务记录无法解析：\(error.localizedDescription)"
            )
        }
        if manifest.state == .committed {
            try fileManager.removeItem(at: transaction.root)
            return
        }

        let errors: [String]
        if manifest.version == 2 || manifest.profileExisted != nil || manifest.configExisted != nil {
            guard
                let profileExisted = manifest.profileExisted,
                let configExisted = manifest.configExisted,
                let localExisted = manifest.localExisted
            else {
                throw AppBootstrapperError.configurationRecoveryFailed("事务记录缺少 Mihomo 文件状态")
            }
            errors = rollbackCurrentConfiguration(
                profileSnapshot: ConfigurationFileSnapshot(
                    existed: profileExisted,
                    data: nil,
                    backupURL: transaction.profileBackup
                ),
                configSnapshot: ConfigurationFileSnapshot(
                    existed: configExisted,
                    data: nil,
                    backupURL: transaction.configBackup
                ),
                localSnapshot: ConfigurationFileSnapshot(
                    existed: localExisted,
                    data: nil,
                    backupURL: transaction.localBackup
                ),
                using: fileManager
            )
        } else {
            errors = rollbackLegacyConfiguration(
                manifest: manifest,
                transaction: transaction,
                using: fileManager
            )
        }
        guard errors.isEmpty else {
            throw AppBootstrapperError.configurationRecoveryFailed(errors.joined(separator: "；"))
        }
        try fileManager.removeItem(at: transaction.root)
    }

    private func rollbackCurrentConfiguration(
        profileSnapshot: ConfigurationFileSnapshot,
        configSnapshot: ConfigurationFileSnapshot,
        localSnapshot: ConfigurationFileSnapshot,
        using fileManager: FileManager
    ) -> [String] {
        rollback(
            files: [
                ("profile.yaml", profileSnapshot, paths.profileConfig),
                ("Mihomo/config.yaml", configSnapshot, paths.generatedConfig),
                ("local-proxy.json", localSnapshot, paths.localProxyConfig),
            ],
            using: fileManager
        )
    }

    private func rollbackLegacyConfiguration(
        manifest: ConfigurationTransactionManifest,
        transaction: ConfigurationTransactionPaths,
        using fileManager: FileManager
    ) -> [String] {
        guard
            let templateExisted = manifest.templateExisted,
            let generatedExisted = manifest.generatedExisted
        else {
            return ["旧事务记录缺少文件状态"]
        }
        var files: [(String, ConfigurationFileSnapshot, URL)] = [
            (
                "template.json",
                ConfigurationFileSnapshot(
                    existed: templateExisted,
                    data: nil,
                    backupURL: transaction.legacyTemplateBackup
                ),
                paths.legacyTemplateConfig
            ),
            (
                "config.json",
                ConfigurationFileSnapshot(
                    existed: generatedExisted,
                    data: nil,
                    backupURL: transaction.legacyGeneratedBackup
                ),
                paths.legacyGeneratedConfig
            ),
        ]
        if let serverExisted = manifest.serverExisted {
            files.append(
                (
                    "server.json",
                    ConfigurationFileSnapshot(
                        existed: serverExisted,
                        data: nil,
                        backupURL: transaction.legacyServerBackup
                    ),
                    paths.legacyServerConfig
                )
            )
        }
        if let localExisted = manifest.localExisted {
            files.append(
                (
                    "local-proxy.json",
                    ConfigurationFileSnapshot(
                        existed: localExisted,
                        data: nil,
                        backupURL: transaction.localBackup
                    ),
                    paths.localProxyConfig
                )
            )
        }
        return rollback(files: files, using: fileManager)
    }

    private func rollback(
        files: [(String, ConfigurationFileSnapshot, URL)],
        using fileManager: FileManager
    ) -> [String] {
        var errors: [String] = []
        for (label, snapshot, destination) in files {
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
        using fileManager: FileManager,
        maximumBytes: Int? = nil
    ) throws -> Data? {
        if let maximumBytes {
            precondition(maximumBytes > 0)
        }
        if (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil {
            throw AppBootstrapperError.invalidConfigurationFile(url)
        }
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return nil
        }
        let values = try url.resourceValues(
            forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        )
        guard !isDirectory.boolValue,
            values.isRegularFile == true,
            values.isSymbolicLink != true
        else {
            throw AppBootstrapperError.invalidConfigurationFile(url)
        }

        guard let maximumBytes else {
            return try Data(contentsOf: url)
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var data = Data()
        data.reserveCapacity(min(maximumBytes, max(0, values.fileSize ?? 0)))
        while data.count < maximumBytes {
            let remaining = maximumBytes - data.count
            guard let chunk = try handle.read(upToCount: min(remaining, 64 * 1_024)),
                !chunk.isEmpty
            else { break }
            data.append(chunk)
        }
        return data
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
        return MihomoServerConfiguration.proxyServerAddress(in: data)
    }

    public func currentProxyEndpoint() throws -> ProxyEndpoint {
        try loadLocalProxyConfiguration().endpoint
    }

    public func resultForSelectedIP(_ selectedIP: String? = nil) throws -> SpeedTestResult? {
        let explicitIP = selectedIP?.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetIP: String?
        if let explicitIP = Self.nonEmpty(explicitIP) {
            targetIP = explicitIP
        } else {
            targetIP = try currentConfigIP()
        }
        guard let targetIP, !targetIP.isEmpty else { return nil }
        return try loadResults().first {
            $0.ip.trimmingCharacters(in: .whitespacesAndNewlines) == targetIP
        }
    }

}

private struct ConfigurationTransactionPaths {
    let root: URL
    let manifest: URL
    let stagedProfile: URL
    let stagedConfig: URL
    let stagedLocal: URL
    let profileBackup: URL
    let configBackup: URL
    let localBackup: URL
    let legacyTemplateBackup: URL
    let legacyGeneratedBackup: URL
    let legacyServerBackup: URL

    init(root: URL) {
        self.root = root
        manifest = root.appendingPathComponent("manifest.json")
        stagedProfile = root.appendingPathComponent("profile.stage.yaml")
        stagedConfig = root.appendingPathComponent("config.stage.yaml")
        stagedLocal = root.appendingPathComponent("local-proxy.stage.json")
        profileBackup = root.appendingPathComponent("profile.backup.yaml")
        configBackup = root.appendingPathComponent("config.backup.yaml")
        localBackup = root.appendingPathComponent("local-proxy.backup.json")
        legacyTemplateBackup = root.appendingPathComponent("template.backup.json")
        legacyGeneratedBackup = root.appendingPathComponent("config.backup.json")
        legacyServerBackup = root.appendingPathComponent("server.backup.json")
    }
}

private struct ConfigurationTransactionManifest: Codable, Sendable {
    enum State: String, Codable, Sendable {
        case prepared
        case committed
    }

    let version: Int?
    let state: State
    let profileExisted: Bool?
    let configExisted: Bool?
    let localExisted: Bool?
    let templateExisted: Bool?
    let generatedExisted: Bool?
    let serverExisted: Bool?

    init(
        version: Int,
        state: State,
        profileExisted: Bool,
        configExisted: Bool,
        localExisted: Bool
    ) {
        self.version = version
        self.state = state
        self.profileExisted = profileExisted
        self.configExisted = configExisted
        self.localExisted = localExisted
        self.templateExisted = nil
        self.generatedExisted = nil
        self.serverExisted = nil
    }
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
            let data = try AppBootstrapper.regularFileDataIfPresent(at: url, using: fileManager)
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
            throw AppBootstrapperError.profileChangedExternally
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
            ".restore-\(UUID().uuidString)"
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
