import Foundation

enum RuntimeNetworkPolicy {
    static let downloadRequestTimeout: TimeInterval = 30
    static let downloadResourceTimeout: TimeInterval = 10 * 60

    static func makeSession(
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval,
        protocolClasses: [AnyClass]? = nil
    ) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.waitsForConnectivity = false
        if let protocolClasses {
            configuration.protocolClasses = protocolClasses
        }
        return URLSession(configuration: configuration)
    }
}
