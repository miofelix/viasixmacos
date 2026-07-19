import Foundation

public enum IPSourceMode: String, Codable, CaseIterable, Sendable {
    case ipv6
    case ipv4
    case file
    case range
}

public struct UserPreferences: Codable, Equatable, Sendable {
    public var parameters: SpeedTestParameters
    public var ipSourceMode: IPSourceMode
    public var selectedIP: String
    public var cfstPath: String
    public var xrayPath: String
    public var exitIPEndpoint: String

    public init(
        parameters: SpeedTestParameters,
        ipSourceMode: IPSourceMode = .ipv6,
        selectedIP: String = "",
        cfstPath: String = "",
        xrayPath: String = "",
        exitIPEndpoint: String = AppMetadata.defaultExitIPEndpoint
    ) {
        self.parameters = parameters
        self.ipSourceMode = ipSourceMode
        self.selectedIP = selectedIP
        self.cfstPath = cfstPath
        self.xrayPath = xrayPath
        self.exitIPEndpoint = exitIPEndpoint
    }

    private enum CodingKeys: String, CodingKey {
        case parameters, ipSourceMode, selectedIP, cfstPath, xrayPath, exitIPEndpoint
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
                ?? AppMetadata.defaultExitIPEndpoint
        )
    }
}
