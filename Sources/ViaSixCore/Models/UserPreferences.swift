import Foundation

public struct UserPreferences: Codable, Equatable, Sendable {
    public var parameters: SpeedTestParameters
    public var selectedIP: String
    public var cfstPath: String
    public var xrayPath: String

    public init(
        parameters: SpeedTestParameters,
        selectedIP: String = "",
        cfstPath: String = "",
        xrayPath: String = ""
    ) {
        self.parameters = parameters
        self.selectedIP = selectedIP
        self.cfstPath = cfstPath
        self.xrayPath = xrayPath
    }
}

