import Foundation
import Security
import SystemConfiguration

/// A network service as exposed by macOS System Configuration.
///
/// The proxy configuration is stored as a property-list payload instead of a
/// hand-written model.  This is intentional: macOS adds proxy keys over time,
/// and keeping the original payload lets ViaSix restore settings it does not
/// know about (PAC, bypass lists, FTP, and future keys) byte-for-byte.
public struct SystemProxyServiceState: Codable, Equatable, Sendable {
    public let serviceID: String
    public let serviceName: String
    public let isEnabled: Bool
    /// False when macOS does not expose a proxies protocol for this service.
    /// Such a service is reported instead of being silently skipped.
    public let hasProxyProtocol: Bool
    public let protocolIsEnabled: Bool
    public let configuration: Data?

    public init(
        serviceID: String,
        serviceName: String,
        isEnabled: Bool,
        hasProxyProtocol: Bool = true,
        protocolIsEnabled: Bool,
        configuration: Data?
    ) {
        self.serviceID = serviceID
        self.serviceName = serviceName
        self.isEnabled = isEnabled
        self.hasProxyProtocol = hasProxyProtocol
        self.protocolIsEnabled = protocolIsEnabled
        self.configuration = configuration
    }
}

/// A change applied to one network service by ``SystemProxyStore``.
public struct SystemProxyServiceChange: Equatable, Sendable {
    public let serviceID: String
    public let configuration: Data?
    public let protocolIsEnabled: Bool
    /// The state observed immediately before the transaction.  A production
    /// store validates this precondition while holding its preferences lock,
    /// preventing ViaSix from overwriting a user's concurrent edit.
    public let expectedState: SystemProxyServiceState?

    public init(
        serviceID: String,
        configuration: Data?,
        protocolIsEnabled: Bool,
        expectedState: SystemProxyServiceState? = nil
    ) {
        self.serviceID = serviceID
        self.configuration = configuration
        self.protocolIsEnabled = protocolIsEnabled
        self.expectedState = expectedState
    }
}

public enum SystemProxyStoreError: LocalizedError, Equatable, Sendable {
    case preferencesUnavailable
    case currentNetworkSetUnavailable
    case serviceUnavailable(String)
    case proxyProtocolUnavailable(String)
    case preferencesBusy
    case preferencesChanged
    case commitFailed(Int32)
    case applyFailed(Int32)
    case lockFailed(Int32)
    case invalidPropertyList(String)
    case authorizationFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .preferencesUnavailable:
            "无法打开 macOS 网络设置"
        case .currentNetworkSetUnavailable:
            "macOS 没有可用的网络服务集合"
        case .serviceUnavailable(let serviceID):
            "找不到网络服务 " + serviceID
        case .proxyProtocolUnavailable(let serviceID):
            "网络服务 " + serviceID + " 不支持代理设置"
        case .preferencesBusy:
            "macOS 网络设置正被其他程序占用"
        case .preferencesChanged:
            "macOS 网络设置在操作期间发生变化"
        case .commitFailed(let status):
            "保存 macOS 网络设置失败（" + String(status) + "）"
        case .applyFailed(let status):
            "应用 macOS 网络设置失败（" + String(status) + "）"
        case .lockFailed(let status):
            "锁定 macOS 网络设置失败（" + String(status) + "）"
        case .invalidPropertyList(let reason):
            "代理设置不是有效的属性列表：" + reason
        case .authorizationFailed(let status):
            "没有修改 macOS 网络设置所需的权限（" + String(status) + "）"
        }
    }
}

/// The small platform boundary used by ``SystemProxyManager``.
///
/// Tests can provide an in-memory implementation.  The macOS implementation
/// is ``MacSystemProxyStore`` and uses SystemConfiguration directly; no shell
/// commands or undocumented APIs are involved.
public protocol SystemProxyStore: Sendable {
    func readServices() throws -> [SystemProxyServiceState]
    func apply(_ changes: [SystemProxyServiceChange]) throws
}

public enum SystemProxyManagerError: LocalizedError, Equatable, Sendable {
    case invalidEndpoint
    case invalidConfiguration(String)
    case noEnabledServices
    case unsupportedServices([String])
    case duplicateServiceID(String)
    case snapshotMissing
    case snapshotUnreadable(String)
    case snapshotWriteFailed(String)
    case externalChange([String])
    case transactionFailed(String, rollback: String?)
    case recoveryFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "系统代理地址或端口无效"
        case .invalidConfiguration(let reason):
            "系统代理配置无效：" + reason
        case .noEnabledServices:
            "没有找到可用的已启用网络服务"
        case .unsupportedServices(let ids):
            "以下网络服务不支持系统代理：" + ids.joined(separator: "、")
        case .duplicateServiceID(let id):
            "网络服务标识重复：" + id
        case .snapshotMissing:
            "没有找到本次代理会话的系统设置快照"
        case .snapshotUnreadable(let reason):
            "无法读取系统代理快照：" + reason
        case .snapshotWriteFailed(let reason):
            "无法保存系统代理快照：" + reason
        case .externalChange(let ids):
            "以下网络服务已被其他程序修改，未覆盖其设置：" + ids.joined(separator: "、")
        case .transactionFailed(let original, let rollback):
            if let rollback {
                "应用系统代理失败：" + original + "；恢复旧设置也失败：" + rollback
            } else {
                "应用系统代理失败：" + original
            }
        case .recoveryFailed(let reason):
            "恢复上次系统代理设置失败：" + reason
        }
    }
}

public struct SystemProxyRestoreReport: Codable, Equatable, Sendable {
    public let restoredServiceIDs: [String]
    public let skippedExternallyModifiedServiceIDs: [String]
    public let missingServiceIDs: [String]

    public init(
        restoredServiceIDs: [String] = [],
        skippedExternallyModifiedServiceIDs: [String] = [],
        missingServiceIDs: [String] = []
    ) {
        self.restoredServiceIDs = restoredServiceIDs
        self.skippedExternallyModifiedServiceIDs = skippedExternallyModifiedServiceIDs
        self.missingServiceIDs = missingServiceIDs
    }

    public var changedByUser: Bool { !skippedExternallyModifiedServiceIDs.isEmpty }
}

public struct SystemProxySnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public struct Service: Codable, Equatable, Sendable {
        public let serviceID: String
        public let serviceName: String
        public let originalProtocolIsEnabled: Bool
        public let originalConfiguration: Data?
        public let appliedProtocolIsEnabled: Bool
        public let appliedConfiguration: Data?

        public init(
            serviceID: String,
            serviceName: String,
            originalProtocolIsEnabled: Bool,
            originalConfiguration: Data?,
            appliedProtocolIsEnabled: Bool,
            appliedConfiguration: Data?
        ) {
            self.serviceID = serviceID
            self.serviceName = serviceName
            self.originalProtocolIsEnabled = originalProtocolIsEnabled
            self.originalConfiguration = originalConfiguration
            self.appliedProtocolIsEnabled = appliedProtocolIsEnabled
            self.appliedConfiguration = appliedConfiguration
        }
    }

    public let version: Int
    public let sessionID: UUID
    public let createdAt: Date
    public let endpoint: ProxyEndpoint
    public let services: [Service]

    public init(
        sessionID: UUID = UUID(),
        createdAt: Date = Date(),
        endpoint: ProxyEndpoint,
        services: [Service],
        version: Int = Self.currentVersion
    ) {
        self.version = version
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.endpoint = endpoint
        self.services = services
    }
}

/// Coordinates a reversible system-proxy session.
///
/// A snapshot is written before the first OS mutation.  Every transaction has
/// compare-and-swap preconditions, and a failed apply is followed by a best
/// effort rollback.  On the next launch ``recoverIfNeeded`` can finish a
/// transaction left behind by a crash.
public actor SystemProxyManager {
    public let snapshotURL: URL

    private let store: any SystemProxyStore
    private let fileManager: FileManager
    private let now: @Sendable () -> Date

    public init(
        store: any SystemProxyStore = MacSystemProxyStore(),
        snapshotURL: URL,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.snapshotURL = snapshotURL
        self.fileManager = fileManager
        self.now = now
    }

    public init(
        store: any SystemProxyStore = MacSystemProxyStore(),
        paths: AppPaths,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.snapshotURL = paths.systemProxySnapshot
        self.fileManager = fileManager
        self.now = now
    }

    /// Enables HTTP, HTTPS and SOCKS on every currently enabled network
    /// service.  Existing bypass, PAC and unknown keys are retained in the
    /// desired payload; they are restored exactly when the session ends.
    @discardableResult
    public func enable(endpoint: ProxyEndpoint) throws -> SystemProxySnapshot {
        try validate(endpoint: endpoint)

        // A stale active session can only be superseded after an attempted
        // recovery.  This prevents stacking snapshots and losing the user's
        // original settings after repeated start/stop cycles.
        if snapshotExists() {
            _ = try recoverIfNeeded()
        }

        let states = try store.readServices()
        let enabled = try unique(states.filter(\.isEnabled))
        guard !enabled.isEmpty else { throw SystemProxyManagerError.noEnabledServices }
        let unsupported = enabled.filter { !$0.hasProxyProtocol }.map(\.serviceID)
        guard unsupported.isEmpty else {
            throw SystemProxyManagerError.unsupportedServices(unsupported)
        }

        let desiredByID = Dictionary(
            uniqueKeysWithValues: try enabled.map { state in
                (
                    state.serviceID,
                    try makeProxyConfiguration(
                        from: state.configuration,
                        endpoint: endpoint
                    )
                )
            })
        let snapshot = SystemProxySnapshot(
            createdAt: now(),
            endpoint: endpoint,
            services: enabled.map { state in
                SystemProxySnapshot.Service(
                    serviceID: state.serviceID,
                    serviceName: state.serviceName,
                    originalProtocolIsEnabled: state.protocolIsEnabled,
                    originalConfiguration: state.configuration,
                    appliedProtocolIsEnabled: true,
                    appliedConfiguration: desiredByID[state.serviceID]!
                )
            }
        )

        // Persist the recovery point before touching macOS.  A write failure
        // is reported as-is; no OS mutation has happened yet, so attempting
        // a rollback here would only hide the actionable persistence error.
        try write(snapshot)
        do {
            let changes = enabled.map { state in
                SystemProxyServiceChange(
                    serviceID: state.serviceID,
                    configuration: desiredByID[state.serviceID]!,
                    protocolIsEnabled: true,
                    expectedState: state
                )
            }
            try store.apply(changes)
            return snapshot
        } catch {
            let original = String(describing: error)
            do {
                try rollbackEnableTransaction(
                    enabled: enabled,
                    desiredByID: desiredByID
                )
                try removeSnapshot()
            } catch {
                throw SystemProxyManagerError.transactionFailed(
                    original,
                    rollback: String(describing: error)
                )
            }
            throw SystemProxyManagerError.transactionFailed(original, rollback: nil)
        }
    }

    /// Restores the exact settings captured by the last successful enable.
    /// If another application changed a service in the meantime, that service
    /// is left untouched and reported in the result.
    @discardableResult
    public func disable() throws -> SystemProxyRestoreReport {
        guard let snapshot = try loadSnapshotIfPresent() else {
            throw SystemProxyManagerError.snapshotMissing
        }
        let current = try indexed(try store.readServices())
        var restoreChanges: [SystemProxyServiceChange] = []
        var restored: [String] = []
        var skipped: [String] = []
        var missing: [String] = []

        for service in snapshot.services {
            guard let state = current[service.serviceID] else {
                missing.append(service.serviceID)
                continue
            }
            guard
                systemProxyConfigurationsEqual(
                    state.configuration,
                    service.appliedConfiguration
                ),
                state.protocolIsEnabled == service.appliedProtocolIsEnabled
            else {
                skipped.append(service.serviceID)
                continue
            }
            restoreChanges.append(
                SystemProxyServiceChange(
                    serviceID: service.serviceID,
                    configuration: service.originalConfiguration,
                    protocolIsEnabled: service.originalProtocolIsEnabled,
                    expectedState: state
                ))
            restored.append(service.serviceID)
        }

        do {
            if !restoreChanges.isEmpty { try store.apply(restoreChanges) }
            try removeSnapshot()
            return SystemProxyRestoreReport(
                restoredServiceIDs: restored,
                skippedExternallyModifiedServiceIDs: skipped,
                missingServiceIDs: missing
            )
        } catch {
            throw SystemProxyManagerError.recoveryFailed(String(describing: error))
        }
    }

    /// Completes a snapshot left by an interrupted or crashed session.  It is
    /// safe to call at every application launch.  User edits are detected and
    /// never overwritten.
    @discardableResult
    public func recoverIfNeeded() throws -> SystemProxyRestoreReport {
        guard snapshotExists() else { return SystemProxyRestoreReport() }
        return try disable()
    }

    public func isEnabled() -> Bool { snapshotExists() }

    // MARK: - Snapshot and configuration helpers

    private func validate(endpoint: ProxyEndpoint) throws {
        let host = endpoint.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, (1...65_535).contains(endpoint.port) else {
            throw SystemProxyManagerError.invalidEndpoint
        }
    }

    private func unique(_ states: [SystemProxyServiceState]) throws -> [SystemProxyServiceState] {
        var seen = Set<String>()
        for state in states {
            guard seen.insert(state.serviceID).inserted else {
                throw SystemProxyManagerError.duplicateServiceID(state.serviceID)
            }
        }
        return states
    }

    private func indexed(_ states: [SystemProxyServiceState]) throws -> [String: SystemProxyServiceState] {
        Dictionary(uniqueKeysWithValues: try unique(states).map { ($0.serviceID, $0) })
    }

    private func rollbackEnableTransaction(
        enabled: [SystemProxyServiceState],
        desiredByID: [String: Data]
    ) throws {
        // Only roll back services that actually contain ViaSix's desired
        // payload.  If a user edited a service while the transaction was
        // failing, its new value is left untouched.
        let current = try indexed(try store.readServices())
        let changes = enabled.compactMap { original -> SystemProxyServiceChange? in
            guard let state = current[original.serviceID],
                state.protocolIsEnabled,
                systemProxyConfigurationsEqual(
                    state.configuration,
                    desiredByID[original.serviceID]
                )
            else { return nil }
            return SystemProxyServiceChange(
                serviceID: original.serviceID,
                configuration: original.configuration,
                protocolIsEnabled: original.protocolIsEnabled,
                expectedState: state
            )
        }
        if !changes.isEmpty { try store.apply(changes) }
    }

    private func makeProxyConfiguration(from data: Data?, endpoint: ProxyEndpoint) throws -> Data {
        var object: [String: Any]
        if let data {
            let decoded: Any
            do {
                decoded = try PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: nil
                )
            } catch {
                throw SystemProxyManagerError.invalidConfiguration(String(describing: error))
            }
            guard let dictionary = decoded as? [String: Any] else {
                throw SystemProxyManagerError.invalidConfiguration("代理设置不是字典")
            }
            object = dictionary
        } else {
            object = [:]
        }

        object["HTTPEnable"] = 1
        object["HTTPProxy"] = endpoint.host
        object["HTTPPort"] = endpoint.port
        object["HTTPSEnable"] = 1
        object["HTTPSProxy"] = endpoint.host
        object["HTTPSPort"] = endpoint.port
        object["SOCKSEnable"] = 1
        object["SOCKSProxy"] = endpoint.host
        object["SOCKSPort"] = endpoint.port
        // A PAC and global proxy are mutually exclusive in macOS.  Preserve
        // the PAC URL itself so the original snapshot can restore it.
        object["ProxyAutoConfigEnable"] = 0

        do {
            return try PropertyListSerialization.data(
                fromPropertyList: object,
                format: .binary,
                options: 0
            )
        } catch {
            throw SystemProxyManagerError.invalidConfiguration(String(describing: error))
        }
    }

    private func snapshotExists() -> Bool {
        fileManager.fileExists(atPath: snapshotURL.path)
    }

    private func loadSnapshotIfPresent() throws -> SystemProxySnapshot? {
        guard snapshotExists() else { return nil }
        do {
            let data = try Data(contentsOf: snapshotURL)
            let snapshot = try JSONDecoder().decode(SystemProxySnapshot.self, from: data)
            guard snapshot.version == SystemProxySnapshot.currentVersion else {
                throw SystemProxyManagerError.snapshotUnreadable(
                    "版本 " + String(snapshot.version) + " 不受支持"
                )
            }
            return snapshot
        } catch let error as SystemProxyManagerError {
            throw error
        } catch {
            throw SystemProxyManagerError.snapshotUnreadable(String(describing: error))
        }
    }

    private func write(_ snapshot: SystemProxySnapshot) throws {
        do {
            try fileManager.createDirectory(
                at: snapshotURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(snapshot).write(to: snapshotURL, options: .atomic)
            try FilePermissions.restrictFile(snapshotURL, using: fileManager)
        } catch {
            throw SystemProxyManagerError.snapshotWriteFailed(String(describing: error))
        }
    }

    private func removeSnapshot() throws {
        guard snapshotExists() else { return }
        do {
            try fileManager.removeItem(at: snapshotURL)
        } catch {
            throw SystemProxyManagerError.snapshotWriteFailed(String(describing: error))
        }
    }
}

/// Native macOS implementation of ``SystemProxyStore``.
public final class MacSystemProxyStore: SystemProxyStore, @unchecked Sendable {
    private let processName: String

    public init(processName: String = AppMetadata.name) {
        self.processName = processName
    }

    public func readServices() throws -> [SystemProxyServiceState] {
        try withPreferences { preferences in
            try readServices(from: preferences)
        }
    }

    public func apply(_ changes: [SystemProxyServiceChange]) throws {
        guard !changes.isEmpty else { return }
        try withPreferences { preferences in
            guard SCPreferencesLock(preferences, true) else {
                throw storeErrorFromSCStatus(.lockFailed)
            }
            var unlocked = false
            defer {
                if !unlocked { _ = SCPreferencesUnlock(preferences) }
            }

            let states = try readServices(from: preferences)
            let byID = Dictionary(uniqueKeysWithValues: states.map { ($0.serviceID, $0) })
            for change in changes {
                guard let current = byID[change.serviceID] else {
                    throw SystemProxyStoreError.serviceUnavailable(change.serviceID)
                }
                if let expected = change.expectedState,
                    !systemProxyServiceStatesEqual(current, expected)
                {
                    throw SystemProxyStoreError.preferencesChanged
                }
            }

            for change in changes {
                guard
                    let service = SCNetworkServiceCopy(
                        preferences,
                        change.serviceID as CFString
                    )
                else {
                    throw SystemProxyStoreError.serviceUnavailable(change.serviceID)
                }
                guard
                    let proxy = SCNetworkServiceCopyProtocol(
                        service,
                        kSCNetworkProtocolTypeProxies
                    )
                else {
                    throw SystemProxyStoreError.proxyProtocolUnavailable(change.serviceID)
                }
                guard
                    SCNetworkProtocolSetConfiguration(
                        proxy,
                        try propertyListDictionary(from: change.configuration)
                    )
                else {
                    throw storeErrorFromSCStatus(.commitFailed)
                }
                guard SCNetworkProtocolSetEnabled(proxy, change.protocolIsEnabled) else {
                    throw storeErrorFromSCStatus(.commitFailed)
                }
            }

            guard SCPreferencesCommitChanges(preferences) else {
                throw storeErrorFromSCStatus(.commitFailed)
            }
            guard SCPreferencesApplyChanges(preferences) else {
                throw storeErrorFromSCStatus(.applyFailed)
            }
            _ = SCPreferencesUnlock(preferences)
            unlocked = true
        }
    }

    private func readServices(from preferences: SCPreferences) throws -> [SystemProxyServiceState] {
        guard let services = SCNetworkServiceCopyAll(preferences) else {
            throw SystemProxyStoreError.currentNetworkSetUnavailable
        }
        var result: [SystemProxyServiceState] = []
        for case let service as SCNetworkService in services as [AnyObject] {
            guard let serviceID = SCNetworkServiceGetServiceID(service) as String? else {
                continue
            }
            let serviceName = (SCNetworkServiceGetName(service) as String?) ?? serviceID
            guard
                let proxy = SCNetworkServiceCopyProtocol(
                    service,
                    kSCNetworkProtocolTypeProxies
                )
            else {
                // Keep unsupported services in the inventory.  The manager
                // will reject an enable transaction before changing any
                // service, rather than silently leaving one network path
                // outside the user's requested system-proxy mode.
                result.append(
                    SystemProxyServiceState(
                        serviceID: serviceID,
                        serviceName: serviceName,
                        isEnabled: SCNetworkServiceGetEnabled(service),
                        hasProxyProtocol: false,
                        protocolIsEnabled: false,
                        configuration: nil
                    ))
                continue
            }
            let configuration = try propertyListData(
                from: SCNetworkProtocolGetConfiguration(proxy)
            )
            result.append(
                SystemProxyServiceState(
                    serviceID: serviceID,
                    serviceName: serviceName,
                    isEnabled: SCNetworkServiceGetEnabled(service),
                    hasProxyProtocol: true,
                    protocolIsEnabled: SCNetworkProtocolGetEnabled(proxy),
                    configuration: configuration
                ))
        }
        return result
    }

    private func withPreferences<T>(
        _ body: (SCPreferences) throws -> T
    ) throws -> T {
        var authorization: AuthorizationRef?
        // Start with an empty authorization object.  The
        // SCPreferencesCreateWithAuthorization helper requests the concrete
        // System Configuration network right when a privileged operation is
        // performed, including user interaction when policy requires it.
        let authorizationStatus = AuthorizationCreate(nil, nil, [], &authorization)
        guard authorizationStatus == errAuthorizationSuccess else {
            throw SystemProxyStoreError.authorizationFailed(authorizationStatus)
        }
        defer {
            if let authorization { _ = AuthorizationFree(authorization, []) }
        }
        guard
            let preferences = SCPreferencesCreateWithAuthorization(
                nil,
                processName as CFString,
                nil,
                authorization
            )
        else {
            throw SystemProxyStoreError.preferencesUnavailable
        }
        return try body(preferences)
    }

    private func propertyListDictionary(from data: Data?) throws -> CFDictionary? {
        guard let data else { return nil }
        do {
            let propertyList = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            )
            guard let dictionary = propertyList as? NSDictionary else {
                throw SystemProxyStoreError.invalidPropertyList("代理设置不是字典")
            }
            return dictionary as CFDictionary
        } catch let error as SystemProxyStoreError {
            throw error
        } catch {
            throw SystemProxyStoreError.invalidPropertyList(String(describing: error))
        }
    }

    private func propertyListData(from dictionary: CFDictionary?) throws -> Data? {
        guard let dictionary else { return nil }
        do {
            return try PropertyListSerialization.data(
                fromPropertyList: dictionary,
                format: .binary,
                options: 0
            )
        } catch {
            throw SystemProxyStoreError.invalidPropertyList(String(describing: error))
        }
    }

    private enum SCFailureKind { case lockFailed, commitFailed, applyFailed }

    private func storeErrorFromSCStatus(_ kind: SCFailureKind) -> SystemProxyStoreError {
        let status = SCError()
        if status == Int32(kSCStatusAccessError) {
            return .authorizationFailed(status)
        }
        switch kind {
        case .lockFailed:
            if status == Int32(kSCStatusPrefsBusy) { return .preferencesBusy }
            return .lockFailed(status)
        case .commitFailed:
            return .commitFailed(status)
        case .applyFailed:
            return .applyFailed(status)
        }
    }
}

/// SystemConfiguration may normalize or reorder property-list keys when it
/// commits a dictionary. Compare decoded values instead of serialized bytes so
/// a harmless representation change cannot prevent restoration.
private func systemProxyConfigurationsEqual(_ lhs: Data?, _ rhs: Data?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil):
        return true
    case (.some, nil), (nil, .some):
        return false
    case (.some(let lhs), .some(let rhs)):
        guard
            let lhsObject = try? PropertyListSerialization.propertyList(
                from: lhs,
                options: [],
                format: nil
            ),
            let rhsObject = try? PropertyListSerialization.propertyList(
                from: rhs,
                options: [],
                format: nil
            )
        else {
            return lhs == rhs
        }
        return (lhsObject as? NSObject)?.isEqual(rhsObject) == true
    }
}

private func systemProxyServiceStatesEqual(
    _ lhs: SystemProxyServiceState,
    _ rhs: SystemProxyServiceState
) -> Bool {
    lhs.serviceID == rhs.serviceID
        && lhs.serviceName == rhs.serviceName
        && lhs.isEnabled == rhs.isEnabled
        && lhs.hasProxyProtocol == rhs.hasProxyProtocol
        && lhs.protocolIsEnabled == rhs.protocolIsEnabled
        && systemProxyConfigurationsEqual(lhs.configuration, rhs.configuration)
}
