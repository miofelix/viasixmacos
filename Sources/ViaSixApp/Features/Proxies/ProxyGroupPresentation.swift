import Foundation
import ViaSixCore

enum ProxySortMode: Int, CaseIterable, Sendable {
    case defaultOrder
    case delay
    case name

    var next: Self {
        Self(rawValue: (rawValue + 1) % Self.allCases.count) ?? .defaultOrder
    }

    var title: String {
        switch self {
        case .defaultOrder: "默认顺序"
        case .delay: "按延迟排序"
        case .name: "按名称排序"
        }
    }

    var systemImage: String {
        switch self {
        case .defaultOrder: "arrow.up.arrow.down"
        case .delay: "clock"
        case .name: "textformat.abc"
        }
    }
}

enum ProxyGroupInputMode: Equatable, Sendable {
    case filter
    case testURL
}

struct ProxyGroupViewState: Equatable, Sendable {
    var isExpanded = false
    var showsType = true
    var sortMode = ProxySortMode.defaultOrder
    var filterText = ""
    var testURL = ""
    var inputMode: ProxyGroupInputMode?
}

struct ProxyCandidatePresentation: Identifiable, Equatable, Sendable {
    var id: String { name }
    let name: String
    let type: String
    let delay: Int?
    fileprivate let originalIndex: Int
}

enum ProxyGroupPresentation {
    static func candidates(
        in group: MihomoProxyGroup,
        filterText: String,
        sortMode: ProxySortMode,
        timeoutMilliseconds: Int = AppMetadata.proxyDelayTimeoutMilliseconds
    ) -> [ProxyCandidatePresentation] {
        let candidates = group.candidates.enumerated().map { index, name in
            ProxyCandidatePresentation(
                name: name,
                type: group.candidateTypes[name] ?? "Unknown",
                delay: group.delays[name],
                originalIndex: index
            )
        }
        let filtered = filter(candidates, text: filterText, timeout: timeoutMilliseconds)
        return sort(filtered, mode: sortMode, timeout: timeoutMilliseconds)
    }

    private static func filter(
        _ candidates: [ProxyCandidatePresentation],
        text: String,
        timeout: Int
    ) -> [ProxyCandidatePresentation] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return candidates }

        if let expression = delayExpression(in: query) {
            return candidates.filter { candidate in
                guard let delay = candidate.delay, delay >= 0 else { return false }
                switch expression.value {
                case .timeout:
                    guard expression.comparison == .equal else { return false }
                    return delay == 0 || (delay >= timeout && delay < 100_000)
                case .error:
                    guard expression.comparison == .equal else { return false }
                    return delay >= 100_000
                case .milliseconds(let value):
                    return switch expression.comparison {
                    case .equal: delay == value
                    case .lessThan: delay <= value
                    case .greaterThan: delay >= value
                    }
                }
            }
        }

        if let typeQuery = typeExpression(in: query) {
            return candidates.filter { candidate in
                candidate.type.localizedCaseInsensitiveContains(typeQuery)
            }
        }

        return candidates.filter { candidate in
            candidate.name.localizedCaseInsensitiveContains(query)
        }
    }

    private static func sort(
        _ candidates: [ProxyCandidatePresentation],
        mode: ProxySortMode,
        timeout: Int
    ) -> [ProxyCandidatePresentation] {
        switch mode {
        case .defaultOrder:
            candidates
        case .name:
            candidates.sorted { lhs, rhs in
                let comparison = lhs.name.localizedStandardCompare(rhs.name)
                return comparison == .orderedSame
                    ? lhs.originalIndex < rhs.originalIndex
                    : comparison == .orderedAscending
            }
        case .delay:
            candidates.sorted { lhs, rhs in
                let left = delaySortKey(lhs.delay, timeout: timeout)
                let right = delaySortKey(rhs.delay, timeout: timeout)
                if left.category != right.category { return left.category < right.category }
                if left.value != right.value { return left.value < right.value }
                return lhs.originalIndex < rhs.originalIndex
            }
        }
    }

    private static func delaySortKey(_ delay: Int?, timeout: Int) -> (category: Int, value: Int) {
        guard let delay else { return (3, .max) }
        if delay > 100_000 { return (2, delay) }
        if delay == 0 || delay >= timeout { return (1, delay == 0 ? timeout : delay) }
        if delay > 0 { return (0, delay) }
        return (3, .max)
    }

    private enum DelayComparison {
        case equal
        case lessThan
        case greaterThan
    }

    private enum DelayValue {
        case milliseconds(Int)
        case timeout
        case error
    }

    private struct DelayExpression {
        let comparison: DelayComparison
        let value: DelayValue
    }

    private static func delayExpression(in query: String) -> DelayExpression? {
        let pattern = #"delay\s*([=<>])\s*(\d+|timeout|error)"#
        guard
            let expression = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            )
        else { return nil }
        let range = NSRange(query.startIndex..<query.endIndex, in: query)
        guard let match = expression.firstMatch(in: query, range: range),
            let comparisonRange = Range(match.range(at: 1), in: query),
            let valueRange = Range(match.range(at: 2), in: query)
        else { return nil }

        let comparison: DelayComparison =
            switch query[comparisonRange] {
            case "<": .lessThan
            case ">": .greaterThan
            default: .equal
            }
        let rawValue = query[valueRange].lowercased()
        let value: DelayValue
        switch rawValue {
        case "timeout":
            value = .timeout
        case "error":
            value = .error
        default:
            guard let milliseconds = Int(rawValue) else { return nil }
            value = .milliseconds(milliseconds)
        }
        return DelayExpression(comparison: comparison, value: value)
    }

    private static func typeExpression(in query: String) -> String? {
        let pattern = #"type\s*=\s*(.*)"#
        guard
            let expression = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            )
        else { return nil }
        let range = NSRange(query.startIndex..<query.endIndex, in: query)
        guard let match = expression.firstMatch(in: query, range: range),
            let valueRange = Range(match.range(at: 1), in: query)
        else { return nil }
        let value = query[valueRange].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
