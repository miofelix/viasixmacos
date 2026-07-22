import Foundation

public struct MihomoAPIConfiguration: Equatable, Sendable {
    public let host: String
    public let port: Int
    public let secret: String

    public init(host: String = "127.0.0.1", port: Int, secret: String) {
        self.host = host
        self.port = port
        self.secret = secret
    }

    public var displayAddress: String { "\(host):\(port)" }
}
