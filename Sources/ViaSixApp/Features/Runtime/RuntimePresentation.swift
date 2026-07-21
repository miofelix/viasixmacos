import Foundation

enum RuntimePresentation {
    static func byteCount(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .binary)
    }

    static func speed(_ value: Int64) -> String {
        "\(byteCount(value))/s"
    }

    static func delay(_ value: Int?) -> String {
        guard let value else { return "—" }
        if value == 0 { return "超时" }
        guard value > 0 else { return "—" }
        return "\(value) ms"
    }

    static func providerTimestamp(_ value: String?) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else { return "未知时间" }
        guard let date = date(value) else { return value }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func connectionTimestamp(_ value: String?) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else { return "未知时间" }
        guard let date = date(value) else { return value }
        return date.formatted(date: .abbreviated, time: .standard)
    }

    static func connectionDuration(start: String?, end: Date) -> String {
        guard let startDate = date(start) else { return "未知" }
        let totalSeconds = max(0, Int(end.timeIntervalSince(startDate)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 { return "\(hours) 小时 \(minutes) 分" }
        if minutes > 0 { return "\(minutes) 分 \(seconds) 秒" }
        return "\(seconds) 秒"
    }

    static func date(_ value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else { return nil }
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standardFormatter = ISO8601DateFormatter()
        return fractionalFormatter.date(from: value) ?? standardFormatter.date(from: value)
    }

    static func subscriptionExpiry(_ value: Int64) -> String {
        guard value > 0 else { return "未提供到期时间" }
        let date = Date(timeIntervalSince1970: TimeInterval(value))
        let prefix = date < Date() ? "已过期" : "到期"
        return "\(prefix) \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}
