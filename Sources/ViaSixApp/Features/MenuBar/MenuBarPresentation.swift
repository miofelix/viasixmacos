import Foundation
import ViaSixCore

/// The menu bar should stay useful even when a speed test produced a large
/// result set. Keep the current selection visible and expose a bounded set of
/// candidates; the full table remains available from the Nodes page.
enum MenuBarNodePresentation {
    static let defaultVisibleLimit = 12

    static func visibleResults(
        from results: [SpeedTestResult],
        selectedIP: String,
        limit: Int = defaultVisibleLimit
    ) -> [SpeedTestResult] {
        guard limit > 0 else { return [] }

        let selected = selectedIP.trimmingCharacters(in: .whitespacesAndNewlines)
        var visible: [SpeedTestResult] = []
        var seen = Set<String>()

        func append(_ result: SpeedTestResult) {
            let ip = result.ip.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ip.isEmpty, !seen.contains(ip), visible.count < limit else { return }
            seen.insert(ip)
            visible.append(result)
        }

        if !selected.isEmpty {
            if let selectedResult = results.first(where: {
                $0.ip.trimmingCharacters(in: .whitespacesAndNewlines) == selected
            }) {
                append(selectedResult)
            } else {
                // A selected address can survive after a new result set is
                // loaded. Keep it actionable rather than silently hiding it.
                append(SpeedTestResult(ip: selected))
            }
        }

        for result in results {
            append(result)
        }
        return visible
    }

    static func hasAdditionalResults(
        in results: [SpeedTestResult],
        selectedIP: String,
        visibleLimit: Int = defaultVisibleLimit
    ) -> Bool {
        guard visibleLimit > 0 else { return !results.isEmpty }
        let allIPs = Set(
            results
                .map { $0.ip.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        let selected = selectedIP.trimmingCharacters(in: .whitespacesAndNewlines)
        let total = allIPs.union(selected.isEmpty ? [] : [selected]).count
        return total > visibleLimit
    }

    static func title(for result: SpeedTestResult) -> String {
        let ip = result.ip.trimmingCharacters(in: .whitespacesAndNewlines)
        let region = result.region.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !region.isEmpty else { return ip }
        return "\(region) · \(ip)"
    }
}
