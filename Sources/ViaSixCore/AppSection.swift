import Foundation

public enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case overview
    case nodes
    case logs

    public var id: Self { self }

    public var title: String {
        switch self {
        case .overview: "连接"
        case .nodes: "节点测速"
        case .logs: "活动"
        }
    }

    public var systemImage: String {
        switch self {
        case .overview: "point.3.connected.trianglepath.dotted"
        case .nodes: "gauge.with.dots.needle.67percent"
        case .logs: "clock.arrow.circlepath"
        }
    }
}
