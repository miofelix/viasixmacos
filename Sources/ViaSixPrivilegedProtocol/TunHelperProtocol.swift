import CryptoKit
import Foundation

public enum TunHelperConstants {
    public static let appBundleIdentifier = "com.felix.viasix"
    public static let helperBundleIdentifier = "com.felix.viasix.tun-helper"
    public static let installerBundleIdentifier = "com.felix.viasix.tun-installer"
    public static let machServiceName = helperBundleIdentifier
    public static let launchDaemonPlistName = "\(helperBundleIdentifier).plist"
    public static let helperRelativePath =
        "Contents/Library/HelperTools/\(helperBundleIdentifier)"
    public static let installerRelativePath =
        "Contents/Library/HelperTools/\(installerBundleIdentifier)"
    public static let localInstallationContainerPath =
        "/Library/Application Support/com.felix.viasix"
    public static let localInstalledAppPath =
        "\(localInstallationContainerPath)/InstalledApp/ViaSix.app"
    public static let localInstallationPolicyPath =
        "\(localInstallationContainerPath)/TunLocalInstallationPolicy.plist"
    public static let systemLaunchDaemonPlistPath =
        "/Library/LaunchDaemons/\(launchDaemonPlistName)"
    public static let errorDomain = "com.felix.viasix.tun-helper.error"
    public static let protocolVersion = 2
    public static let implementationVersion = 4
}

public struct TunHelperFeature: OptionSet, Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let fixedRuntimeManagement = Self(rawValue: 1 << 0)
    public static let sessionLifecycle = Self(rawValue: 1 << 1)
    public static let routingModeControl = Self(rawValue: 1 << 2)
    public static let recovery = Self(rawValue: 1 << 3)
    public static let ipv4 = Self(rawValue: 1 << 4)
    public static let ipv6 = Self(rawValue: 1 << 5)
    public static let systemRouting = Self(rawValue: 1 << 6)
    public static let loopbackPrevention = Self(rawValue: 1 << 7)
    public static let dnsManagement = Self(rawValue: 1 << 8)
    public static let networkChangeRecovery = Self(rawValue: 1 << 9)
    public static let loopbackController = Self(rawValue: 1 << 10)

    public static let allKnown: Self = [
        .fixedRuntimeManagement,
        .sessionLifecycle,
        .routingModeControl,
        .recovery,
        .ipv4,
        .ipv6,
        .systemRouting,
        .loopbackPrevention,
        .dnsManagement,
        .networkChangeRecovery,
        .loopbackController,
    ]
}

/// Scalar-only compatibility handshake shared with protocol v1. The selector
/// and callback layout are permanent so a newer client can reject an older,
/// still-running launch daemon before invoking newer selectors.
public struct TunHelperProbeResult: Equatable, Sendable {
    public let protocolVersion: Int
    public let implementationVersion: Int
    public let supportedFeatures: UInt64
    public let recoveryPending: Bool

    public init(
        protocolVersion: Int,
        implementationVersion: Int,
        supportedFeatures: UInt64,
        recoveryPending: Bool
    ) {
        self.protocolVersion = protocolVersion
        self.implementationVersion = implementationVersion
        self.supportedFeatures = supportedFeatures
        self.recoveryPending = recoveryPending
    }
}

@objc public enum TunPrivilegedRuntimeState: Int, CaseIterable, Sendable {
    /// This helper build cannot inspect or manage the fixed privileged runtime.
    case unavailable
    case notInstalled
    case ready
    case repairRequired
    case installing
    case failed
}

@objc public enum TunHelperSessionPhase: Int, CaseIterable, Sendable {
    case inactive
    case starting
    case running
    case stopping
    case recovering
    /// A persisted session exists, but no live backend can safely own or clean it.
    case recoveryRequired
    case failed
}

@objc public enum TunHelperRoutingMode: Int, CaseIterable, Sendable {
    case rule
    case global
    case direct
}

@objc public enum TunHelperErrorCode: Int, Sendable {
    case backendUnavailable = 1
    case invalidConfigurationEnvelope = 2
    case invalidRoutingMode = 3
    case invalidStatusSnapshot = 4
    case runtimeUnavailable = 5
    case sessionBusy = 6
    case sessionNotOwned = 7
    case operationFailed = 8
}

public enum TunConfigurationEnvelopeError: LocalizedError, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case emptyPayload
    case payloadTooLarge(Int)
    case invalidSHA256
    case sha256Mismatch
    case payloadIsNotBinaryPropertyList
    case payloadRootIsNotDictionary

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "特权配置封装版本不受支持：\(version)"
        case .emptyPayload:
            "特权配置封装为空"
        case .payloadTooLarge(let size):
            "特权配置封装过大：\(size) 字节"
        case .invalidSHA256:
            "特权配置封装 SHA-256 无效"
        case .sha256Mismatch:
            "特权配置封装 SHA-256 校验失败"
        case .payloadIsNotBinaryPropertyList:
            "特权配置必须是 ViaSix 类型化二进制属性列表"
        case .payloadRootIsNotDictionary:
            "特权配置的类型化属性列表顶层必须是字典"
        }
    }
}

/// Versioned transport for the `ViaSixMihomoConfig.MihomoPrivilegedEnvelope`
/// binary property-list model. The protocol target stays independent from the
/// configuration module, so `payload` must be decoded there again before use.
/// It is deliberately not a raw YAML/JSON Mihomo document.
public final class TunConfigurationEnvelope: NSObject, NSSecureCoding, @unchecked Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumPayloadBytes = 8 * 1_024 * 1_024
    public static var supportsSecureCoding: Bool { true }

    public let schemaVersion: Int
    public let payload: Data
    public let sha256: String

    public convenience init(payload: Data) throws {
        try self.init(
            schemaVersion: Self.currentSchemaVersion,
            payload: payload,
            sha256: Self.sha256Hex(of: payload)
        )
    }

    public init(
        schemaVersion: Int,
        payload: Data,
        sha256: String
    ) throws {
        try Self.validate(
            schemaVersion: schemaVersion,
            payload: payload,
            sha256: sha256
        )
        self.schemaVersion = schemaVersion
        self.payload = payload
        self.sha256 = sha256
        super.init()
    }

    public required init?(coder: NSCoder) {
        let schemaVersion = coder.decodeInteger(forKey: CodingKey.schemaVersion)
        guard
            let payload = coder.decodeObject(
                of: NSData.self,
                forKey: CodingKey.payload
            ) as Data?,
            let sha256 = coder.decodeObject(
                of: NSString.self,
                forKey: CodingKey.sha256
            ) as String?,
            (try? Self.validate(
                schemaVersion: schemaVersion,
                payload: payload,
                sha256: sha256
            )) != nil
        else { return nil }

        self.schemaVersion = schemaVersion
        self.payload = payload
        self.sha256 = sha256
        super.init()
    }

    public func encode(with coder: NSCoder) {
        coder.encode(schemaVersion, forKey: CodingKey.schemaVersion)
        coder.encode(payload as NSData, forKey: CodingKey.payload)
        coder.encode(sha256 as NSString, forKey: CodingKey.sha256)
    }

    public func validate() throws {
        try Self.validate(
            schemaVersion: schemaVersion,
            payload: payload,
            sha256: sha256
        )
    }

    public static func sha256Hex(of payload: Data) -> String {
        SHA256.hash(data: payload)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func validate(
        schemaVersion: Int,
        payload: Data,
        sha256: String
    ) throws {
        guard schemaVersion == currentSchemaVersion else {
            throw TunConfigurationEnvelopeError.unsupportedSchemaVersion(schemaVersion)
        }
        guard !payload.isEmpty else {
            throw TunConfigurationEnvelopeError.emptyPayload
        }
        guard payload.count <= maximumPayloadBytes else {
            throw TunConfigurationEnvelopeError.payloadTooLarge(payload.count)
        }
        guard isLowercaseHex(sha256, length: 64) else {
            throw TunConfigurationEnvelopeError.invalidSHA256
        }
        guard sha256Hex(of: payload) == sha256 else {
            throw TunConfigurationEnvelopeError.sha256Mismatch
        }

        var format = PropertyListSerialization.PropertyListFormat.binary
        let root: Any
        do {
            root = try PropertyListSerialization.propertyList(
                from: payload,
                options: [],
                format: &format
            )
        } catch {
            throw TunConfigurationEnvelopeError.payloadIsNotBinaryPropertyList
        }
        guard format == .binary else {
            throw TunConfigurationEnvelopeError.payloadIsNotBinaryPropertyList
        }
        guard root is [String: Any] else {
            throw TunConfigurationEnvelopeError.payloadRootIsNotDictionary
        }
    }

    private static func isLowercaseHex(_ value: String, length: Int) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == length else { return false }
        return bytes.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }

    private enum CodingKey {
        static let schemaVersion = "schemaVersion"
        static let payload = "payload"
        static let sha256 = "sha256"
    }
}

public enum TunHelperStatusSnapshotError: LocalizedError, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case incompatibleProtocol(Int)
    case invalidRuntimeState(Int)
    case invalidSessionPhase(Int)
    case invalidRoutingMode(Int)
    case invalidRuntimeVersion
    case invalidObservationDate
    case invalidSessionState
    case lastErrorTooLarge

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "虚拟网卡状态版本不受支持：\(version)"
        case .incompatibleProtocol(let version):
            "虚拟网卡服务协议不兼容：\(version)"
        case .invalidRuntimeState(let state):
            "虚拟网卡运行组件状态无效：\(state)"
        case .invalidSessionPhase(let phase):
            "虚拟网卡会话阶段无效：\(phase)"
        case .invalidRoutingMode(let mode):
            "虚拟网卡路由模式无效：\(mode)"
        case .invalidRuntimeVersion:
            "虚拟网卡运行组件版本无效"
        case .invalidObservationDate:
            "虚拟网卡状态时间无效"
        case .invalidSessionState:
            "虚拟网卡会话状态不一致"
        case .lastErrorTooLarge:
            "虚拟网卡状态错误信息过长"
        }
    }
}

/// Immutable point-in-time state returned by the helper. A snapshot reports
/// observed state only; feature bits never imply that an operation succeeded.
public final class TunHelperStatusSnapshot: NSObject, NSSecureCoding, @unchecked Sendable {
    public static let currentSchemaVersion = 1
    public static var supportsSecureCoding: Bool { true }

    private static let maximumRuntimeVersionBytes = 128
    private static let maximumLastErrorBytes = 4_096

    public let schemaVersion: Int
    public let protocolVersion: Int
    public let implementationVersion: Int
    public let supportedFeatures: UInt64
    public let runtimeState: TunPrivilegedRuntimeState
    public let runtimeVersion: String?
    public let sessionPhase: TunHelperSessionPhase
    public let sessionIdentifier: UUID?
    public let sessionOwnedByCaller: Bool
    public let recoveryRequired: Bool
    public let routingMode: TunHelperRoutingMode?
    public let observedAt: Date
    public let lastError: String?

    public var features: TunHelperFeature {
        TunHelperFeature(rawValue: supportedFeatures)
    }

    public init(
        schemaVersion: Int = TunHelperStatusSnapshot.currentSchemaVersion,
        protocolVersion: Int = TunHelperConstants.protocolVersion,
        implementationVersion: Int = TunHelperConstants.implementationVersion,
        supportedFeatures: UInt64,
        runtimeState: TunPrivilegedRuntimeState,
        runtimeVersion: String?,
        sessionPhase: TunHelperSessionPhase,
        sessionIdentifier: UUID?,
        sessionOwnedByCaller: Bool,
        recoveryRequired: Bool,
        routingMode: TunHelperRoutingMode?,
        observedAt: Date = Date(),
        lastError: String?
    ) throws {
        try Self.validate(
            schemaVersion: schemaVersion,
            protocolVersion: protocolVersion,
            runtimeState: runtimeState,
            runtimeVersion: runtimeVersion,
            sessionPhase: sessionPhase,
            sessionIdentifier: sessionIdentifier,
            sessionOwnedByCaller: sessionOwnedByCaller,
            recoveryRequired: recoveryRequired,
            routingMode: routingMode,
            observedAt: observedAt,
            lastError: lastError
        )
        self.schemaVersion = schemaVersion
        self.protocolVersion = protocolVersion
        self.implementationVersion = implementationVersion
        self.supportedFeatures = supportedFeatures
        self.runtimeState = runtimeState
        self.runtimeVersion = runtimeVersion
        self.sessionPhase = sessionPhase
        self.sessionIdentifier = sessionIdentifier
        self.sessionOwnedByCaller = sessionOwnedByCaller
        self.recoveryRequired = recoveryRequired
        self.routingMode = routingMode
        self.observedAt = observedAt
        self.lastError = lastError
        super.init()
    }

    public required init?(coder: NSCoder) {
        let schemaVersion = coder.decodeInteger(forKey: CodingKey.schemaVersion)
        let protocolVersion = coder.decodeInteger(forKey: CodingKey.protocolVersion)
        let implementationVersion = coder.decodeInteger(
            forKey: CodingKey.implementationVersion
        )
        let supportedFeatures = UInt64(
            bitPattern: coder.decodeInt64(forKey: CodingKey.supportedFeatures)
        )
        let runtimeStateRawValue = coder.decodeInteger(forKey: CodingKey.runtimeState)
        let sessionPhaseRawValue = coder.decodeInteger(forKey: CodingKey.sessionPhase)
        let sessionOwnedByCaller = coder.decodeBool(forKey: CodingKey.sessionOwnedByCaller)
        let recoveryRequired = coder.decodeBool(forKey: CodingKey.recoveryRequired)

        guard
            let runtimeState = TunPrivilegedRuntimeState(rawValue: runtimeStateRawValue),
            let sessionPhase = TunHelperSessionPhase(rawValue: sessionPhaseRawValue),
            let observedAt = coder.decodeObject(
                of: NSDate.self,
                forKey: CodingKey.observedAt
            ) as Date?
        else { return nil }

        let runtimeVersion =
            coder.decodeObject(
                of: NSString.self,
                forKey: CodingKey.runtimeVersion
            ) as String?
        let sessionIdentifier =
            coder.decodeObject(
                of: NSUUID.self,
                forKey: CodingKey.sessionIdentifier
            ) as UUID?
        let lastError =
            coder.decodeObject(
                of: NSString.self,
                forKey: CodingKey.lastError
            ) as String?

        let routingMode: TunHelperRoutingMode?
        if coder.containsValue(forKey: CodingKey.routingMode) {
            guard
                let decoded = TunHelperRoutingMode(
                    rawValue: coder.decodeInteger(forKey: CodingKey.routingMode)
                )
            else { return nil }
            routingMode = decoded
        } else {
            routingMode = nil
        }

        guard
            (try? Self.validate(
                schemaVersion: schemaVersion,
                protocolVersion: protocolVersion,
                runtimeState: runtimeState,
                runtimeVersion: runtimeVersion,
                sessionPhase: sessionPhase,
                sessionIdentifier: sessionIdentifier,
                sessionOwnedByCaller: sessionOwnedByCaller,
                recoveryRequired: recoveryRequired,
                routingMode: routingMode,
                observedAt: observedAt,
                lastError: lastError
            )) != nil
        else { return nil }

        self.schemaVersion = schemaVersion
        self.protocolVersion = protocolVersion
        self.implementationVersion = implementationVersion
        self.supportedFeatures = supportedFeatures
        self.runtimeState = runtimeState
        self.runtimeVersion = runtimeVersion
        self.sessionPhase = sessionPhase
        self.sessionIdentifier = sessionIdentifier
        self.sessionOwnedByCaller = sessionOwnedByCaller
        self.recoveryRequired = recoveryRequired
        self.routingMode = routingMode
        self.observedAt = observedAt
        self.lastError = lastError
        super.init()
    }

    public func encode(with coder: NSCoder) {
        coder.encode(schemaVersion, forKey: CodingKey.schemaVersion)
        coder.encode(protocolVersion, forKey: CodingKey.protocolVersion)
        coder.encode(implementationVersion, forKey: CodingKey.implementationVersion)
        coder.encode(Int64(bitPattern: supportedFeatures), forKey: CodingKey.supportedFeatures)
        coder.encode(runtimeState.rawValue, forKey: CodingKey.runtimeState)
        coder.encode(runtimeVersion as NSString?, forKey: CodingKey.runtimeVersion)
        coder.encode(sessionPhase.rawValue, forKey: CodingKey.sessionPhase)
        coder.encode(sessionIdentifier as NSUUID?, forKey: CodingKey.sessionIdentifier)
        coder.encode(sessionOwnedByCaller, forKey: CodingKey.sessionOwnedByCaller)
        coder.encode(recoveryRequired, forKey: CodingKey.recoveryRequired)
        if let routingMode {
            coder.encode(routingMode.rawValue, forKey: CodingKey.routingMode)
        }
        coder.encode(observedAt as NSDate, forKey: CodingKey.observedAt)
        coder.encode(lastError as NSString?, forKey: CodingKey.lastError)
    }

    public func validate() throws {
        try Self.validate(
            schemaVersion: schemaVersion,
            protocolVersion: protocolVersion,
            runtimeState: runtimeState,
            runtimeVersion: runtimeVersion,
            sessionPhase: sessionPhase,
            sessionIdentifier: sessionIdentifier,
            sessionOwnedByCaller: sessionOwnedByCaller,
            recoveryRequired: recoveryRequired,
            routingMode: routingMode,
            observedAt: observedAt,
            lastError: lastError
        )
    }

    private static func validate(
        schemaVersion: Int,
        protocolVersion: Int,
        runtimeState: TunPrivilegedRuntimeState,
        runtimeVersion: String?,
        sessionPhase: TunHelperSessionPhase,
        sessionIdentifier: UUID?,
        sessionOwnedByCaller: Bool,
        recoveryRequired: Bool,
        routingMode: TunHelperRoutingMode?,
        observedAt: Date,
        lastError: String?
    ) throws {
        guard schemaVersion == currentSchemaVersion else {
            throw TunHelperStatusSnapshotError.unsupportedSchemaVersion(schemaVersion)
        }
        guard protocolVersion == TunHelperConstants.protocolVersion else {
            throw TunHelperStatusSnapshotError.incompatibleProtocol(protocolVersion)
        }
        if let runtimeVersion {
            let bytes = Array(runtimeVersion.utf8)
            guard
                !bytes.isEmpty,
                bytes.count <= maximumRuntimeVersionBytes,
                bytes.allSatisfy({ byte in
                    (48...57).contains(byte) || (65...90).contains(byte)
                        || (97...122).contains(byte) || byte == 45 || byte == 46
                })
            else {
                throw TunHelperStatusSnapshotError.invalidRuntimeVersion
            }
        }
        if runtimeState == .ready, runtimeVersion == nil {
            throw TunHelperStatusSnapshotError.invalidRuntimeVersion
        }
        guard observedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw TunHelperStatusSnapshotError.invalidObservationDate
        }
        if let lastError, lastError.utf8.count > maximumLastErrorBytes {
            throw TunHelperStatusSnapshotError.lastErrorTooLarge
        }

        if !sessionOwnedByCaller,
            sessionIdentifier != nil || routingMode != nil || lastError != nil
        {
            throw TunHelperStatusSnapshotError.invalidSessionState
        }
        if sessionPhase == .inactive {
            guard
                sessionIdentifier == nil,
                !sessionOwnedByCaller,
                routingMode == nil,
                !recoveryRequired
            else {
                throw TunHelperStatusSnapshotError.invalidSessionState
            }
        } else if sessionOwnedByCaller, sessionIdentifier == nil {
            throw TunHelperStatusSnapshotError.invalidSessionState
        }
        guard (sessionPhase == .recoveryRequired) == recoveryRequired else {
            throw TunHelperStatusSnapshotError.invalidSessionState
        }
    }

    private enum CodingKey {
        static let schemaVersion = "schemaVersion"
        static let protocolVersion = "protocolVersion"
        static let implementationVersion = "implementationVersion"
        static let supportedFeatures = "supportedFeatures"
        static let runtimeState = "runtimeState"
        static let runtimeVersion = "runtimeVersion"
        static let sessionPhase = "sessionPhase"
        static let sessionIdentifier = "sessionIdentifier"
        static let sessionOwnedByCaller = "sessionOwnedByCaller"
        static let recoveryRequired = "recoveryRequired"
        static let routingMode = "routingMode"
        static let observedAt = "observedAt"
        static let lastError = "lastError"
    }
}

/// The privileged surface is deliberately fixed and path-free. It must never
/// accept executable/config/home paths, argv, environment, shell input, or a
/// caller-selected utun device.
@objc public protocol TunHelperXPCProtocol {
    /// Permanent v1-compatible selector. Never change its Objective-C shape.
    func probe(
        reply:
            @escaping (
                _ protocolVersion: Int,
                _ implementationVersion: Int,
                _ supportedFeatures: UInt64,
                _ recoveryPending: Bool,
                _ error: NSError?
            ) -> Void
    )

    func status(
        reply: @escaping (_ snapshot: TunHelperStatusSnapshot?, _ error: NSError?) -> Void
    )

    func installOrRepairRuntime(
        reply: @escaping (_ snapshot: TunHelperStatusSnapshot?, _ error: NSError?) -> Void
    )

    func startSession(
        configuration: TunConfigurationEnvelope,
        reply: @escaping (_ snapshot: TunHelperStatusSnapshot?, _ error: NSError?) -> Void
    )

    func stopSession(
        reply: @escaping (_ snapshot: TunHelperStatusSnapshot?, _ error: NSError?) -> Void
    )

    func setRoutingMode(
        _ routingMode: TunHelperRoutingMode,
        reply: @escaping (_ snapshot: TunHelperStatusSnapshot?, _ error: NSError?) -> Void
    )

    func recover(
        reply: @escaping (_ snapshot: TunHelperStatusSnapshot?, _ error: NSError?) -> Void
    )
}

/// Builds the only NSXPC interface used by both endpoints and explicitly
/// declares every complex class crossing the process boundary.
public enum TunHelperXPCInterfaceFactory {
    public static func make() -> NSXPCInterface {
        let interface = NSXPCInterface(with: TunHelperXPCProtocol.self)

        let envelopeClasses = classSet([
            TunConfigurationEnvelope.self,
            NSData.self,
            NSString.self,
        ])
        interface.setClasses(
            envelopeClasses,
            for: #selector(TunHelperXPCProtocol.startSession(configuration:reply:)),
            argumentIndex: 0,
            ofReply: false
        )

        let snapshotClasses = classSet([
            TunHelperStatusSnapshot.self,
            NSDate.self,
            NSUUID.self,
            NSString.self,
        ])
        let errorClasses = classSet([
            NSError.self,
            NSDictionary.self,
            NSString.self,
            NSNumber.self,
        ])
        interface.setClasses(
            errorClasses,
            for: #selector(TunHelperXPCProtocol.probe(reply:)),
            argumentIndex: 4,
            ofReply: true
        )
        for selector in replySelectors {
            interface.setClasses(
                snapshotClasses,
                for: selector,
                argumentIndex: 0,
                ofReply: true
            )
            interface.setClasses(
                errorClasses,
                for: selector,
                argumentIndex: 1,
                ofReply: true
            )
        }
        return interface
    }

    private static func classSet(_ classes: [AnyClass]) -> Set<AnyHashable> {
        // Foundation imports the Objective-C NSSet<Class> API as
        // Set<AnyHashable>, so bridge through NSSet to preserve Class values.
        NSSet(array: classes) as! Set<AnyHashable>
    }

    private static let replySelectors: [Selector] = [
        #selector(TunHelperXPCProtocol.status(reply:)),
        #selector(TunHelperXPCProtocol.installOrRepairRuntime(reply:)),
        #selector(TunHelperXPCProtocol.startSession(configuration:reply:)),
        #selector(TunHelperXPCProtocol.stopSession(reply:)),
        #selector(TunHelperXPCProtocol.setRoutingMode(_:reply:)),
        #selector(TunHelperXPCProtocol.recover(reply:)),
    ]
}

public enum TunHelperRemoteError {
    public static func backendUnavailable() -> NSError {
        NSError(
            domain: TunHelperConstants.errorDomain,
            code: TunHelperErrorCode.backendUnavailable.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "虚拟网卡后端尚不可用，未执行任何系统修改"
            ]
        )
    }

    public static func invalidConfigurationEnvelope(_ error: any Error) -> NSError {
        NSError(
            domain: TunHelperConstants.errorDomain,
            code: TunHelperErrorCode.invalidConfigurationEnvelope.rawValue,
            userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
        )
    }

    public static func invalidRoutingMode() -> NSError {
        NSError(
            domain: TunHelperConstants.errorDomain,
            code: TunHelperErrorCode.invalidRoutingMode.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "虚拟网卡路由模式无效"]
        )
    }

    public static func operationFailed(
        _ error: any Error,
        code: TunHelperErrorCode = .operationFailed
    ) -> NSError {
        NSError(
            domain: TunHelperConstants.errorDomain,
            code: code.rawValue,
            userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
        )
    }
}

public enum TunHelperClientError: LocalizedError, Equatable, Sendable {
    case incompatibleProtocol(expected: Int, actual: Int)
    case invalidRemoteObject
    case invalidStatusSnapshot
    case timedOut
    case operationOutcomeUnknown

    public var errorDescription: String? {
        switch self {
        case .incompatibleProtocol(let expected, let actual):
            "虚拟网卡服务协议不兼容（需要 \(expected)，实际 \(actual)）"
        case .invalidRemoteObject:
            "无法连接虚拟网卡服务"
        case .invalidStatusSnapshot:
            "虚拟网卡服务返回了无效状态"
        case .timedOut:
            "虚拟网卡服务响应超时"
        case .operationOutcomeUnknown:
            "虚拟网卡服务未能确认操作结果，请刷新状态后再重试"
        }
    }
}
