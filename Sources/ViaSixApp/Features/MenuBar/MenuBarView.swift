import AppKit
import SwiftUI
import ViaSixCore

/// The menu bar is intentionally action-oriented: the most common controls
/// are available without opening a second window, while detailed editing stays
/// in the main application pages.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("打开 ViaSix", systemImage: "macwindow") {
            openMainWindow(.overview)
        }
        .keyboardShortcut("o")

        Divider()

        proxyStatus
        routingModeMenu
        nodeMenu

        Divider()

        localProxyMenu
        networkAccessMenu
        Button("重新连接", systemImage: "arrow.clockwise") {
            model.restartProxy()
        }
        .disabled(!model.state.isProxyRunning || proxyRestartDisabled)
        speedTestMenu

        Divider()

        Button("日志", systemImage: "text.alignleft") {
            openMainWindow(.logs)
        }
        Button("设置", systemImage: "gearshape") {
            openMainWindow(.settings)
        }

        Divider()

        Button("退出 ViaSix", systemImage: "power") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private var proxyStatus: some View {
        let presentation = SidebarProxyPresentation(
            launchPhase: model.state.launchPhase,
            proxyCorePhase: model.state.proxyCorePhase,
            endpoint: model.state.proxyEndpoint
        )

        Label(presentation.statusTitle, systemImage: presentationIcon(presentation))
            .lineLimit(1)
            .accessibilityLabel("本地代理状态")
            .accessibilityValue(statusAccessibilityValue(presentation))
        if let endpoint = presentation.endpointSummary {
            Text(endpoint)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        if let detail = presentation.detailText {
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        if model.state.localProxyConfiguration.routingMode != .direct,
            !model.state.preferences.selectedIP.isEmpty
        {
            Label {
                Text("节点：\(model.state.preferences.selectedIP)")
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: "network")
            }
            .foregroundStyle(.secondary)
        }
    }

    private var routingModeMenu: some View {
        Menu {
            ForEach(ProxyRoutingMode.allCases, id: \.rawValue) { mode in
                Toggle(isOn: routingModeBinding(for: mode)) {
                    Label(mode.displayName, systemImage: mode.appSystemImage)
                }
                .disabled(routingModeDisabled)
                .help(mode.appDescription)
            }
        } label: {
            Label(
                "代理模式：\(model.state.localProxyConfiguration.routingMode.displayName)",
                systemImage: model.state.localProxyConfiguration.routingMode.appSystemImage
            )
        }
        .accessibilityLabel("代理模式")
        .accessibilityValue(model.state.localProxyConfiguration.routingMode.displayName)
    }

    private var nodeMenu: some View {
        let visible = MenuBarNodePresentation.visibleResults(
            from: model.state.results,
            selectedIP: model.state.preferences.selectedIP
        )
        let hasMore = MenuBarNodePresentation.hasAdditionalResults(
            in: model.state.results,
            selectedIP: model.state.preferences.selectedIP
        )

        return Menu {
            if visible.isEmpty {
                Button("暂无测速节点", systemImage: "network.slash") {}
                    .disabled(true)
            } else {
                ForEach(visible) { result in
                    Toggle(
                        isOn: nodeSelectionBinding(for: result.ip)
                    ) {
                        Text(MenuBarNodePresentation.title(for: result))
                    }
                    .disabled(nodeSelectionDisabled)
                    .help(nodeHelp(for: result))
                }
            }

            Divider()

            if hasMore {
                Button("查看全部节点…", systemImage: "list.bullet") {
                    openMainWindow(.nodes)
                }
            } else {
                Button("打开节点页", systemImage: "list.bullet") {
                    openMainWindow(.nodes)
                }
            }

        } label: {
            Label(nodeMenuTitle, systemImage: "point.3.connected.trianglepath.dotted")
        }
        .accessibilityLabel("节点")
        .accessibilityValue(nodeMenuTitle)
    }

    private var localProxyMenu: some View {
        Menu {
            Label(localProxyStatusTitle, systemImage: localProxyStatusIcon)
                .foregroundStyle(.secondary)

            if let issue = model.proxyConfigurationIssue, !model.state.isProxyRunning {
                Text(issue)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if case .failed(let message) = model.state.proxyCorePhase {
                Text(message)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Divider()
            localProxyActions
        } label: {
            Label("本地代理", systemImage: "network")
        }
        .accessibilityLabel("本地代理")
        .accessibilityValue(localProxyStatusTitle)
    }

    @ViewBuilder
    private var localProxyActions: some View {
        switch model.state.proxyCorePhase {
        case .stopped, .failed:
            Button("启动本地代理", systemImage: "play.fill") {
                model.startProxy()
            }
            .disabled(proxyStartDisabled)
        case .validating, .starting:
            Button("停止本地代理", systemImage: "stop.fill") {
                model.stopProxy()
            }
        case .running:
            Button("停止本地代理", systemImage: "stop.fill") {
                model.stopProxy()
            }
        case .stopping:
            Button("正在停止本地代理…", systemImage: "hourglass") {}
                .disabled(true)
        }
    }

    private var networkAccessMenu: some View {
        let presentation = systemProxyPresentation

        return Menu {
            Toggle("使用系统代理", isOn: systemProxyRequestedBinding)
                .disabled(systemProxyToggleDisabled)

            Toggle("虚拟网卡模式", isOn: .constant(false))
                .disabled(true)
                .help("需要安装并授权虚拟网卡服务")

            Divider()

            Label(
                "接入方式：\(model.state.localProxyConfiguration.networkAccessMode.displayName)",
                systemImage: model.state.localProxyConfiguration.networkAccessMode.usesSystemProxy
                    ? "checkmark.circle"
                    : "circle"
            )
            .foregroundStyle(.secondary)

            Label(
                "macOS：\(presentation.text)",
                systemImage: systemProxyStatusIcon(presentation)
            )
            .foregroundStyle(.secondary)

            if case .failed(let message) = model.state.systemProxyPhase {
                Text(message)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } label: {
            Label(
                "网络设置：\(model.state.localProxyConfiguration.networkAccessMode.displayName)",
                systemImage: "network"
            )
        }
        .accessibilityLabel("网络设置")
        .accessibilityValue(
            "接入方式：\(model.state.localProxyConfiguration.networkAccessMode.displayName)，macOS：\(presentation.text)"
        )
    }

    private var speedTestMenu: some View {
        Menu {
            speedTestStatus

            Divider()

            switch model.state.speedTest.phase {
            case .idle, .failed:
                Button("开始节点测速", systemImage: "gauge.with.dots.needle.67percent") {
                    model.startSpeedTest()
                }
                .disabled(!canStartFullSpeedTest)
            case .running:
                Button("停止节点测速", systemImage: "stop.fill") {
                    model.stopSpeedTest()
                }
            case .stopping:
                Button("正在停止测速…", systemImage: "hourglass") {}
                    .disabled(true)
            }

            if model.state.proxySupportsNodeSelection,
                !model.state.preferences.selectedIP.isEmpty
            {
                switch model.state.configurationTest.phase {
                case .idle, .failed:
                    Button("测试当前节点", systemImage: "scope") {
                        model.startCurrentConfigurationTest()
                    }
                    .disabled(model.currentConfigurationTestUnavailableReason != nil)
                case .running:
                    Button("停止当前节点测速", systemImage: "stop.fill") {
                        model.stopCurrentConfigurationTest()
                    }
                case .stopping:
                    Button("正在停止当前节点测速…", systemImage: "hourglass") {}
                        .disabled(true)
                }
            }

            Button("打开节点页", systemImage: "list.bullet") {
                openMainWindow(.nodes)
            }
        } label: {
            Label(speedTestMenuTitle, systemImage: "gauge.with.dots.needle.67percent")
        }
        .accessibilityLabel("测速")
        .accessibilityValue(speedTestMenuTitle)
    }

    @ViewBuilder
    private var speedTestStatus: some View {
        switch model.state.speedTest.phase {
        case .running:
            if model.state.speedTest.total > 0 {
                Label(
                    "正在测速 · \(model.state.speedTest.current)/\(model.state.speedTest.total)",
                    systemImage: "gauge.with.dots.needle.67percent"
                )
            } else {
                Label("测速准备中", systemImage: "gauge.with.dots.needle.67percent")
            }
        case .stopping:
            Label("正在停止测速", systemImage: "hourglass")
        case .failed(let message):
            Text("测速失败：\(message)")
                .lineLimit(2)
        case .idle:
            if let result = model.state.selectedResult {
                Label("当前节点：\(result.performanceSummary)", systemImage: "checkmark.circle")
            } else {
                Label("尚未测速", systemImage: "circle")
            }
        }
    }

    private var nodeMenuTitle: String {
        if model.state.localProxyConfiguration.routingMode == .direct {
            return "节点：直连模式"
        }
        let selected = model.state.preferences.selectedIP
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else { return "节点：未选择" }
        if let result = model.state.results.first(where: { $0.ip == selected }) {
            return "节点：\(MenuBarNodePresentation.title(for: result))"
        }
        return "节点：\(selected)"
    }

    private var localProxyStatusTitle: String {
        switch model.state.proxyCorePhase {
        case .stopped: "未启动"
        case .validating: "正在校验配置"
        case .starting: "正在启动"
        case .running: "运行中 · \(model.state.proxyEndpoint.displayAddress)"
        case .stopping: "正在停止"
        case .failed: "运行异常"
        }
    }

    private var localProxyStatusIcon: String {
        switch model.state.proxyCorePhase {
        case .running: "checkmark.circle.fill"
        case .validating, .starting, .stopping: "hourglass"
        case .failed: "exclamationmark.triangle.fill"
        case .stopped: "circle"
        }
    }

    private var speedTestMenuTitle: String {
        switch model.state.speedTest.phase {
        case .running: "测速进行中"
        case .stopping: "正在停止测速"
        case .failed: "测速失败"
        case .idle: "测速"
        }
    }

    private var systemProxyPresentation: SystemProxyStatusPresentation {
        SystemProxyStatusPresentation(
            phase: model.state.systemProxyPhase,
            isRequested: model.state.localProxyConfiguration.networkAccessMode.usesSystemProxy
        )
    }

    private var routingModeDisabled: Bool {
        guard model.state.launchPhase == .ready else { return true }
        if model.isRoutingModeChanging
            || model.isSystemProxyTransitioning
            || model.state.runtimeOperation != nil
            || model.isTemplateOperationBusy
            || model.switchingIP != nil
        {
            return true
        }
        switch model.state.proxyCorePhase {
        case .validating, .starting, .stopping:
            return true
        case .stopped, .running, .failed:
            return false
        }
    }

    private var nodeSelectionDisabled: Bool {
        guard model.state.launchPhase == .ready else { return true }
        guard model.state.proxySupportsNodeSelection else { return true }
        guard model.state.speedTestResultsAreCurrent else { return true }
        if model.switchingIP != nil
            || model.isCfstBusy
            || model.isTemplateOperationBusy
            || model.isRoutingModeChanging
        {
            return true
        }
        guard case .idle = model.state.speedTest.phase else { return true }
        switch model.state.proxyCorePhase {
        case .validating, .starting, .stopping:
            return true
        case .stopped, .running, .failed:
            return false
        }
    }

    private var proxyStartDisabled: Bool {
        guard model.state.launchPhase == .ready else { return true }
        if model.state.runtimeOperation != nil
            || model.isTemplateOperationBusy
            || model.switchingIP != nil
            || !model.hasProxyCoreExecutable
            || !model.isProxyConfigurationReady
        {
            return true
        }
        return false
    }

    private var proxyRestartDisabled: Bool {
        model.switchingIP != nil
            || model.isTemplateOperationBusy
            || model.state.runtimeOperation != nil
    }

    private var canStartFullSpeedTest: Bool {
        guard model.state.launchPhase == .ready else { return false }
        guard model.state.runtimeOperation == nil,
            !model.isTemplateOperationBusy,
            model.switchingIP == nil,
            !model.isCfstBusy,
            model.hasCfstExecutable
        else { return false }
        do {
            _ = try model.parameters.validated()
            return true
        } catch {
            return false
        }
    }

    private var systemProxyRequestedBinding: Binding<Bool> {
        Binding {
            model.state.localProxyConfiguration.networkAccessMode.usesSystemProxy
        } set: { enabled in
            model.setNetworkAccessMode(enabled ? .systemProxy : .localProxy)
        }
    }

    private var systemProxyToggleDisabled: Bool {
        guard model.state.launchPhase == .ready else { return true }
        if model.isRoutingModeChanging
            || model.state.runtimeOperation != nil
            || model.isTemplateOperationBusy
            || model.switchingIP != nil
        {
            return true
        }
        switch model.state.proxyCorePhase {
        case .validating, .starting, .stopping:
            return true
        case .stopped, .running, .failed:
            break
        }
        return model.isSystemProxyTransitioning
    }

    private func routingModeBinding(for mode: ProxyRoutingMode) -> Binding<Bool> {
        Binding {
            model.state.localProxyConfiguration.routingMode == mode
        } set: { isSelected in
            guard isSelected else { return }
            model.setRoutingMode(mode)
        }
    }

    private func nodeSelectionBinding(for ip: String) -> Binding<Bool> {
        Binding {
            model.state.preferences.selectedIP == ip
        } set: { isSelected in
            guard isSelected else { return }
            model.selectIP(ip)
        }
    }

    private func nodeHelp(for result: SpeedTestResult) -> String {
        let metrics = result.performanceSummary
        return metrics == "暂无有效测速指标" ? result.ip : "\(result.ip) · \(metrics)"
    }

    private func presentationIcon(_ presentation: SidebarProxyPresentation) -> String {
        if presentation.tone == .negative {
            return "exclamationmark.triangle.fill"
        }
        return switch presentation.action {
        case .startProxy: "play.circle"
        case .stopProxy: presentation.isBusy ? "hourglass" : "checkmark.circle.fill"
        case .none:
            "hourglass"
        }
    }

    private func statusAccessibilityValue(_ presentation: SidebarProxyPresentation) -> String {
        if let detail = presentation.detailText {
            return "\(presentation.statusTitle)，\(detail)"
        }
        return presentation.statusTitle
    }

    private func systemProxyStatusIcon(_ presentation: SystemProxyStatusPresentation) -> String {
        switch presentation.tone {
        case .active: "checkmark.circle.fill"
        case .pending: "hourglass"
        case .error: "exclamationmark.triangle.fill"
        case .neutral: "circle"
        }
    }

    private func openMainWindow(_ section: AppSection) {
        router.select(section)
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
