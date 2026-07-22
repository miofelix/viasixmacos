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

                    TrafficStatsView(
                        snapshot: model.state.traffic.snapshot,
                        isProxyRunning: model.state.isProxyRunning
                    )

                    HStack(alignment: .top, spacing: VisualStyle.spacing12) {
                        ipInfoCard
                        appInfoCard
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, VisualStyle.pageHorizontalPadding)
                .padding(.vertical, VisualStyle.pageVerticalPadding)
            }
            .scrollbarSafeContent()
        }
    }

    // MARK: - Link card

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

    // MARK: - Routing / network

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

    // MARK: - IP info (entry + exit)

    private var ipInfoCard: some View {
        SurfaceCard {
            CardHeader("IP 信息", systemImage: "globe.asia.australia.fill", tone: selectedNodeIsIPv6 ? .accent : .warning) {
                HStack(spacing: VisualStyle.spacing8) {
                    Button("选择节点", systemImage: "list.bullet", action: onSelectNodes)
                        .controlSize(.small)
                    Button(
                        model.state.exit.isDetecting ? "检测中…" : "检测出口",
                        systemImage: "arrow.clockwise",
                        action: model.detectExitIP
                    )
                    .controlSize(.small)
                    .disabled(model.state.exit.isDetecting)
                }
            }
            Divider()

            VStack(alignment: .leading, spacing: VisualStyle.spacing12) {
                ipInfoSection(title: "IPv6 入口", systemImage: "6.circle") {
                    VStack(alignment: .leading, spacing: VisualStyle.spacing8) {
                        HStack(alignment: .firstTextBaseline, spacing: VisualStyle.spacing8) {
                            Text(
                                model.state.preferences.selectedIP.isEmpty
                                    ? "尚未选择"
                                    : model.state.preferences.selectedIP
                            )
                            .font(.body.monospaced().weight(.semibold))
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            Spacer(minLength: 0)
                            if selectedNodeIsIPv6 {
                                copyButton(model.state.preferences.selectedIP)
                            }
                        }

                        if let result = currentNodeResult {
                            Text(result.performanceSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("优选 IPv6 地址后，ViaSix 会在运行时注入代理入口。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack {
                            Button(configurationTestTitle, systemImage: "scope") {
                                if configurationTestIsRunning {
                                    model.stopCurrentConfigurationTest()
                                } else {
                                    model.startCurrentConfigurationTest()
                                }
                            }
                            .controlSize(.small)
                            .disabled(
                                !configurationTestIsRunning
                                    && model.currentConfigurationTestUnavailableReason != nil
                            )
                            if let family = entryAddressFamilyLabel {
                                StatusBadge(family, tone: .accent, systemImage: "network")
                            }
                        }
                    }
                }

                Divider()

                ipInfoSection(title: "公网出口", systemImage: "location.fill") {
                    VStack(alignment: .leading, spacing: VisualStyle.spacing8) {
                        HStack(alignment: .firstTextBaseline, spacing: VisualStyle.spacing8) {
                            Text(model.state.exit.info?.ip ?? "尚未检测")
                                .font(.body.monospaced().weight(.semibold))
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                            Spacer(minLength: 0)
                            if let ip = model.state.exit.info?.ip, !ip.isEmpty {
                                copyButton(ip)
                            }
                        }

                        if let info = model.state.exit.info {
                            if !info.location.isEmpty {
                                infoRow("位置", info.location)
                            }
                            if !info.details.isEmpty {
                                infoRow("详情", info.details)
                            }
                            if let family = info.addressFamily {
                                StatusBadge(
                                    family.displayName,
                                    tone: .neutral,
                                    systemImage: family == .ipv6 ? "6.circle" : "4.circle"
                                )
                            }
                        } else if let error = model.state.exit.errorMessage, !error.isEmpty {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(AppTone.negative.color)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("检测网站出口 IP。它可能是 IPv4，不代表入口地址族。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack {
                            Picker("地址族", selection: exitModeBinding) {
                                Text("自动").tag(ExitIPDetectionMode.automatic)
                                Text("IPv4").tag(ExitIPDetectionMode.ipv4)
                                Text("IPv6").tag(ExitIPDetectionMode.ipv6)
                            }
                            .labelsHidden()
                            .frame(width: 100)

                            if let route = model.exitIPRouteDescription {
                                Text(route)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .padding(VisualStyle.spacing16)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - App info

    private var appInfoCard: some View {
        SurfaceCard {
            CardHeader("应用信息", systemImage: "info.circle.fill", tone: .neutral) {
                Link(destination: AppMetadata.repositoryURL) {
                    Label("GitHub", systemImage: "arrow.up.right.square")
                }
                .controlSize(.small)
            }
            Divider()

            VStack(alignment: .leading, spacing: 0) {
                infoDetailRow("应用版本", AppMetadata.displayVersion, systemImage: "app.badge")
                Divider().padding(.leading, 52)
                infoDetailRow("系统", macOSVersionSummary, systemImage: "desktopcomputer")
                Divider().padding(.leading, 52)
                infoDetailRow("运行方式", runtimeModeSummary, systemImage: "gearshape.2")
                Divider().padding(.leading, 52)
                infoDetailRow(
                    "本地代理",
                    model.state.proxyEndpoint.displayAddress,
                    systemImage: "point.3.filled.connected.trianglepath.dotted"
                )
                Divider().padding(.leading, 52)
                infoDetailRow(
                    "Controller",
                    "127.0.0.1:\(model.state.localProxyConfiguration.controllerPort)",
                    systemImage: "antenna.radiowaves.left.and.right"
                )
                Divider().padding(.leading, 52)
                infoDetailRow("代理模式", routingMode.displayName, systemImage: routingMode.appSystemImage)

                HStack(spacing: VisualStyle.spacing8) {
                    Link(destination: AppMetadata.repositoryURL) {
                        Label("打开仓库", systemImage: "link")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Link(destination: AppMetadata.issuesURL) {
                        Label("反馈问题", systemImage: "exclamationmark.bubble")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("使用帮助", systemImage: "questionmark.circle") {
                        AppDocumentOpener.open(.userGuide)
                    }
                    .controlSize(.small)
                }
                .padding(.top, VisualStyle.spacing12)
            }
            .padding(VisualStyle.spacing16)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Shared chrome

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

    private func ipInfoSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: VisualStyle.spacing8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: VisualStyle.spacing8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func infoDetailRow(_ title: String, _ value: String, systemImage: String) -> some View {
        SettingRow(title, detail: value, systemImage: systemImage) {
            EmptyView()
        }
    }

    private func copyButton(_ text: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .help("复制")
    }

    private var proxyActionButton: some View {
        Button(proxyActionTitle, systemImage: proxyActionIcon) {
            model.state.isProxyRunning ? model.stopProxy() : model.startProxy()
        }
        .buttonStyle(.borderedProminent)
        .disabled(proxyActionDisabled)
        .help(model.proxyConfigurationIssue ?? proxyActionTitle)
    }

    // MARK: - Computed state

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

    private var entryAddressFamilyLabel: String? {
        selectedNodeIsIPv6 ? "IPv6" : nil
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

    private var macOSVersionSummary: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var parts = [
            "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        ]
        #if arch(arm64)
            parts.append("Apple Silicon")
        #elseif arch(x86_64)
            parts.append("Intel")
        #endif
        return parts.joined(separator: " · ")
    }

    private var runtimeModeSummary: String {
        var parts: [String] = []
        if tunIsRequested {
            parts.append(model.state.tun.isRunning ? "TUN 运行中" : "TUN")
        } else {
            parts.append(model.state.isProxyRunning ? "本地代理运行中" : "本地代理")
        }
        if model.state.localProxyConfiguration.systemProxyEnabled {
            switch model.state.systemProxyPhase {
            case .enabled: parts.append("系统代理已启用")
            case .enabling, .disabling: parts.append("系统代理切换中")
            case .failed: parts.append("系统代理异常")
            case .disabled: parts.append("系统代理偏好开")
            }
        }
        return parts.joined(separator: " · ")
    }
}
