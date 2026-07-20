import Foundation

/// The three ways in which ViaSix can expose a proxy to the local Mac.
///
/// Keeping this as one value prevents contradictory persisted state such as
/// system proxy and virtual-interface mode both being enabled at once.
public enum NetworkAccessMode: String, Codable, CaseIterable, Sendable {
    case localProxy
    case systemProxy
    case virtualInterface

    public var displayName: String {
        switch self {
        case .localProxy: "本地代理"
        case .systemProxy: "系统代理"
        case .virtualInterface: "虚拟网卡"
        }
    }

    public var usesSystemProxy: Bool { self == .systemProxy }
    public var usesVirtualInterface: Bool { self == .virtualInterface }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")

        switch value {
        case "localproxy", "local": self = .localProxy
        case "systemproxy", "system": self = .systemProxy
        case "virtualinterface", "virtualnetworkinterface", "tun": self = .virtualInterface
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported network access mode: \(value)"
            )
        }
    }
}

/// A comparable Mihomo semantic version parsed from the core's own banner.
public struct MihomoRuntimeVersion: Codable, Comparable, Hashable, Sendable,
    CustomStringConvertible
{
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?

    public static let minimumSafe = Self(major: 1, minor: 19, patch: 29)

    public init(major: Int, minor: Int, patch: Int, prerelease: String? = nil) {
        precondition(major >= 0 && minor >= 0 && patch >= 0)
        self.major = major
        self.minor = minor
        self.patch = patch
        let normalized = prerelease?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.prerelease = normalized?.isEmpty == true ? nil : normalized
    }

    public init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.init(major: major, minor: minor, patch: patch)
    }

    /// Parses output such as `Mihomo Meta v1.19.29 darwin arm64 with go1.26.5`.
    /// Requiring the Mihomo product prefix prevents a later Go/toolchain
    /// version from being mistaken for the runtime version.
    public init?(text: String) {
        guard let parsed = Self.parse(text) else { return nil }
        self = parsed
    }

    public static func parse(_ text: String) -> Self? {
        let pattern = #"\bmihomo(?:\s+meta)?\s+v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?\b"#
        guard
            let expression = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            )
        else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        for match in expression.matches(in: text, range: range) {
            if let version = version(in: text, match: match) { return version }
        }
        return nil
    }

    public var description: String {
        let base = "\(major).\(minor).\(patch)"
        return prerelease.map { "\(base)-\($0)" } ?? base
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (nil, _): return false
        case (_, nil): return true
        case (let left?, let right?):
            return Self.comparePrerelease(left, right) < 0
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let version = Self.parseCanonical(value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid Mihomo runtime version: \(value)"
            )
        }
        self = version
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    private static func parseCanonical(_ text: String) -> Self? {
        let pattern = #"^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: range), match.range == range else {
            return nil
        }
        return version(in: text, match: match)
    }

    private static func version(
        in text: String,
        match: NSTextCheckingResult
    ) -> Self? {
        guard
            let major = integer(in: text, match: match, group: 1),
            let minor = integer(in: text, match: match, group: 2),
            let patch = integer(in: text, match: match, group: 3)
        else { return nil }

        var prerelease: String?
        if match.range(at: 4).location != NSNotFound,
            let valueRange = Range(match.range(at: 4), in: text)
        {
            prerelease = String(text[valueRange])
        }
        return Self(major: major, minor: minor, patch: patch, prerelease: prerelease)
    }

    private static func integer(
        in text: String,
        match: NSTextCheckingResult,
        group: Int
    ) -> Int? {
        guard let range = Range(match.range(at: group), in: text) else { return nil }
        return Int(text[range])
    }

    private static func comparePrerelease(_ lhs: String, _ rhs: String) -> Int {
        let leftParts = lhs.split(separator: ".", omittingEmptySubsequences: false)
        let rightParts = rhs.split(separator: ".", omittingEmptySubsequences: false)
        for index in 0..<max(leftParts.count, rightParts.count) {
            guard index < leftParts.count else { return -1 }
            guard index < rightParts.count else { return 1 }
            let left = leftParts[index]
            let right = rightParts[index]
            if left == right { continue }
            if let leftNumber = Int(left), let rightNumber = Int(right) {
                return leftNumber < rightNumber ? -1 : 1
            }
            if Int(left) != nil { return -1 }
            if Int(right) != nil { return 1 }
            return left < right ? -1 : 1
        }
        return 0
    }
}

/// Features that must be accounted for before a virtual interface can be
/// advertised as safe for ordinary users.
public struct VirtualInterfaceFeature: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let ipv4 = Self(rawValue: 1 << 0)
    public static let ipv6 = Self(rawValue: 1 << 1)
    public static let systemRouting = Self(rawValue: 1 << 2)
    public static let loopbackPrevention = Self(rawValue: 1 << 3)
    public static let dnsManagement = Self(rawValue: 1 << 4)
    public static let crashRecovery = Self(rawValue: 1 << 5)
    public static let networkChangeRecovery = Self(rawValue: 1 << 6)

    public static let all: Self = [
        .ipv4,
        .ipv6,
        .systemRouting,
        .loopbackPrevention,
        .dnsManagement,
        .crashRecovery,
        .networkChangeRecovery,
    ]

    /// Features required before ViaSix can advertise a user-facing
    /// full-traffic mode. A reversible macOS DNS manager remains required even
    /// when Mihomo receives DNS settings in its own configuration.
    public static let minimumSafe: Self = .all

    // Naming aliases keep the domain vocabulary clear at call sites.
    public static let systemRoutes = systemRouting
    public static let loopbackProtection = loopbackPrevention
}

public enum VirtualInterfaceUnavailableReason: Equatable, Hashable, Sendable {
    case runtimeMissing
    case runtimeTooOld(installed: MihomoRuntimeVersion?, minimum: MihomoRuntimeVersion)
    case helperUnavailable
    case permissionUnavailable
    case unsupportedBuild

    public var displayMessage: String {
        switch self {
        case .runtimeMissing:
            "虚拟网卡运行组件不可用"
        case .runtimeTooOld(let installed, let minimum):
            if let installed {
                "虚拟网卡需要 Mihomo \(minimum) 或更高版本（当前 \(installed)）"
            } else {
                "无法确认虚拟网卡所需的 Mihomo 版本"
            }
        case .helperUnavailable:
            "虚拟网卡服务尚未安装或不可用"
        case .permissionUnavailable:
            "没有启用虚拟网卡所需的系统权限"
        case .unsupportedBuild:
            "当前构建不支持虚拟网卡"
        }
    }
}

public struct VirtualInterfaceProbe: Equatable, Sendable {
    public let runtimeInstalled: Bool
    public let runtimeVersion: MihomoRuntimeVersion?
    public let helperAvailable: Bool
    public let permissionAvailable: Bool
    public let buildSupported: Bool
    public let supportedFeatures: VirtualInterfaceFeature
    public let requiredFeatures: VirtualInterfaceFeature

    public init(
        runtimeVersion: MihomoRuntimeVersion? = nil,
        runtimeInstalled: Bool? = nil,
        helperAvailable: Bool = false,
        permissionAvailable: Bool = false,
        buildSupported: Bool = true,
        // An empty default is intentional: a probe must explicitly attest to
        // every feature instead of accidentally advertising a guessed
        // capability.
        supportedFeatures: VirtualInterfaceFeature = [],
        requiredFeatures: VirtualInterfaceFeature = .minimumSafe
    ) {
        self.runtimeInstalled = runtimeInstalled ?? (runtimeVersion != nil)
        self.runtimeVersion = runtimeVersion
        self.helperAvailable = helperAvailable
        self.permissionAvailable = permissionAvailable
        self.buildSupported = buildSupported
        self.supportedFeatures = supportedFeatures
        self.requiredFeatures = requiredFeatures
    }

    public static let unsupportedBuild = Self(buildSupported: false)
}

public enum VirtualInterfaceCapability: Equatable, Hashable, Sendable {
    case unavailable(VirtualInterfaceUnavailableReason)
    case available(features: VirtualInterfaceFeature)

    public static let minimumSafeVersion = MihomoRuntimeVersion.minimumSafe

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    /// The only value UI code should use to decide whether to render an
    /// actionable virtual-interface control.
    public var isAvailableForUI: Bool { isAvailable }
    public var uiEnabled: Bool { isAvailable }

    public var features: VirtualInterfaceFeature {
        switch self {
        case .available(let features): features
        case .unavailable: []
        }
    }

    public var unavailableReason: VirtualInterfaceUnavailableReason? {
        guard case .unavailable(let reason) = self else { return nil }
        return reason
    }

    public static func evaluate(_ probe: VirtualInterfaceProbe) -> Self {
        guard probe.buildSupported else { return .unavailable(.unsupportedBuild) }
        guard probe.runtimeInstalled else { return .unavailable(.runtimeMissing) }

        guard let version = probe.runtimeVersion else {
            return .unavailable(.runtimeTooOld(installed: nil, minimum: minimumSafeVersion))
        }
        guard version >= minimumSafeVersion else {
            return .unavailable(.runtimeTooOld(installed: version, minimum: minimumSafeVersion))
        }
        guard probe.helperAvailable else { return .unavailable(.helperUnavailable) }
        guard probe.permissionAvailable else { return .unavailable(.permissionUnavailable) }
        // Callers may ask for additional capabilities, but they can never
        // weaken the baseline required for a user-facing full-traffic mode.
        let requiredFeatures = probe.requiredFeatures.union(.minimumSafe)
        guard probe.supportedFeatures.isSuperset(of: requiredFeatures) else {
            return .unavailable(.unsupportedBuild)
        }
        return .available(features: probe.supportedFeatures)
    }
}

public enum VirtualInterfaceStatus: Equatable, Sendable {
    case unavailable(VirtualInterfaceUnavailableReason)
    case disabled
    case preparing
    case enabling
    case enabled
    case disabling
    case failed(String)
}

public struct VirtualInterfaceConfiguration: Codable, Equatable, Sendable {
    public var mtu: UInt32
    public var features: VirtualInterfaceFeature

    public init(
        mtu: UInt32 = 1_500,
        features: VirtualInterfaceFeature = .minimumSafe
    ) {
        self.mtu = mtu
        self.features = features
    }

    public func validated() throws -> Self {
        guard (576...9_000).contains(mtu) else {
            throw VirtualInterfaceManagerError.invalidMTU(mtu)
        }
        guard features.isSuperset(of: .minimumSafe) else {
            throw VirtualInterfaceManagerError.missingRequiredFeatures(
                required: .minimumSafe,
                actual: features
            )
        }
        return self
    }
}

public enum VirtualInterfaceManagerError: LocalizedError, Equatable, Sendable {
    case unavailable(VirtualInterfaceUnavailableReason)
    case invalidMTU(UInt32)
    case missingRequiredFeatures(required: VirtualInterfaceFeature, actual: VirtualInterfaceFeature)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason): reason.displayMessage
        case .invalidMTU(let mtu): "虚拟网卡 MTU 无效：\(mtu)"
        case .missingRequiredFeatures(let required, let actual):
            "虚拟网卡缺少必需功能（需要 \(required.rawValue)，实际 \(actual.rawValue)）"
        }
    }
}

/// Platform boundary for a future privileged helper or Network Extension.
/// This protocol intentionally contains no shell, route, or packet APIs.
public protocol VirtualInterfaceManaging: Sendable {
    func probe() async -> VirtualInterfaceCapability
    func enable(configuration: VirtualInterfaceConfiguration) async throws
    func disable() async throws
    func recoverIfNeeded() async throws
    func status() async -> VirtualInterfaceStatus
}

public extension VirtualInterfaceManaging {
    func capability() async -> VirtualInterfaceCapability {
        await probe()
    }

    var isAvailableForUI: Bool {
        get async { await probe().isAvailableForUI }
    }
}

/// Safe default until a signed helper/Network Extension has been installed.
/// It never mutates the network. Enabling fails explicitly; cleanup methods
/// are idempotent no-ops so shutdown and crash recovery remain safe.
public actor UnavailableVirtualInterfaceManager: VirtualInterfaceManaging {
    public let reason: VirtualInterfaceUnavailableReason

    public init(reason: VirtualInterfaceUnavailableReason = .unsupportedBuild) {
        self.reason = reason
    }

    public func probe() async -> VirtualInterfaceCapability {
        .unavailable(reason)
    }

    public func enable(configuration: VirtualInterfaceConfiguration) async throws {
        _ = configuration
        throw VirtualInterfaceManagerError.unavailable(reason)
    }

    public func disable() async throws {}

    public func recoverIfNeeded() async throws {}

    public func status() async -> VirtualInterfaceStatus {
        .unavailable(reason)
    }
}
