import ViaSixCore

/// User-facing state for the proxy control anchored at the bottom of the
/// application sidebar. Keeping launch and runtime precedence here prevents
/// the shell from presenting a stopped proxy while the application is still
/// loading or has failed to initialize.
struct SidebarProxyPresentation: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case none
        case startProxy
        case stopProxy
    }

    let statusTitle: String
    let detailText: String?
    let tone: AppTone
    let endpointSummary: String?
    let actionTitle: String
    let actionSystemImage: String
    let action: Action
    let isBusy: Bool

    init(
        launchPhase: AppState.LaunchPhase,
        proxyCorePhase: AppState.ProxyCorePhase,
        endpoint: ProxyEndpoint
    ) {
        switch launchPhase {
        case .idle, .loading:
            statusTitle = "正在准备 ViaSix"
            detailText = "正在检查应用数据与运行组件"
            tone = .accent
            endpointSummary = nil
            actionTitle = "正在准备"
            actionSystemImage = "hourglass"
            action = .none
            isBusy = true

        case .failed(let message):
            statusTitle = "初始化失败"
            detailText = message
            tone = .negative
            endpointSummary = nil
            actionTitle = "初始化未完成"
            actionSystemImage = "exclamationmark.triangle.fill"
            action = .none
            isBusy = false

        case .ready:
            endpointSummary = endpoint.displayAddress

            switch proxyCorePhase {
            case .stopped:
                statusTitle = "本地代理未启动"
                detailText = nil
                tone = .neutral
                actionTitle = "启动代理"
                actionSystemImage = "play.fill"
                action = .startProxy
                isBusy = false

            case .validating:
                statusTitle = "正在校验配置"
                detailText = nil
                tone = .warning
                actionTitle = "取消启动"
                actionSystemImage = "stop.fill"
                action = .stopProxy
                isBusy = true

            case .starting:
                statusTitle = "正在启动代理"
                detailText = nil
                tone = .warning
                actionTitle = "取消启动"
                actionSystemImage = "stop.fill"
                action = .stopProxy
                isBusy = true

            case .running:
                statusTitle = "本地代理运行中"
                detailText = nil
                tone = .positive
                actionTitle = "停止代理"
                actionSystemImage = "stop.fill"
                action = .stopProxy
                isBusy = false

            case .stopping:
                statusTitle = "正在停止代理"
                detailText = nil
                tone = .warning
                actionTitle = "正在停止"
                actionSystemImage = "hourglass"
                action = .none
                isBusy = true

            case .failed(let message):
                statusTitle = "本地代理异常"
                detailText = message
                tone = .negative
                actionTitle = "重新启动"
                actionSystemImage = "arrow.clockwise"
                action = .startProxy
                isBusy = false
            }
        }
    }
}
