import Foundation
import Network
import ViaSixCore

enum NodeResultSortField: Hashable, Sendable {
    case ip
    case sent
    case received
    case loss
    case latency
    case speed
    case region
}

struct NodeResultSortComparator: SortComparator {
    let field: NodeResultSortField
    var order: SortOrder

    init(_ field: NodeResultSortField, order: SortOrder = .forward) {
        self.field = field
        self.order = order
    }

    func compare(_ lhs: SpeedTestResult, _ rhs: SpeedTestResult) -> ComparisonResult {
        switch field {
        case .ip:
            compareIP(lhs.ip, rhs.ip)
        case .sent:
            compareNumeric(lhs.sent, rhs.sent)
        case .received:
            compareNumeric(lhs.received, rhs.received)
        case .loss:
            compareNumeric(lhs.loss, rhs.loss)
        case .latency:
            compareNumeric(lhs.latency, rhs.latency)
        case .speed:
            compareNumeric(lhs.speed, rhs.speed)
        case .region:
            compareText(lhs.region, rhs.region)
        }
    }

    private func compareNumeric(_ lhs: String, _ rhs: String) -> ComparisonResult {
        compareOptional(
            finiteDouble(lhs),
            finiteDouble(rhs),
            using: compareComparable
        )
    }

    private func compareText(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhs = normalized(lhs)
        let rhs = normalized(rhs)
        return compareOptional(
            lhs.isEmpty ? nil : lhs,
            rhs.isEmpty ? nil : rhs
        ) { lhs, rhs in
            lhs.compare(
                rhs,
                options: [.caseInsensitive, .diacriticInsensitive, .numeric],
                locale: Locale(identifier: "zh_Hans_CN")
            )
        }
    }

    private func compareIP(_ lhs: String, _ rhs: String) -> ComparisonResult {
        compareOptional(ipSortKey(lhs), ipSortKey(rhs)) { lhs, rhs in
            let familyComparison = compareComparable(lhs.familyRank, rhs.familyRank)
            guard familyComparison == .orderedSame else { return familyComparison }

            if lhs.bytes.lexicographicallyPrecedes(rhs.bytes) {
                return .orderedAscending
            }
            if rhs.bytes.lexicographicallyPrecedes(lhs.bytes) {
                return .orderedDescending
            }
            return .orderedSame
        }
    }

    /// Empty or malformed values stay at the bottom in both directions. This
    /// keeps incomplete rows from displacing useful measurements when a user
    /// asks for either the best or worst values.
    private func compareOptional<Value>(
        _ lhs: Value?,
        _ rhs: Value?,
        using comparison: (Value, Value) -> ComparisonResult
    ) -> ComparisonResult {
        switch (lhs, rhs) {
        case (.none, .none):
            return .orderedSame
        case (.none, .some):
            return .orderedDescending
        case (.some, .none):
            return .orderedAscending
        case (.some(let lhs), .some(let rhs)):
            return ordered(comparison(lhs, rhs))
        }
    }

    private func ordered(_ result: ComparisonResult) -> ComparisonResult {
        guard order == .reverse else { return result }
        switch result {
        case .orderedAscending:
            return .orderedDescending
        case .orderedDescending:
            return .orderedAscending
        case .orderedSame:
            return .orderedSame
        }
    }

    private func compareComparable<Value: Comparable>(
        _ lhs: Value,
        _ rhs: Value
    ) -> ComparisonResult {
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }

    private func finiteDouble(_ value: String) -> Double? {
        guard let value = Double(normalized(value)), value.isFinite else { return nil }
        return value
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func ipSortKey(_ value: String) -> IPSortKey? {
        let value = normalized(value)
        if let address = IPv4Address(value) {
            return IPSortKey(familyRank: 0, bytes: Array(address.rawValue))
        }
        if let address = IPv6Address(value) {
            return IPSortKey(familyRank: 1, bytes: Array(address.rawValue))
        }
        return nil
    }
}

enum NodeResultSorting {
    static func sorted(
        _ results: [SpeedTestResult],
        using comparators: [NodeResultSortComparator]
    ) -> [SpeedTestResult] {
        guard !comparators.isEmpty else { return results }

        return results.enumerated().sorted { lhs, rhs in
            for comparator in comparators {
                switch comparator.compare(lhs.element, rhs.element) {
                case .orderedAscending:
                    return true
                case .orderedDescending:
                    return false
                case .orderedSame:
                    continue
                }
            }

            // Swift's sort is not documented as stable. Preserve the source
            // order explicitly when all selected columns compare equally.
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}

private struct IPSortKey {
    let familyRank: Int
    let bytes: [UInt8]
}
