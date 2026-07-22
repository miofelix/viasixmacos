import AppKit
import Network
import SwiftUI
import ViaSixCore

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    let onSelectNodes: () -> Void
    let onManageRuntime: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            AppPageHeader("首页", subtitle: "IPv6 代理链路状态与控制") {
                StatusBadge(
                    headerStatus,
                    tone: headerTone,
                    systemImage: headerIcon
                )
            }

            ScrollView {
                VStack(alignment: .leading, spacing: VisualStyle.spacing12) {
                    ipv6LinkCard
                    HStack(alignment: .top, spacing: VisualStyle.spacing12) {
                        routingModeCard
                        networkAccessCard
                    }
                    HStack(alignment: .top, spacing: VisualStyle.spacing12) {
                        nodeCard
                        exitIPCard
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, VisualStyle.pageHorizontalPadding)
                .padding(.vertical, VisualStyle.pageVerticalPadding)
            }
            .scrollbarSafeContent()
        }
    }

    private var ipv6LinkCard: some View {
        SurfaceCard {
            CardHeader("IPv6 链路", systemImage: "6.circle.fill", tone: headerTone) {
                proxyActionButton
            }
            Divider()

            VStack(spacing: 0) {
                linkStep(
                    "网络接入",
                    detail: networkAccessDetail,
                    ready: networkAccessIsReady,
                    active: networkAccessIsActive,
                    actionTitle: networkAccessNeedsSetup ? "准备服务" : nil,
                    action: networkAccessNeedsSetup ? onManageRuntime : nil
                )
                Divider().padding(.leading, 52)
                linkStep(
                    "IPv6 节点",
                    detail: selectedNodeDetail,
                    ready: selectedNodeIsIPv6,
                    active: selectedNodeIsIPv6,
                    actionTitle: selectedNodeIsIPv6 ? "更换" : "选择",
                    action: onSelectNodes
                )
                Divider().padding(.leading, 52)
                linkStep(
                    "连接配置",
                    detail: configurationDetail,
                    ready: configurationIsReady,
                    active: configurationIsReady,
                    actionTitle: nil,
                    action: nil
                )
                Divider().padding(.leading, 52)
                linkStep(
                    "公网流量",
                    detail: publicTrafficDetail,
                    ready: model.isProxyConfigurationReady,
                    active: model.state.isProxyRunning,
                    actionTitle: nil,
                    action: nil
                )
            }
            .padding(.horizontal, VisualStyle.spacing16)
            .padding(.bottom, VisualStyle.spacing12)
        }
    }

    private var routingModeCard: some View {
        SurfaceCard {
            CardHeader("代理模式", systemImage: routingMode.appSystemImage, tone: .accent)
            Divider()
            VStack(alignment: .leading, spacing: VisualStyle.spacing12) {
                Picker("代理模式", selection: routingModeBinding) {
                    ForEach(ProxyRoutingMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(routingControlsDisabled)

                Text(routingModeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(VisualStyle.spacing16)
        }
        .frame(maxWidth: .infinity)
    }

    private var networkAccessCard: some View {
        SurfaceCard {
            CardHeader("网络设置", systemImage: "network", tone: .accent)
            Divider()
            VStack(spacing: 0) {
                SettingRow(
                    "系统代理",
                    detail: "配置 macOS HTTP、HTTPS 与 SOCKS 代理",
                    systemImage: "desktopcomputer"
                ) {
                    Toggle("系统代理", isOn: systemProxyBinding)
                        .labelsHidden()
                        .disabled(networkControlsDisabled)
                }

                Divider().padding(.leading, 52)

                SettingRow(
                    "虚拟网卡模式",
                    detail: tunNetworkDetail,
                    systemImage: "point.3.filled.connected.trianglepath.dotted"
                ) {
                    Toggle("虚拟网卡模式", isOn: tunBinding)
                        .labelsHidden()
                        .disabled(networkControlsDisabled || (!tunIsRequested && !model.canUseTunMode))
                }
            }
            .padding(.horizontal, VisualStyle.spacing16)
            .padding(.bottom, VisualStyle.spacing12)
        }
        .frame(maxWidth: .infinity)
    }

    private func linkStep(
        _ title: String,
        detail: String,
        ready: Bool,
        active: Bool,
        actionTitle: String?,
        action: (() -> Void)?
    ) -> some View {
        SettingRow(
            title,
            detail: detail,
            systemImage: active ? "checkmark.circle.fill" : (ready ? "checkmark.circle" : "circle")
        ) {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
            } else {
                StatusBadge(
                    active ? "已启用" : (ready ? "已就绪" : "未就绪"),
                    tone: active ? .positive : (ready ? .accent : .warning)
                )
            }
        }
    }

    private var nodeCard: some View {
        SurfaceCard {
            CardHeader("当前 IPv6 节点", systemImage: "network", tone: selectedNodeIsIPv6 ? .accent : .warning)
            Divider()
            VStack(alignment: .leading, spacing: VisualStyle.spacing12) {
                Text(model.state.preferences.selectedIP.isEmpty ? "尚未选择" : model.state.preferences.selectedIP)
                    .font(.title3.monospaced().weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                if let result = currentNodeResult {
                    Text(result.performanceSummary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("选择 IPv6 优选地址后，ViaSix 会在运行时将它注入代理入口。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Button("选择节点", systemImage: "list.bullet", action: onSelectNodes)
                    Button(configurationTestTitle, systemImage: "scope") {
                        if configurationTestIsRunning {
                            model.stopCurrentConfigurationTest()
                        } else {
                            model.startCurrentConfigurationTest()
                        }
                    }
                    .disabled(
                        !configurationTestIsRunning
                            && model.currentConfigurationTestUnavailableReason != nil
                    )
                }
            }
            .padding(VisualStyle.spacing16)
        }
        .frame(maxWidth: .infinity)
    }

    private var exitIPCard: some View {
        SurfaceCard {
            CardHeader("公网出口", systemImage: "location", tone: .neutral)
            Divider()
            VStack(alignment: .leading, spacing: VisualStyle.spacing12) {
                HStack {
                    Text(model.state.exit.info?.ip ?? "尚未检测")
                        .font(.title3.monospaced().weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer()
                    if model.state.exit.info != nil {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(
                                model.state.exit.info?.ip ?? "",
                                forType: .string
                            )
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                if let info = model.state.exit.info, !info.location.isEmpty {
                    Text(info.location)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Text("出口地址可能是 IPv4；它不代表客户端到代理入口所使用的地址族。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Picker("地址族", selection: exitModeBinding) {
                        Text("自动").tag(ExitIPDetectionMode.automatic)
                        Text("IPv4").tag(ExitIPDetectionMode.ipv4)
                        Text("IPv6").tag(ExitIPDetectionMode.ipv6)
                    }
                    .labelsHidden()
                    .frame(width: 100)
                    Button(
                        model.state.exit.isDetecting ? "检测中…" : "检测",
                        systemImage: "arrow.clockwise",
                        action: model.detectExitIP
                    )
                    .disabled(model.state.exit.isDetecting)
                }
            }
            .padding(VisualStyle.spacing16)
        }
        .frame(maxWidth: .infinity)
    }

    private var proxyActionButton: some View {
        Button(proxyActionTitle, systemImage: proxyActionIcon) {
            model.state.isProxyRunning ? model.stopProxy() : model.startProxy()
        }
        .buttonStyle(.borderedProminent)
        .disabled(proxyActionDisabled)
        .help(model.proxyConfigurationIssue ?? proxyActionTitle)
    }

    private var proxyActionTitle: String {
        switch model.state.proxyCorePhase {
        case .stopped, .failed: "启动连接"
        case .validating, .starting: "正在启动"
        case .running: "停止连接"
        case .stopping: "正在停止"
        }
    }

    private var proxyActionIcon: String {
        model.state.isProxyRunning ? "stop.fill" : "play.fill"
    }

    private var proxyActionDisabled: Bool {
        switch model.state.proxyCorePhase {
        case .validating, .starting, .stopping: true
        case .running: false
        case .stopped, .failed:
            !model.isProxyConfigurationReady || !model.activeProxyRuntimeIsAvailable
                || model.isTemplateOperationBusy || model.switchingIP != nil
        }
    }

    private var headerStatus: String {
        if routingMode == .direct {
            return model.state.isProxyRunning ? "直连已启用" : "直连未启用"
        }
        return model.state.isProxyRunning ? "IPv6 已启用" : "IPv6 未启用"
    }

    private var headerTone: AppTone {
        if case .failed = model.state.proxyCorePhase { return .negative }
        return model.state.isProxyRunning ? .positive : .accent
    }

    private var headerIcon: String {
        if routingMode == .direct { return "arrow.right.circle" }
        return model.state.isProxyRunning ? "checkmark.circle.fill" : "6.circle"
    }

    private var selectedNodeIsIPv6: Bool {
        IPv6Address(
            model.state.preferences.selectedIP.trimmingCharacters(in: .whitespacesAndNewlines)
        ) != nil
    }

    private var selectedNodeDetail: String {
        selectedNodeIsIPv6 ? model.state.preferences.selectedIP : "尚未选择有效 IPv6 地址"
    }

    private var configurationDetail: String {
        if routingMode == .direct { return "直连模式不加载远程代理配置" }
        return model.state.proxySupportsNodeSelection
            ? "主内联节点可注入当前 IPv6 地址"
            : "配置需要包含可注入地址的内联代理"
    }

    private var configurationIsReady: Bool {
        routingMode == .direct || model.state.proxySupportsNodeSelection
    }

    private var networkAccessDetail: String {
        switch (tunIsRequested, model.state.localProxyConfiguration.systemProxyEnabled) {
        case (true, true):
            return model.state.isProxyRunning
                ? "虚拟网卡与系统代理已同时启用"
                : "启动后同时启用虚拟网卡与系统代理"
        case (true, false):
            return model.state.tun.isRunning
                ? "虚拟网卡正在接管系统流量"
                : "启动后由虚拟网卡接管系统流量"
        case (false, true):
            return model.state.systemProxyPhase == .enabled
                ? "macOS 系统代理已指向 ViaSix"
                : "启动后配置 macOS 系统代理"
        case (false, false):
            return "仅提供本地代理端口，不自动接管系统流量"
        }
    }

    private var networkAccessNeedsSetup: Bool {
        tunIsRequested && !model.canUseTunMode
    }

    private var networkAccessIsReady: Bool {
        !tunIsRequested || model.canUseTunMode
    }

    private var networkAccessIsActive: Bool {
        guard model.state.isProxyRunning else { return false }
        if tunIsRequested { return model.state.tun.isRunning }
        if model.state.localProxyConfiguration.systemProxyEnabled {
            return model.state.systemProxyPhase == .enabled
        }
        return true
    }

    private var publicTrafficDetail: String {
        if model.state.isProxyRunning {
            switch routingMode {
            case .rule: return "私有地址直连，其余流量通过 IPv6 代理入口"
            case .global: return "所有代理流量通过当前 IPv6 代理入口"
            case .direct: return "流量不经过远程代理"
            }
        }
        return model.proxyConfigurationIssue ?? "等待启动"
    }

    private var routingMode: ProxyRoutingMode {
        model.state.localProxyConfiguration.routingMode
    }

    private var routingModeBinding: Binding<ProxyRoutingMode> {
        Binding(get: { routingMode }, set: { model.setRoutingMode($0) })
    }

    private var routingModeDescription: String {
        switch routingMode {
        case .rule: "私有地址直连，其余流量走当前 IPv6 节点。"
        case .global: "所有进入代理的流量统一走当前 IPv6 节点。"
        case .direct: "不使用远程代理，保留本地接入方式用于直连。"
        }
    }

    private var systemProxyBinding: Binding<Bool> {
        Binding(
            get: { model.state.localProxyConfiguration.systemProxyEnabled },
            set: { model.setSystemProxyEnabled($0) }
        )
    }

    private var tunBinding: Binding<Bool> {
        Binding(
            get: { tunIsRequested },
            set: { enabled in
                model.setNetworkAccessMode(enabled ? .virtualInterface : .localProxy)
            }
        )
    }

    private var tunIsRequested: Bool {
        model.state.localProxyConfiguration.networkAccessMode == .virtualInterface
    }

    private var tunNetworkDetail: String {
        if tunIsRequested {
            return model.state.tun.isRunning ? "正在接管系统流量" : "启动连接时接管系统流量"
        }
        return model.canUseTunMode ? "当前关闭，可与系统代理独立启用" : "需要先在设置中准备 TUN 服务"
    }

    private var routingControlsDisabled: Bool {
        model.isRoutingModeChanging
            || model.isNetworkAccessChanging
            || model.isTemplateOperationBusy
            || model.switchingIP != nil
    }

    private var networkControlsDisabled: Bool {
        model.isNetworkAccessChanging
            || model.isRoutingModeChanging
            || model.isTunTransitioning
            || model.isTemplateOperationBusy
    }

    private var currentNodeResult: SpeedTestResult? {
        if let result = model.state.configurationTest.result,
            result.ip == model.state.preferences.selectedIP
        {
            return result
        }
        return model.state.selectedResult
    }

    private var configurationTestIsRunning: Bool {
        switch model.state.configurationTest.phase {
        case .running, .stopping: true
        case .idle, .failed: false
        }
    }

    private var configurationTestTitle: String {
        configurationTestIsRunning ? "停止测试" : "测试当前节点"
    }

    private var exitModeBinding: Binding<ExitIPDetectionMode> {
        Binding(get: { model.exitIPDetectionMode }, set: { model.exitIPDetectionMode = $0 })
    }
}
