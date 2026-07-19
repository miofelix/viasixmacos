import Foundation

public enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case overview
    case nodes
    case logs
    case settings

    public var id: Self { self }

    public var title: String {
        switch self {
        case .overview: "总览"
        case .nodes: "节点优选"
        case .logs: "运行记录"
        case .settings: "设置"
        }
    }

    public var systemImage: String {
        switch self {
        case .overview: "rectangle.grid.2x2"
        case .nodes: "network"
        case .logs: "text.alignleft"
        case .settings: "gearshape"
        }
    }
}
