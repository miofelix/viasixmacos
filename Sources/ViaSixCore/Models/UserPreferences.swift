import Foundation

public enum IPSourceMode: String, Codable, CaseIterable, Sendable {
    case ipv6
    case ipv4
    case file
    case range

    /// Preferences are persisted across app versions. Keep decoding tolerant
    /// of legacy spellings and values written by newer builds so one unknown
    /// field does not discard the user's other settings.
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch Self.normalized(value) {
        case "ipv6", "v6", "ip6", "builtinipv6":
            self = .ipv6
        case "ipv4", "v4", "ip4", "builtinipv4":
            self = .ipv4
        case "file", "customfile", "custom-file", "custom_file", "path":
            self = .file
        case "range", "cidr", "customrange", "custom-range", "custom_range":
            self = .range
        default:
            // The safest fallback is the bundled IPv6 list.  AppModel will
            // normalize its path during bootstrap.
            self = .ipv6
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

public enum ExitIPDetectionMode: String, Codable, CaseIterable, Sendable {
    case automatic
    case ipv4
    case ipv6

    /// Accepts common legacy spellings and safely falls back when a newer
    /// build writes an unknown mode.
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "automatic", "auto", "default":
            self = .automatic
        case "ipv4", "v4", "ip4":
            self = .ipv4
        case "ipv6", "v6", "ip6":
            self = .ipv6
        default:
            self = .automatic
        }
    }

    public var expectedAddressFamily: IPAddressFamily? {
        switch self {
        case .automatic: nil
        case .ipv4: .ipv4
        case .ipv6: .ipv6
        }
    }
}

public struct UserPreferences: Codable, Equatable, Sendable {
    public var parameters: SpeedTestParameters
    public var ipSourceMode: IPSourceMode
    public var selectedIP: String
    public var cfstPath: String
    public var mihomoPath: String
    public var exitIPEndpoint: String
    public var exitIPDetectionMode: ExitIPDetectionMode
    public var lastSuccessfulSpeedTestParameters: SpeedTestParameters?

    public init(
        parameters: SpeedTestParameters,
        ipSourceMode: IPSourceMode = .ipv6,
        selectedIP: String = "",
        cfstPath: String = "",
        mihomoPath: String = "",
        exitIPEndpoint: String = AppMetadata.defaultExitIPEndpoint,
        exitIPDetectionMode: ExitIPDetectionMode = .automatic,
        lastSuccessfulSpeedTestParameters: SpeedTestParameters? = nil
    ) {
        self.parameters = parameters
        self.ipSourceMode = ipSourceMode
        self.selectedIP = selectedIP
        self.cfstPath = cfstPath
        self.mihomoPath = mihomoPath
        self.exitIPEndpoint = exitIPEndpoint
        self.exitIPDetectionMode = exitIPDetectionMode
        self.lastSuccessfulSpeedTestParameters = lastSuccessfulSpeedTestParameters
    }

    private enum CodingKeys: String, CodingKey {
        case parameters, ipSourceMode, selectedIP, cfstPath, mihomoPath, exitIPEndpoint
        case exitIPDetectionMode, lastSuccessfulSpeedTestParameters
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            parameters: try values.decode(SpeedTestParameters.self, forKey: .parameters),
            ipSourceMode: try values.decodeIfPresent(IPSourceMode.self, forKey: .ipSourceMode) ?? .ipv6,
            selectedIP: try values.decodeIfPresent(String.self, forKey: .selectedIP) ?? "",
            cfstPath: try values.decodeIfPresent(String.self, forKey: .cfstPath) ?? "",
            mihomoPath: try values.decodeIfPresent(String.self, forKey: .mihomoPath) ?? "",
            exitIPEndpoint: try values.decodeIfPresent(String.self, forKey: .exitIPEndpoint)
                ?? AppMetadata.defaultExitIPEndpoint,
            exitIPDetectionMode: try values.decodeIfPresent(
                ExitIPDetectionMode.self,
                forKey: .exitIPDetectionMode
            ) ?? .automatic,
            lastSuccessfulSpeedTestParameters: try values.decodeIfPresent(
                SpeedTestParameters.self,
                forKey: .lastSuccessfulSpeedTestParameters
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(parameters, forKey: .parameters)
        try values.encode(ipSourceMode, forKey: .ipSourceMode)
        try values.encode(selectedIP, forKey: .selectedIP)
        try values.encode(cfstPath, forKey: .cfstPath)
        try values.encode(mihomoPath, forKey: .mihomoPath)
        try values.encode(exitIPEndpoint, forKey: .exitIPEndpoint)
        try values.encode(exitIPDetectionMode, forKey: .exitIPDetectionMode)
        try values.encodeIfPresent(
            lastSuccessfulSpeedTestParameters,
            forKey: .lastSuccessfulSpeedTestParameters
        )
    }

}
