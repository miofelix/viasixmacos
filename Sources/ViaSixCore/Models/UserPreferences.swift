import Foundation

public enum IPSourceMode: String, Codable, CaseIterable, Sendable {
    case ipv6
    case ipv4
    case file
    case range
}

public enum ExitIPDetectionMode: String, Codable, CaseIterable, Sendable {
    case automatic
    case ipv4
    case ipv6

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
    public var xrayPath: String
    public var exitIPEndpoint: String
    public var exitIPDetectionMode: ExitIPDetectionMode
    public var lastSuccessfulSpeedTestParameters: SpeedTestParameters?

    public init(
        parameters: SpeedTestParameters,
        ipSourceMode: IPSourceMode = .ipv6,
        selectedIP: String = "",
        cfstPath: String = "",
        xrayPath: String = "",
        exitIPEndpoint: String = AppMetadata.defaultExitIPEndpoint,
        exitIPDetectionMode: ExitIPDetectionMode = .automatic,
        lastSuccessfulSpeedTestParameters: SpeedTestParameters? = nil
    ) {
        self.parameters = parameters
        self.ipSourceMode = ipSourceMode
        self.selectedIP = selectedIP
        self.cfstPath = cfstPath
        self.xrayPath = xrayPath
        self.exitIPEndpoint = exitIPEndpoint
        self.exitIPDetectionMode = exitIPDetectionMode
        self.lastSuccessfulSpeedTestParameters = lastSuccessfulSpeedTestParameters
    }

    private enum CodingKeys: String, CodingKey {
        case parameters, ipSourceMode, selectedIP, cfstPath, xrayPath, exitIPEndpoint
        case exitIPDetectionMode, lastSuccessfulSpeedTestParameters
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            parameters: try values.decode(SpeedTestParameters.self, forKey: .parameters),
            ipSourceMode: try values.decodeIfPresent(IPSourceMode.self, forKey: .ipSourceMode) ?? .ipv6,
            selectedIP: try values.decodeIfPresent(String.self, forKey: .selectedIP) ?? "",
            cfstPath: try values.decodeIfPresent(String.self, forKey: .cfstPath) ?? "",
            xrayPath: try values.decodeIfPresent(String.self, forKey: .xrayPath) ?? "",
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
}
