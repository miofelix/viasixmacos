import Foundation

public struct SpeedTestResult: Codable, Equatable, Identifiable, Sendable {
    public let ip: String
    public let sent: String
    public let received: String
    public let loss: String
    public let latency: String
    public let speed: String
    public let region: String

    public init(
        ip: String,
        sent: String = "",
        received: String = "",
        loss: String = "",
        latency: String = "",
        speed: String = "",
        region: String = ""
    ) {
        self.ip = ip
        self.sent = sent
        self.received = received
        self.loss = loss
        self.latency = latency
        self.speed = speed
        self.region = region
    }

    public var id: String { ip }
    public var latencyValue: Double? { Double(latency.trimmingCharacters(in: .whitespacesAndNewlines)) }
    public var speedValue: Double? { Double(speed.trimmingCharacters(in: .whitespacesAndNewlines)) }
    public var lossValue: Double? { Double(loss.trimmingCharacters(in: .whitespacesAndNewlines)) }
}

