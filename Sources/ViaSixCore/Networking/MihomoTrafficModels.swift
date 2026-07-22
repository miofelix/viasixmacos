import Foundation

/// Instantaneous Mihomo traffic rates from the `/traffic` WebSocket stream.
public struct TrafficSpeedSample: Equatable, Sendable, Codable {
    public var up: UInt64
    public var down: UInt64
    public var timestamp: Date

    public init(up: UInt64, down: UInt64, timestamp: Date = Date()) {
        self.up = up
        self.down = down
        self.timestamp = timestamp
    }

    private enum CodingKeys: String, CodingKey {
        case up, down
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.up = try Self.decodeUInt64(from: container, forKey: .up)
        self.down = try Self.decodeUInt64(from: container, forKey: .down)
        self.timestamp = Date()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(up, forKey: .up)
        try container.encode(down, forKey: .down)
    }

    private static func decodeUInt64(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> UInt64 {
        if let value = try? container.decode(UInt64.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int64.self, forKey: key), value >= 0 {
            return UInt64(value)
        }
        if let value = try? container.decode(Double.self, forKey: key),
            value.isFinite, value >= 0
        {
            return UInt64(value)
        }
        return 0
    }
}

/// Mihomo process memory usage from the `/memory` WebSocket stream.
public struct MihomoMemoryUsage: Equatable, Sendable, Codable {
    public var inuse: UInt64
    public var oslimit: UInt64?

    public init(inuse: UInt64, oslimit: UInt64? = nil) {
        self.inuse = inuse
        self.oslimit = oslimit
    }

    private enum CodingKeys: String, CodingKey {
        case inuse, oslimit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.inuse = try Self.decodeUInt64(from: container, forKey: .inuse) ?? 0
        self.oslimit = try Self.decodeUInt64(from: container, forKey: .oslimit)
    }

    private static func decodeUInt64(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> UInt64? {
        guard container.contains(key), try !container.decodeNil(forKey: key) else {
            return nil
        }
        if let value = try? container.decode(UInt64.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int64.self, forKey: key), value >= 0 {
            return UInt64(value)
        }
        if let value = try? container.decode(Double.self, forKey: key),
            value.isFinite, value >= 0
        {
            return UInt64(value)
        }
        return 0
    }
}

/// Latest traffic view for UI consumption.
public struct TrafficSnapshot: Equatable, Sendable {
    public var up: UInt64
    public var down: UInt64
    public var memoryInUse: UInt64
    public var points: [TrafficSpeedSample]
    public var isLive: Bool
    public var lastUpdated: Date?

    public init(
        up: UInt64 = 0,
        down: UInt64 = 0,
        memoryInUse: UInt64 = 0,
        points: [TrafficSpeedSample] = [],
        isLive: Bool = false,
        lastUpdated: Date? = nil
    ) {
        self.up = up
        self.down = down
        self.memoryInUse = memoryInUse
        self.points = points
        self.isLive = isLive
        self.lastUpdated = lastUpdated
    }

    public static let empty = TrafficSnapshot()
}
