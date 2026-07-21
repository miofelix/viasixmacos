import Foundation

public enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case overview
    case proxies
    case profiles
    case connections
    case rules
    case logs
    case nodes
    case settings

    public var id: Self { self }

    public var title: String {
        switch self {
        case .overview: "首页"
        case .proxies: "代理"
        case .profiles: "配置"
        case .connections: "连接"
        case .rules: "规则"
        case .logs: "日志"
        case .nodes: "测速"
        case .settings: "设置"
        }
    }

    public var subtitle: String {
        switch self {
        case .overview: "连接状态与网络控制"
        case .proxies: "选择代理组与出站节点"
        case .profiles: "管理 Mihomo 配置档"
        case .connections: "查看并终止活动连接"
        case .rules: "检查当前路由规则"
        case .logs: "查看代理与测速活动"
        case .nodes: "测速并选择优选地址"
        case .settings: "服务器、本机与应用设置"
        }
    }

    public var systemImage: String {
        switch self {
        case .overview: "house"
        case .proxies: "wifi"
        case .profiles: "shippingbox"
        case .connections: "globe"
        case .rules: "arrow.triangle.branch"
        case .logs: "text.alignleft"
        case .nodes: "point.3.filled.connected.trianglepath.dotted"
        case .settings: "gearshape"
        }
    }
}
