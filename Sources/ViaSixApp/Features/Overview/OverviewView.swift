import AppKit
import SwiftUI
import ViaSixCore

struct OverviewView: View {
    @Environment(AppModel.self) private var model
    let onSelectNodes: () -> Void
    let onManageRuntime: () -> Void

    @State private var copiedEndpoint = false
    @State private var copiedExitIP = false
    @State private var optimisticRoutingMode: ProxyRoutingMode?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VisualStyle.spacing16) {
                pageHeader

                if runtimeNeedsAttention {
                    runtimeBanner
                }

                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: 350),
                            spacing: VisualStyle.spacing16,
                            alignment: .top
                        )
                    ],
                    alignment: .leading,
                    spacing: VisualStyle.spacing16
                ) {
                    connectionCard
                    routingModeCard
                    networkAccessCard
                    runtimeActivityCard
                    exitIPCard
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, VisualStyle.spacing4)
        }
        .scrollbarSafeContent()
        .onChange(of: model.state.localProxyConfiguration.routingMode) { _, mode in
            if optimisticRoutingMode == mode {
                optimisticRoutingMode = nil
            }
        }
        .onChange(of: model.isRoutingModeChanging) { _, isChanging in
            if !isChanging {
                optimisticRoutingMode = nil
            }
        }
    }

    private var pageHeader: some View {
        AppPageHeader(
            "首页",
            subtitle: "查看连接状态并控制本地网络代理"
        ) {
            StatusBadge(
                proxyPresentation.statusTitle,
                tone: proxyPresentation.tone,
                systemImage: proxyPresentation.isBusy ? "hourglass" : nil
            )
        }
    }

    private var connectionCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(
                    "当前连接",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    tone: proxyPresentation.tone
                ) {
                    StatusBadge(
                        connectionStatusShortTitle,
                        tone: proxyPresentation.tone
                    )
                }

                Divider()

                VStack(alignment: .leading, spacing: VisualStyle.spacing16) {
                    currentNodeSummary

                    if selectedResult != nil {
                        connectionMetrics
                    }

                    configurationTestStatus

                    Divider()

                    localEndpointRow

                    if case .failed(let message) = model.state.proxyCorePhase {
                        inlineMessage(
                            message,
                            systemImage: "exclamationmark.triangle.fill",
                            tone: .negative
                        )
                    } else if !model.state.isProxyRunning {
                        inlineMessage(
                            proxyReadinessHint,
                            systemImage: "info.circle",
                            tone: .neutral
                        )
                    }

                    connectionActions
                }
                .padding(VisualStyle.spacing16)
            }
        }
    }

    private var currentNodeSummary: some View {
        HStack(alignment: .top, spacing: VisualStyle.spacing12) {
            Image(systemName: currentNodeIcon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(currentNodeTone.color)
                .frame(width: 42, height: 42)
                .background(
                    currentNodeTone.color.opacity(0.1),
                    in: RoundedRectangle(
                        cornerRadius: VisualStyle.radiusMedium,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(currentNodeTitle)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(currentNodeDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: VisualStyle.spacing8)
        }
    }

    private var connectionMetrics: some View {
        HStack(spacing: VisualStyle.spacing8) {
            if let region = selectedResult?.region, !region.isEmpty {
                ConnectionMetricChip(
                    title: region,
                    systemImage: "mappin.and.ellipse"
                )
            }

            if let latency = selectedResult?.latencyDisplayValue {
                ConnectionMetricChip(
                    title: latency,
                    systemImage: "timer"
                )
            }

            if let speed = selectedResult?.speedDisplayValue {
                ConnectionMetricChip(
                    title: speed,
                    systemImage: "arrow.down"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var localEndpointRow: some View {
        SettingRow(
            "本地端点",
            detail: "HTTP / SOCKS 混合代理",
            systemImage: "network"
        ) {
            HStack(spacing: 4) {
                Text(proxyEndpoint)
                    .font(.caption.monospaced().weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Button(action: copyProxyEndpoint) {
                    Image(systemName: copiedEndpoint ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .iconButtonHitTarget()
                .help(copiedEndpoint ? "已复制" : "复制代理地址")
                .accessibilityLabel(copiedEndpoint ? "已复制代理地址" : "复制代理地址")
            }
        }
    }

    private var connectionActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: VisualStyle.spacing8) {
                proxyPrimaryButton
                nodeSelectionButton
                configurationTestButton

                if model.state.isProxyRunning {
                    reconnectButton
                }
            }

            VStack(alignment: .leading, spacing: VisualStyle.spacing8) {
                HStack(spacing: VisualStyle.spacing8) {
                    proxyPrimaryButton
                    nodeSelectionButton
                }

                HStack(spacing: VisualStyle.spacing8) {
                    configurationTestButton
                    if model.state.isProxyRunning {
                        reconnectButton
                    }
                }
            }
        }
    }

    private var proxyPrimaryButton: some View {
        Button {
            performProxyPrimaryAction()
        } label: {
            Label(
                proxyPresentation.actionTitle,
                systemImage: proxyPresentation.actionSystemImage
            )
        }
        .buttonStyle(OverviewPrimaryActionButtonStyle())
        .disabled(proxyPresentation.action == .none || proxyToggleDisabled)
        .help(proxyReadinessHint)
    }

    private var nodeSelectionButton: some View {
        Button("选择节点", systemImage: "network", action: onSelectNodes)
    }

    private var configurationTestButton: some View {
        Button(configurationTestButtonTitle, systemImage: configurationTestButtonIcon) {
            if isConfigurationTestRunning {
                model.stopCurrentConfigurationTest()
            } else {
                model.startCurrentConfigurationTest()
            }
        }
        .disabled(configurationTestButtonDisabled)
        .help(configurationTestButtonHelp)
        .accessibilityHint(configurationTestButtonHelp)
    }

    private var reconnectButton: some View {
        Button("重新连接", systemImage: "arrow.clockwise", action: model.restartProxy)
            .disabled(model.switchingIP != nil || model.isTemplateOperationBusy)
    }

    @ViewBuilder
    private var configurationTestStatus: some View {
        switch model.state.configurationTest.phase {
        case .running:
            inlineMessage(
                "正在测试当前节点…",
                systemImage: "gauge.with.dots.needle.67percent",
                tone: .accent
            )
        case .stopping:
            inlineMessage(
                "正在停止当前节点测速…",
                systemImage: "hourglass",
                tone: .neutral
            )
        case .failed(let message):
            inlineMessage(
                "当前节点测速失败：\(message)",
                systemImage: "exclamationmark.circle.fill",
                tone: .negative
            )
        case .idle:
            if let completedAt = model.state.configurationTest.completedAt,
                model.state.configurationTest.result != nil
            {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("当前节点测速完成 ·")
                    Text(completedAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(completedAt.formatted(date: .complete, time: .standard))
            }
        }
    }

    private var routingModeCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(
                    "代理模式",
                    systemImage: "point.3.connected.trianglepath.dotted"
                ) {
                    if model.isRoutingModeChanging {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("正在切换代理模式")
                    } else {
                        StatusBadge(displayedRoutingMode.displayName, tone: .accent)
                    }
                }

                Divider()

                ProxyRoutingModePicker(
                    selection: Binding(
                        get: { displayedRoutingMode },
                        set: { selectRoutingMode($0) }
                    ),
                    isDisabled: routingModePickerDisabled
                )
                .padding(VisualStyle.spacing16)
            }
        }
    }

    private var networkAccessCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(
                    "网络接入",
                    systemImage: "macbook.and.iphone",
                    tone: networkAccessTone
                ) {
                    StatusBadge(
                        networkAccessStatusText,
                        tone: networkAccessTone,
                        systemImage: networkAccessStatusSystemImage
                    )
                }

                Divider()

                VStack(alignment: .leading, spacing: 0) {
                    SettingRow(
                        "系统代理",
                        detail: "让遵循 macOS 代理设置的应用使用 ViaSix",
                        systemImage: "desktopcomputer"
                    ) {
                        Toggle("系统代理", isOn: systemProxyEnabledBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .disabled(systemProxyToggleDisabled)
                            .accessibilityLabel("系统代理")
                            .accessibilityValue(systemProxyStatusText)
                    }

                    Divider()

                    SettingRow(
                        "虚拟网卡模式",
                        detail: "通过 TUN 接管不支持系统代理的应用流量",
                        systemImage: "point.3.filled.connected.trianglepath.dotted"
                    ) {
                        Toggle("虚拟网卡模式", isOn: tunEnabledBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .disabled(tunToggleDisabled)
                            .help(tunToggleHelp)
                            .accessibilityLabel("虚拟网卡模式")
                            .accessibilityValue(tunStatusText)
                    }

                    Divider()

                    SettingRow(
                        "本地监听",
                        detail: "仅监听本机回环地址",
                        systemImage: "lock.shield"
                    ) {
                        Text(proxyEndpoint)
                            .font(.caption.monospaced().weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if model.state.localProxyConfiguration.networkAccessMode == .virtualInterface,
                        let message = model.state.tun.lastError
                    {
                        Divider()
                        inlineMessage(
                            message,
                            systemImage: "exclamationmark.triangle.fill",
                            tone: .negative
                        )
                        .padding(.vertical, VisualStyle.spacing12)
                    } else if case .failed(let message) = model.state.systemProxyPhase {
                        Divider()
                        inlineMessage(
                            message,
                            systemImage: "exclamationmark.triangle.fill",
                            tone: .negative
                        )
                        .padding(.vertical, VisualStyle.spacing12)
                    }

                    Text(networkAccessFooter)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, VisualStyle.spacing12)
                }
                .padding(.horizontal, VisualStyle.spacing16)
                .padding(.bottom, VisualStyle.spacing16)
            }
        }
    }

    private var runtimeActivityCard: some View {
        SurfaceCard {
            CardHeader(
                "实时活动",
                systemImage: "waveform.path.ecg",
                tone: model.state.isProxyRunning ? .positive : .neutral
            ) {
                if let version = model.state.mihomoRuntime.snapshot?.version {
                    StatusBadge(version, tone: .neutral)
                }
            }
            Divider()

            if let snapshot = model.state.mihomoRuntime.snapshot {
                VStack(alignment: .leading, spacing: VisualStyle.spacing12) {
                    HStack(spacing: VisualStyle.spacing8) {
                        overviewRuntimeMetric(
                            "上传",
                            value: RuntimePresentation.speed(model.state.mihomoRuntime.uploadSpeed),
                            icon: "arrow.up",
                            tone: .warning
                        )
                        overviewRuntimeMetric(
                            "下载",
                            value: RuntimePresentation.speed(model.state.mihomoRuntime.downloadSpeed),
                            icon: "arrow.down",
                            tone: .accent
                        )
                        overviewRuntimeMetric(
                            "连接",
                            value: "\(snapshot.connections.count)",
                            icon: "link",
                            tone: .positive
                        )
                        overviewRuntimeMetric(
                            "内存",
                            value: RuntimePresentation.byteCount(snapshot.memoryUsage),
                            icon: "memorychip",
                            tone: .neutral
                        )
                    }

                    RuntimeTrafficChart(samples: model.state.mihomoRuntime.trafficSamples)

                    SettingRow(
                        "累计流量",
                        detail: "Mihomo 本次运行会话",
                        systemImage: "chart.bar"
                    ) {
                        Text(
                            "↑ \(RuntimePresentation.byteCount(snapshot.uploadTotal))  "
                                + "↓ \(RuntimePresentation.byteCount(snapshot.downloadTotal))"
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(VisualStyle.spacing16)
            } else {
                VStack(spacing: VisualStyle.spacing8) {
                    if model.state.isProxyRunning {
                        ProgressView()
                        Text("正在连接 Mihomo Controller…")
                    } else {
                        Image(systemName: "waveform.path.ecg")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text("启动本地代理后显示实时流量与连接数")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 142)
                .padding(VisualStyle.spacing16)
            }
        }
    }

    private func overviewRuntimeMetric(
        _ title: String,
        value: String,
        icon: String,
        tone: AppTone
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(tone.color)
            Text(value)
                .font(.callout.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(tone.color.opacity(0.2))
        }
    }

    private var exitIPCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(
                    "出口 IP",
                    systemImage: "globe.asia.australia",
                    tone: model.exitIPResultIsStale ? .warning : .accent
                ) {
                    if let family = model.state.exit.info?.addressFamily {
                        StatusBadge(family.displayName, tone: .neutral)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: VisualStyle.spacing12) {
                    exitIPSummary
                    exitIPControls
                }
                .padding(VisualStyle.spacing16)
            }
        }
    }

    private var exitIPSummary: some View {
        VStack(alignment: .leading, spacing: VisualStyle.spacing8) {
            HStack(alignment: .firstTextBaseline, spacing: VisualStyle.spacing8) {
                Text(model.state.exit.info?.ip ?? "尚未检测")
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                if model.state.exit.info != nil {
                    Button(action: copyExitIP) {
                        Image(systemName: copiedExitIP ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .iconButtonHitTarget()
                    .help(copiedExitIP ? "已复制" : "复制出口 IP")
                    .accessibilityLabel(copiedExitIP ? "已复制出口 IP" : "复制出口 IP")
                }
            }

            if let info = model.state.exit.info {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if model.state.exit.isEnriching, info.location.isEmpty {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "mappin.and.ellipse")
                    }

                    Text(
                        model.state.exit.isEnriching && info.location.isEmpty
                            ? "正在补充位置与网络信息…"
                            : (info.location.isEmpty ? "位置未返回" : info.location)
                    )
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !info.details.isEmpty {
                    Label(info.details, systemImage: "building.2")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if model.state.exit.isEnriching, !info.location.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("正在补充网络信息…")
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }

                exitIPMetadata
            } else {
                Text("检测后会显示当前出口、地址族、地区与网络服务商。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = model.state.exit.errorMessage {
                inlineMessage(
                    error,
                    systemImage: "exclamationmark.circle.fill",
                    tone: .negative
                )
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var exitIPControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: VisualStyle.spacing8) {
                exitIPModePicker
                    .frame(width: 190)
                exitIPDetectionButton
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: VisualStyle.spacing8) {
                exitIPModePicker
                    .frame(maxWidth: 320)
                exitIPDetectionButton
            }
        }
    }

    private var exitIPModePicker: some View {
        Picker("地址族", selection: exitIPDetectionModeBinding) {
            Text("自动").tag(ExitIPDetectionMode.automatic)
            Text("IPv4").tag(ExitIPDetectionMode.ipv4)
            Text("IPv6").tag(ExitIPDetectionMode.ipv6)
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .disabled(model.state.exit.isDetecting)
        .accessibilityLabel("出口 IP 地址族")
    }

    private var exitIPDetectionButton: some View {
        Button {
            model.detectExitIP()
        } label: {
            Label(
                model.state.exit.isDetecting ? "检测中…" : "检测",
                systemImage: model.state.exit.isDetecting ? "hourglass" : "arrow.clockwise"
            )
        }
        .disabled(model.state.exit.isDetecting || isProxyTransitioning)
        .accessibilityHint(model.state.isProxyRunning ? "通过本地代理检测出口" : "直接检测本机出口")
    }

    @ViewBuilder
    private var exitIPMetadata: some View {
        if let route = model.exitIPRouteDescription {
            Label(route, systemImage: exitIPRouteIcon)
                .lineLimit(1)
                .truncationMode(.middle)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }

        if let detectedAt = model.state.exit.detectedAt {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "clock")
                Text("检测于 ")
                Text(detectedAt, style: .relative)
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .help(detectedAt.formatted(date: .complete, time: .standard))
        }

        if model.exitIPResultIsStale {
            Label("结果已过期，请重新检测", systemImage: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundStyle(VisualStyle.warning)
        } else if showingPreviousExitIPResult {
            Label("上次成功结果", systemImage: "clock.arrow.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var runtimeBanner: some View {
        SurfaceCard {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: VisualStyle.spacing12) {
                    runtimeStatusSummary
                    Spacer(minLength: VisualStyle.spacing16)
                    runtimeInstallButton
                }

                VStack(alignment: .leading, spacing: VisualStyle.spacing12) {
                    runtimeStatusSummary
                    runtimeInstallButton
                }
            }
            .padding(VisualStyle.spacing16)
        }
    }

    private var runtimeStatusSummary: some View {
        HStack(alignment: .top, spacing: VisualStyle.spacing12) {
            Image(systemName: runtimeStatusIcon)
                .font(.title3)
                .foregroundStyle(runtimeStatusTone.color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(runtimeStatusTitle)
                    .font(.callout.weight(.semibold))
                Text(runtimeStatusDetail)
                    .font(.caption)
                    .foregroundStyle(
                        model.state.runtimeOperationError == nil ? Color.secondary : VisualStyle.negative
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var runtimeInstallButton: some View {
        if model.state.runtimeOperation != nil {
            Button("取消", systemImage: "xmark.circle", action: model.cancelRuntimeOperation)
                .disabled(model.state.runtimeOperation?.canCancel != true)
        } else {
            Button(
                "管理组件",
                systemImage: "shippingbox",
                action: onManageRuntime
            )
        }
    }

    private func inlineMessage(
        _ message: String,
        systemImage: String,
        tone: AppTone
    ) -> some View {
        Label(message, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(tone.color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var proxyPresentation: SidebarProxyPresentation {
        SidebarProxyPresentation(
            launchPhase: model.state.launchPhase,
            proxyCorePhase: model.state.proxyCorePhase,
            endpoint: model.state.proxyEndpoint
        )
    }

    private var connectionStatusShortTitle: String {
        switch model.state.proxyCorePhase {
        case .stopped: "未启动"
        case .validating: "校验中"
        case .starting: "启动中"
        case .running: "运行中"
        case .stopping: "停止中"
        case .failed: "异常"
        }
    }

    private var currentNodeTitle: String {
        if model.state.localProxyConfiguration.routingMode == .direct {
            return "直连模式"
        }
        if let region = selectedResult?.region, !region.isEmpty {
            return region
        }
        return selectedIP.isEmpty ? "配置默认节点" : "当前节点"
    }

    private var currentNodeDetail: String {
        if model.state.localProxyConfiguration.routingMode == .direct {
            return "流量直接连接，不经过代理节点"
        }
        if selectedIP.isEmpty {
            return "使用代理配置中的服务器或 Provider"
        }
        return selectedIP
    }

    private var currentNodeIcon: String {
        model.state.localProxyConfiguration.routingMode == .direct
            ? "arrow.up.right"
            : "network"
    }

    private var currentNodeTone: AppTone {
        if model.state.localProxyConfiguration.routingMode == .direct { return .neutral }
        return selectedIP.isEmpty ? .neutral : .accent
    }

    private var selectedResult: ViaSixCore.SpeedTestResult? {
        if let result = model.state.configurationTest.result, result.ip == selectedIP {
            return result
        }
        return model.state.selectedResult
    }

    private var selectedIP: String {
        model.state.preferences.selectedIP
    }

    private var proxyEndpoint: String {
        model.state.proxyEndpoint.displayAddress
    }

    private func performProxyPrimaryAction() {
        switch proxyPresentation.action {
        case .startProxy:
            model.startProxy()
        case .stopProxy:
            model.stopProxy()
        case .none:
            break
        }
    }

    private var displayedRoutingMode: ProxyRoutingMode {
        optimisticRoutingMode ?? model.state.localProxyConfiguration.routingMode
    }

    private var routingModePickerDisabled: Bool {
        guard model.state.launchPhase == .ready else { return true }
        if model.isRoutingModeChanging
            || model.isSystemProxyTransitioning
            || model.isMihomoActionBusy
            || model.state.runtimeOperation != nil
            || model.isTemplateOperationBusy
            || model.switchingIP != nil
        {
            return true
        }
        switch model.state.proxyCorePhase {
        case .stopped, .running, .failed:
            return false
        case .validating, .starting, .stopping:
            return true
        }
    }

    private func selectRoutingMode(_ mode: ProxyRoutingMode) {
        guard mode != displayedRoutingMode, !routingModePickerDisabled else { return }
        model.setRoutingMode(mode)
        optimisticRoutingMode = model.isRoutingModeChanging ? mode : nil
    }

    private var systemProxyEnabledBinding: Binding<Bool> {
        Binding {
            model.state.localProxyConfiguration.networkAccessMode.usesSystemProxy
        } set: { enabled in
            model.setNetworkAccessMode(enabled ? .systemProxy : .localProxy)
        }
    }

    private var tunEnabledBinding: Binding<Bool> {
        Binding {
            model.state.localProxyConfiguration.networkAccessMode.usesVirtualInterface
        } set: { enabled in
            model.setNetworkAccessMode(enabled ? .virtualInterface : .localProxy)
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
        if model.state.isProxyRunning,
            model.state.localProxyConfiguration.networkAccessMode == .virtualInterface
        {
            return true
        }
        return switch model.state.systemProxyPhase {
        case .enabling, .disabling:
            true
        case .disabled, .enabled, .failed:
            false
        }
    }

    private var tunToggleDisabled: Bool {
        guard model.state.launchPhase == .ready else { return true }
        if model.isRoutingModeChanging
            || model.isSystemProxyTransitioning
            || model.isTunTransitioning
            || model.state.runtimeOperation != nil
            || model.isTemplateOperationBusy
            || model.switchingIP != nil
            || model.state.isProxyRunning
        {
            return true
        }
        switch model.state.proxyCorePhase {
        case .validating, .starting, .stopping:
            return true
        case .stopped, .running, .failed:
            break
        }
        return !model.state.localProxyConfiguration.networkAccessMode.usesVirtualInterface
            && !model.canUseTunMode
    }

    private var tunToggleHelp: String {
        if model.state.isProxyRunning { return "请先停止代理，再切换虚拟网卡接入方式" }
        if !model.canUseTunMode { return "请先在设置中安装、批准并准备虚拟网卡服务" }
        return model.state.localProxyConfiguration.networkAccessMode.usesVirtualInterface
            ? "关闭虚拟网卡，改为仅保留本地监听"
            : "使用 TUN 接管系统流量"
    }

    private var tunStatusText: String {
        switch model.state.tun.sessionPhase {
        case .inactive: model.canUseTunMode ? "已就绪" : "未就绪"
        case .starting: "正在启动"
        case .running: "运行中"
        case .stopping: "正在停止"
        case .recovering: "正在恢复"
        case .recoveryRequired: "需要恢复"
        case .failed: "运行异常"
        }
    }

    private var networkAccessStatusText: String {
        switch model.state.localProxyConfiguration.networkAccessMode {
        case .localProxy: "仅本地监听"
        case .systemProxy: systemProxyStatusText
        case .virtualInterface: tunStatusText
        }
    }

    private var networkAccessTone: AppTone {
        switch model.state.localProxyConfiguration.networkAccessMode {
        case .localProxy: .neutral
        case .systemProxy: systemProxyPresentation.appTone
        case .virtualInterface:
            switch model.state.tun.sessionPhase {
            case .running: .positive
            case .starting, .stopping, .recovering: .accent
            case .recoveryRequired: .warning
            case .failed: .negative
            case .inactive: model.canUseTunMode ? .accent : .warning
            }
        }
    }

    private var networkAccessStatusSystemImage: String? {
        switch model.state.localProxyConfiguration.networkAccessMode {
        case .localProxy: "circle"
        case .systemProxy: systemProxyIsTransitioning ? "hourglass" : nil
        case .virtualInterface:
            switch model.state.tun.sessionPhase {
            case .running: "checkmark.circle.fill"
            case .starting, .stopping, .recovering: "hourglass"
            case .recoveryRequired: "exclamationmark.circle.fill"
            case .failed: "xmark.circle.fill"
            case .inactive: model.canUseTunMode ? "checkmark.circle" : "exclamationmark.circle.fill"
            }
        }
    }

    private var networkAccessFooter: String {
        switch model.state.localProxyConfiguration.networkAccessMode {
        case .localProxy:
            "仅提供回环地址上的 mixed 代理端口，不修改 macOS 网络设置。"
        case .systemProxy:
            "系统代理不会接管不遵循 macOS 代理设置的应用流量。"
        case .virtualInterface:
            "TUN 由固定签名内核管理路由与 DNS，可接管不支持系统代理的应用流量。"
        }
    }

    private var systemProxyStatusText: String {
        systemProxyPresentation.text
    }

    private var systemProxyIsTransitioning: Bool {
        systemProxyPresentation.isTransitioning
    }

    private var systemProxyPresentation: SystemProxyStatusPresentation {
        SystemProxyStatusPresentation(
            phase: model.state.systemProxyPhase,
            isRequested: model.state.localProxyConfiguration.networkAccessMode.usesSystemProxy
        )
    }

    private var exitIPDetectionModeBinding: Binding<ExitIPDetectionMode> {
        Binding {
            model.exitIPDetectionMode
        } set: { mode in
            model.exitIPDetectionMode = mode
        }
    }

    private var showingPreviousExitIPResult: Bool {
        guard model.state.exit.info != nil else { return false }
        return model.state.exit.isDetecting || model.state.exit.errorMessage != nil
    }

    private var exitIPRouteIcon: String {
        guard let route = model.state.exit.context?.route else { return "arrow.left.arrow.right" }
        switch route {
        case .direct:
            return "arrow.up.right"
        case .proxy:
            return "point.3.connected.trianglepath.dotted"
        }
    }

    private var isProxyTransitioning: Bool {
        switch model.state.proxyCorePhase {
        case .validating, .starting, .stopping:
            true
        case .stopped, .running, .failed:
            false
        }
    }

    private var proxyToggleDisabled: Bool {
        guard model.state.launchPhase == .ready else { return true }
        if model.state.runtimeOperation != nil || model.isTemplateOperationBusy { return true }
        switch model.state.proxyCorePhase {
        case .stopping:
            return true
        case .validating, .starting, .running:
            return false
        case .stopped, .failed:
            return model.switchingIP != nil
                || (model.state.localProxyConfiguration.networkAccessMode == .virtualInterface
                    && model.hasForeignTunSession)
                || !model.activeProxyRuntimeIsAvailable
                || !model.isProxyConfigurationReady
        }
    }

    private var proxyReadinessHint: String {
        switch model.state.proxyCorePhase {
        case .validating:
            return "正在校验代理配置，可取消启动。"
        case .starting:
            return "正在启动本地代理，可取消启动。"
        case .stopping:
            return "正在停止本地代理并清理网络监听。"
        case .running:
            return "本地代理正在运行。"
        case .stopped, .failed:
            break
        }
        if model.state.runtimeOperation != nil {
            return "运行组件安装中，完成后即可启动本地代理。"
        }
        if model.isTemplateOperationBusy {
            return "代理配置操作进行中，完成后即可继续。"
        }
        if let issue = model.proxyConfigurationIssue {
            return "代理配置尚未就绪：\(issue)。请在设置中导入或编辑配置。"
        }
        if model.state.localProxyConfiguration.networkAccessMode == .virtualInterface,
            model.hasForeignTunSession
        {
            return "虚拟网卡会话正由其他登录用户使用，当前用户无法接管。"
        }
        if !model.activeProxyRuntimeIsAvailable {
            if model.state.localProxyConfiguration.networkAccessMode == .virtualInterface {
                return "虚拟网卡服务尚未就绪，请在设置中安装、批准或修复。"
            }
            return "尚未找到 Mihomo，请在设置中安装或指定路径。"
        }
        return "本地代理当前未启动。"
    }

    private func copyProxyEndpoint() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(proxyEndpoint, forType: .string)
        copiedEndpoint = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            copiedEndpoint = false
        }
    }

    private func copyExitIP() {
        guard let ip = model.state.exit.info?.ip else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ip, forType: .string)
        copiedExitIP = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            copiedExitIP = false
        }
    }

    private var runtimeNeedsAttention: Bool {
        model.state.runtimePhase != .ready
            || model.state.runtimeOperation != nil
            || model.state.runtimeOperationError != nil
            || model.runtimeIntegrityIssue != nil
    }

    private var isConfigurationTestRunning: Bool {
        switch model.state.configurationTest.phase {
        case .running, .stopping: true
        case .idle, .failed: false
        }
    }

    private var configurationTestButtonTitle: String {
        switch model.state.configurationTest.phase {
        case .running: "停止测速"
        case .stopping: "正在停止"
        case .idle, .failed: "测试当前节点"
        }
    }

    private var configurationTestButtonIcon: String {
        switch model.state.configurationTest.phase {
        case .running: "stop.fill"
        case .stopping: "hourglass"
        case .idle, .failed: "gauge.with.dots.needle.67percent"
        }
    }

    private var configurationTestButtonDisabled: Bool {
        if case .stopping = model.state.configurationTest.phase { return true }
        if isConfigurationTestRunning { return false }
        return model.currentConfigurationTestUnavailableReason != nil
    }

    private var configurationTestButtonHelp: String {
        switch model.state.configurationTest.phase {
        case .running:
            return "停止当前节点测速"
        case .stopping:
            return "正在停止当前节点测速"
        case .idle, .failed:
            if let reason = model.currentConfigurationTestUnavailableReason {
                return "暂不可测速：\(reason)"
            }
            return "沿用当前协议、端口和下载设置；候选筛选条件不会影响本次结果。"
        }
    }

    private var runtimeStatusTitle: String {
        if let operation = model.state.runtimeOperation {
            return operation.description
        }
        if model.state.runtimeOperationError != nil {
            return "运行组件操作失败"
        }
        if model.runtimeIntegrityIssue != nil {
            return "运行组件需要修复"
        }
        return switch model.state.runtimePhase {
        case .ready: "运行组件已就绪"
        case .checking: "正在检查运行组件"
        case .missing: "运行组件未安装"
        }
    }

    private var runtimeStatusDetail: String {
        if let error = model.state.runtimeOperationError {
            return error
        }
        if model.state.runtimeOperation != nil {
            return "节点测速与本地代理会在操作完成后恢复。"
        }
        if let issue = model.runtimeIntegrityIssue {
            return issue
        }
        return "CloudflareSpeedTest 与 Mihomo 可在设置中分别安装或指定自定义文件。"
    }

    private var runtimeStatusTone: AppTone {
        if model.state.runtimeOperation != nil { return .accent }
        if model.state.runtimeOperationError != nil { return .negative }
        if model.runtimeIntegrityIssue != nil { return .warning }
        return switch model.state.runtimePhase {
        case .ready: .positive
        case .checking: .neutral
        case .missing: .warning
        }
    }

    private var runtimeStatusIcon: String {
        if model.state.runtimeOperation != nil { return "arrow.down.circle" }
        if model.state.runtimeOperationError != nil { return "exclamationmark.triangle.fill" }
        if model.runtimeIntegrityIssue != nil { return "exclamationmark.triangle.fill" }
        return switch model.state.runtimePhase {
        case .ready: "checkmark.circle.fill"
        case .checking: "clock"
        case .missing: "arrow.down.circle"
        }
    }
}

private struct ConnectionMetricChip: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                VisualStyle.subtleFill,
                in: Capsule(style: .continuous)
            )
            .lineLimit(1)
    }
}

private struct OverviewPrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .padding(.horizontal, 12)
            .frame(minHeight: 30)
            .background(
                isEnabled ? VisualStyle.accent : VisualStyle.subtleFill,
                in: RoundedRectangle(
                    cornerRadius: VisualStyle.radiusSmall,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: VisualStyle.radiusSmall,
                    style: .continuous
                )
                .stroke(
                    isEnabled ? VisualStyle.accent : VisualStyle.surfaceBorder,
                    lineWidth: 1
                )
            }
            .opacity(configuration.isPressed ? 0.76 : 1)
    }
}
