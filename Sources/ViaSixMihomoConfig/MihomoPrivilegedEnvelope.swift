import Foundation

public struct MihomoPrivilegedRuntimePlan: Equatable, Sendable {
    public let configuration: Data
    public let options: MihomoRuntimeOptions

    public init(configuration: Data, options: MihomoRuntimeOptions) {
        self.configuration = configuration
        self.options = options
    }
}

/// A versioned, binary-property-list transport for the already-sanitized
/// privileged Mihomo plan. The payload is not runnable Mihomo YAML: the helper
/// must decode it, repeat the privileged allowlist projection, and generate a
/// fresh runtime document before validation or launch.
public enum MihomoPrivilegedEnvelope {
    public static let schemaVersion = 1
    public static let maximumBytes = 8 * 1_024 * 1_024

    public static func encode(
        server: MihomoServerConfiguration?,
        options: MihomoRuntimeOptions,
        replacingPrimaryServerWith address: String? = nil
    ) throws -> Data {
        try validateCanonicalOptions(options)
        let runtime = try MihomoServerConfiguration.runtimeConfiguration(
            server: server,
            options: options,
            projection: .privilegedTun,
            replacingPrimaryServerWith: address
        )
        let wire = try wireEnvelope(runtime: runtime, options: options)
        let data = try encoded(wire)
        guard data.count <= maximumBytes else {
            throw MihomoConfigurationError.privilegedEnvelopeTooLarge(data.count)
        }
        return data
    }

    public static func decodeRuntimeConfiguration(from data: Data) throws -> Data {
        try decodeRuntimePlan(from: data).configuration
    }

    public static func decodeRuntimePlan(from data: Data) throws -> MihomoPrivilegedRuntimePlan {
        guard data.count <= maximumBytes else {
            throw MihomoConfigurationError.privilegedEnvelopeTooLarge(data.count)
        }
        guard data.starts(with: Data("bplist00".utf8)) else {
            throw MihomoConfigurationError.invalidPrivilegedEnvelope
        }
        let receivedRoot = try propertyListRoot(from: data)
        try validatePropertyListComplexity(receivedRoot)

        if let version = receivedRoot["schemaVersion"] as? NSNumber,
            CFGetTypeID(version) != CFBooleanGetTypeID(),
            version.intValue != schemaVersion
        {
            throw MihomoConfigurationError.unsupportedPrivilegedEnvelopeVersion(
                version.intValue
            )
        }

        let wire: WireEnvelope
        do {
            wire = try PropertyListDecoder().decode(WireEnvelope.self, from: data)
        } catch {
            throw MihomoConfigurationError.invalidPrivilegedEnvelope
        }
        let canonicalRoot = try propertyListRoot(from: encoded(wire))
        guard receivedRoot.isEqual(canonicalRoot) else {
            throw MihomoConfigurationError.nonCanonicalPrivilegedEnvelope
        }
        guard wire.schemaVersion == schemaVersion else {
            throw MihomoConfigurationError.invalidPrivilegedEnvelope
        }
        try validateCanonicalOptions(wire.options)

        var remainingNodes = PrivilegedEnvelopeLimit.nodes
        let serverMapping = try wire.server.foundationMapping(
            depth: 0,
            remainingNodes: &remainingNodes
        )
        let server: MihomoServerConfiguration?
        if wire.options.routingMode == .direct || serverMapping.isEmpty {
            server = nil
        } else {
            server = try MihomoServerConfiguration(
                data: MihomoYAML.data(from: serverMapping)
            )
        }

        let runtime = try MihomoServerConfiguration.runtimeConfiguration(
            server: server,
            options: wire.options,
            projection: .privilegedTun
        )
        let canonical = try wireEnvelope(runtime: runtime, options: wire.options)
        guard canonical == wire else {
            throw MihomoConfigurationError.nonCanonicalPrivilegedEnvelope
        }
        return MihomoPrivilegedRuntimePlan(
            configuration: runtime,
            options: wire.options
        )
    }

    private static func encoded(_ wire: WireEnvelope) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        do {
            return try encoder.encode(wire)
        } catch {
            throw MihomoConfigurationError.invalidPrivilegedEnvelope
        }
    }

    private static func propertyListRoot(from data: Data) throws -> NSDictionary {
        var format = PropertyListSerialization.PropertyListFormat.binary
        let root: Any
        do {
            root = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: &format
            )
        } catch {
            throw MihomoConfigurationError.invalidPrivilegedEnvelope
        }
        guard format == .binary, let root = root as? NSDictionary else {
            throw MihomoConfigurationError.invalidPrivilegedEnvelope
        }
        return root
    }

    private static func validatePropertyListComplexity(_ root: NSDictionary) throws {
        var remainingNodes = PrivilegedEnvelopeLimit.nodes
        var pending: [(value: Any, depth: Int)] = [(root, 0)]

        while let node = pending.popLast() {
            guard node.depth <= PrivilegedEnvelopeLimit.depth else {
                throw MihomoConfigurationError.configurationTooDeep
            }
            remainingNodes -= 1
            guard remainingNodes >= 0 else {
                throw MihomoConfigurationError.configurationTooComplex
            }

            if let mapping = node.value as? NSDictionary {
                for (key, value) in mapping {
                    guard key is String else {
                        throw MihomoConfigurationError.invalidPrivilegedEnvelope
                    }
                    pending.append((value, node.depth + 1))
                }
            } else if let values = node.value as? NSArray {
                for value in values {
                    pending.append((value, node.depth + 1))
                }
            }
        }
    }

    private static let retainedServerKeys = [
        "proxies",
        "proxy-providers",
        "proxy-groups",
        "rules",
        "rule-providers",
        "sub-rules",
    ]

    private static func wireEnvelope(
        runtime: Data,
        options: MihomoRuntimeOptions
    ) throws -> WireEnvelope {
        let root = try MihomoYAML.mapping(from: runtime)
        var server: [String: WireValue] = [:]
        for key in retainedServerKeys {
            if let value = root[key] {
                server[key] = try WireValue(foundationValue: value)
            }
        }
        return WireEnvelope(
            schemaVersion: schemaVersion,
            options: options,
            server: server
        )
    }

    private static func validateCanonicalOptions(_ options: MihomoRuntimeOptions) throws {
        let normalizedHost = options.listenAddress
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalizedHost == options.listenAddress else {
            throw MihomoConfigurationError.nonCanonicalPrivilegedEnvelope
        }
        if let tun = options.tun {
            for route in tun.routeExcludeAddresses {
                guard route == route.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    throw MihomoConfigurationError.nonCanonicalPrivilegedEnvelope
                }
            }
        }
    }
}

private struct WireEnvelope: Codable, Equatable {
    let schemaVersion: Int
    let options: MihomoRuntimeOptions
    let server: [String: WireValue]
}

private enum PrivilegedEnvelopeLimit {
    static let depth = 64
    static let nodes = 200_000
}

private enum WireValue: Codable, Equatable {
    case string(String)
    case integer(Int)
    case boolean(Bool)
    case array([Self])
    case mapping([String: Self])

    init(foundationValue value: Any) throws {
        switch value {
        case let value as String:
            self = .string(value)
        case let value as Bool:
            self = .boolean(value)
        case let value as Int:
            self = .integer(value)
        case let value as [Any]:
            self = .array(try value.map(Self.init(foundationValue:)))
        case let value as [String: Any]:
            self = .mapping(try value.mapValues(Self.init(foundationValue:)))
        default:
            throw MihomoConfigurationError.invalidPrivilegedEnvelope
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([Self].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: Self].self) {
            self = .mapping(value)
        } else {
            throw MihomoConfigurationError.invalidPrivilegedEnvelope
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .boolean(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .mapping(let value):
            try container.encode(value)
        }
    }

    func foundationValue(
        depth: Int,
        remainingNodes: inout Int
    ) throws -> Any {
        guard depth <= PrivilegedEnvelopeLimit.depth else {
            throw MihomoConfigurationError.configurationTooDeep
        }
        remainingNodes -= 1
        guard remainingNodes >= 0 else {
            throw MihomoConfigurationError.configurationTooComplex
        }
        switch self {
        case .string(let value):
            return value
        case .integer(let value):
            return value
        case .boolean(let value):
            return value
        case .array(let values):
            return try values.map {
                try $0.foundationValue(
                    depth: depth + 1,
                    remainingNodes: &remainingNodes
                )
            }
        case .mapping(let values):
            var result: [String: Any] = [:]
            result.reserveCapacity(values.count)
            for (key, value) in values {
                result[key] = try value.foundationValue(
                    depth: depth + 1,
                    remainingNodes: &remainingNodes
                )
            }
            return result
        }
    }
}

private extension Dictionary where Key == String, Value == WireValue {
    func foundationMapping(
        depth: Int,
        remainingNodes: inout Int
    ) throws -> [String: Any] {
        var result: [String: Any] = [:]
        result.reserveCapacity(count)
        for (key, value) in self {
            result[key] = try value.foundationValue(
                depth: depth + 1,
                remainingNodes: &remainingNodes
            )
        }
        return result
    }
}
