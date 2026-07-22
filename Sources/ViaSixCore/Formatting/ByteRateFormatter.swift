import Foundation

/// Formats byte counts and rates for traffic UI, aligned with Clash Verge conventions.
public enum ByteRateFormatter {
    private static let units = ["B", "KB", "MB", "GB", "TB", "PB"]
    private static let shortUnits = ["B", "K", "M", "G", "T", "P"]
    /// Promote when the display value would round to four digits (or more).
    private static let displayThreshold: Double = 1_000

    /// Returns `(value, unit)` for a byte count, e.g. `("1.23", "MB")`.
    public static func parseBytes(_ bytes: UInt64) -> (value: String, unit: String) {
        parse(Double(bytes), units: units, suffix: "")
    }

    /// Formats a byte count, e.g. `"1.23 MB"`.
    public static func formatBytes(_ bytes: UInt64) -> String {
        let parsed = parseBytes(bytes)
        return "\(parsed.value) \(parsed.unit)"
    }

    /// Formats a rate in bytes/second for UI cards, e.g. `"1.23 MB/s"`.
    public static func formatRate(_ bytesPerSecond: UInt64) -> String {
        let parsed = parse(Double(bytesPerSecond), units: units, suffix: "/s")
        return "\(parsed.value) \(parsed.unit)"
    }

    /// Compact menu-bar rate, e.g. `"1.2M/s"` / `"999B/s"`.
    public static func formatCompactRate(_ bytesPerSecond: UInt64) -> String {
        let parsed = parse(Double(bytesPerSecond), units: shortUnits, suffix: "/s", compact: true)
        return "\(parsed.value)\(parsed.unit)"
    }

    /// Two-line, right-aligned menu bar title for upload then download.
    public static func menuBarSpeedTitle(up: UInt64, down: UInt64) -> String {
        let upText = padLeft(formatCompactRate(up), width: 7)
        let downText = padLeft(formatCompactRate(down), width: 7)
        return "\(upText)\n\(downText)"
    }

    private static func padLeft(_ text: String, width: Int) -> String {
        guard text.count < width else { return text }
        return String(repeating: " ", count: width - text.count) + text
    }

    private static func parse(
        _ amount: Double,
        units: [String],
        suffix: String,
        compact: Bool = false
    ) -> (value: String, unit: String) {
        guard amount.isFinite, amount >= 0 else {
            return ("0", units[0] + suffix)
        }

        if amount < displayThreshold {
            let value =
                compact
                ? String(Int(amount.rounded(.towardZero)))
                : String(Int(amount.rounded(.towardZero)))
            return (value, units[0] + suffix)
        }

        var unitIndex = min(Int(log2(max(amount, 1)) / 10), units.count - 1)
        var scaled = amount / pow(1_024, Double(unitIndex))

        if scaled.roundToDisplayPrecision() >= displayThreshold, unitIndex < units.count - 1 {
            unitIndex += 1
            scaled = amount / pow(1_024, Double(unitIndex))
        }

        let value: String
        if compact {
            if scaled < 9.95 {
                value = String(format: "%.1f", scaled)
            } else {
                value = String(format: "%.0f", scaled.rounded())
            }
        } else if scaled >= 100 {
            value = String(format: "%.0f", scaled.rounded())
        } else if scaled >= 10 {
            value = String(format: "%.1f", scaled)
        } else {
            value = String(format: "%.2f", scaled)
        }

        return (value, units[unitIndex] + suffix)
    }
}

private extension Double {
    func roundToDisplayPrecision() -> Double {
        (self * 10).rounded() / 10
    }
}
