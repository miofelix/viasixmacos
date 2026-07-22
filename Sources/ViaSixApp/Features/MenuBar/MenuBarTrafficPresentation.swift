import Foundation
import ViaSixCore

/// Pure presentation helpers for menu bar traffic text.
enum MenuBarTrafficPresentation {
    static func speedTitle(
        isProxyRunning: Bool,
        snapshot: TrafficSnapshot
    ) -> String? {
        guard isProxyRunning else { return nil }
        return ByteRateFormatter.menuBarSpeedTitle(up: snapshot.up, down: snapshot.down)
    }

    static func menuSummary(
        isProxyRunning: Bool,
        snapshot: TrafficSnapshot
    ) -> String? {
        guard isProxyRunning else { return nil }
        let up = ByteRateFormatter.formatRate(snapshot.up)
        let down = ByteRateFormatter.formatRate(snapshot.down)
        return "↑ \(up)  ↓ \(down)"
    }
}
