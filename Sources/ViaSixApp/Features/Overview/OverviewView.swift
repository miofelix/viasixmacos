import AppKit
import SwiftUI
import ViaSixCore

struct OverviewView: View {
    @Environment(AppModel.self) private var model
    let onSelectNodes: () -> Void

    @State private var copiedEndpoint = false
    @State private var copiedExitIP = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                pageHeader
                metricsPanel
                proxyPanel

                if model.state.runtimePhase != .ready {
                    runtimePanel
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)
        }
        .scrollbarSafeContent()
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("连接")
                .font(.title2.weight(.semibold))
            Text("管理本地代理、当前节点与网络出口")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var metricsPanel: some View {
        LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 18) {
            OverviewMetric(
                title: "当前节点",
                value: selectedResult?.ip ?? selectedIP,
                detail: "Cloudflare IP",
                systemImage: "network"
            )
            OverviewMetric(
                title: "地区",
                value: selectedResult?.region ?? "",
                detail: "数据中心",
                systemImage: "mappin"
            )
            OverviewMetric(
                title: "平均延迟",
                value: selectedResult.map { "\($0.latency) ms" } ?? "",
                detail: speedTestProtocolLabel,
                systemImage: "timer"
            )
            OverviewMetric(
                title: "下行速度",
                value: selectedResult.map { "\($0.speed) MB/s" } ?? "",
                detail: "测速结果",
                systemImage: "arrow.down"
            )
        }
        .padding(22)
        .cardStyle()
    }

    private var proxyPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            proxyHeader

            Divider()

            proxyEndpointRow
            Divider()
            detailRow(label: "协议", value: "HTTP / SOCKS")
            Divider()

            exitIPPanel

            Divider()

            proxyActionsRow

            if case .failed(let message) = model.state.configurationTest.phase {
                Text("当前节点测速失败：\(message)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            if !model.state.isXrayRunning {
                Label(proxyReadinessHint, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }

            if case .failed(let message) = model.state.xrayPhase {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
        .padding(22)
        .cardStyle()
    }

    private var proxyHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 9) {
                proxyIdentity
                Spacer(minLength: 16)
                proxyStatus
                proxyToggle
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    proxyIdentity
                    Spacer(minLength: 12)
                    proxyStatus
                }

                HStack {
                    Spacer(minLength: 0)
                    proxyToggle
                }
            }
        }
        .padding(.bottom, 15)
    }

    private var proxyIdentity: some View {
        HStack(spacing: 9) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundStyle(.secondary)
            Text("本地代理")
                .font(.headline)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var proxyStatus: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(xrayStatusColor)
                .frame(width: 7, height: 7)
            Text(xrayStatusText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var proxyToggle: some View {
        Toggle("本地代理", isOn: proxyEnabledBinding)
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(proxyToggleDisabled)
            .accessibilityLabel("本地代理")
            .accessibilityValue(xrayStatusText)
    }

    private var proxyEndpointRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                proxyEndpointLabel
                proxyEndpointValue
                Spacer(minLength: 0)
                copyProxyEndpointButton
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    proxyEndpointLabel
                    Spacer(minLength: 0)
                    copyProxyEndpointButton
                }
                proxyEndpointValue
            }
        }
        .padding(.vertical, 10)
    }

    private var proxyEndpointLabel: some View {
        Text("代理地址")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: 72, alignment: .leading)
    }

    private var proxyEndpointValue: some View {
        Text(proxyEndpoint)
            .font(.system(.callout, design: .monospaced).weight(.medium))
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .layoutPriority(1)
    }

    private var copyProxyEndpointButton: some View {
        Button(action: copyProxyEndpoint) {
            Image(systemName: copiedEndpoint ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .iconButtonHitTarget()
        .help(copiedEndpoint ? "已复制" : "复制代理地址")
        .accessibilityLabel(copiedEndpoint ? "已复制代理地址" : "复制代理地址")
    }

    private var proxyActionsRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 9) {
                proxyActionButtons
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 9) {
                proxyActionButtons
            }
        }
        .padding(.top, 14)
    }

    @ViewBuilder
    private var proxyActionButtons: some View {
        Button("选择节点", systemImage: "network", action: onSelectNodes)

        Button(configurationTestButtonTitle, systemImage: configurationTestButtonIcon) {
            if isConfigurationTestRunning {
                model.stopCurrentConfigurationTest()
            } else {
                model.startCurrentConfigurationTest()
            }
        }
        .disabled(configurationTestButtonDisabled)

        if model.state.isXrayRunning {
            Button("重新连接", systemImage: "arrow.clockwise", action: model.restartXray)
        }
    }

    private var runtimePanel: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                runtimeStatusSummary
                Spacer(minLength: 16)
                runtimeInstallButton
            }

            VStack(alignment: .leading, spacing: 12) {
                runtimeStatusSummary
                runtimeInstallButton
            }
        }
        .padding(18)
        .cardStyle()
    }

    private var runtimeStatusSummary: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: runtimeStatusIcon)
                .foregroundStyle(runtimeStatusColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(runtimeStatusTitle)
                    .font(.callout.weight(.medium))
                Text("节点测速与本地代理需要运行组件。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var runtimeInstallButton: some View {
        Button("安装", systemImage: "arrow.down.circle", action: model.installRuntime)
            .disabled(runtimeInstallationDisabled)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.vertical, 10)
    }

    private var exitIPPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    exitIPLabel
                    exitIPSummary
                }

                VStack(alignment: .leading, spacing: 8) {
                    exitIPLabel
                    exitIPSummary
                }
            }

            exitIPControls
        }
        .padding(.vertical, 11)
    }

    private var exitIPLabel: some View {
        Text("出口 IP")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: 72, alignment: .leading)
    }

    private var exitIPControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 9) {
                Spacer()
                    .frame(width: 84)
                exitIPModePicker
                    .frame(width: 190)
                exitIPDetectionButton
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 9) {
                exitIPModePicker
                    .frame(maxWidth: 320)
                exitIPDetectionButton
            }
            .padding(.leading, 84)
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
        .disabled(model.state.exit.isDetecting || isXrayTransitioning)
        .accessibilityHint(model.state.isXrayRunning ? "通过本地代理检测出口" : "直接检测本机出口")
    }

    private var exitIPSummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.state.exit.info?.ip ?? "未检测")
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                if let family = model.state.exit.info?.addressFamily {
                    Text(family.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                }

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
                            .foregroundStyle(.secondary)
                    }
                    Text(
                        model.state.exit.isEnriching && info.location.isEmpty
                            ? "正在补充位置与网络信息…"
                            : (info.location.isEmpty ? "位置未返回" : info.location)
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if !info.details.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "building.2")
                            .foregroundStyle(.tertiary)
                        Text(info.details)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
            }

            if let error = model.state.exit.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var exitIPMetadata: some View {
        if let route = model.exitIPRouteDescription {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: exitIPRouteIcon)
                    .foregroundStyle(.tertiary)
                Text(route)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }

        if let detectedAt = model.state.exit.detectedAt {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "clock")
                    .foregroundStyle(.tertiary)
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
                .foregroundStyle(.orange)
        } else if showingPreviousExitIPResult {
            Label("上次成功结果", systemImage: "clock.arrow.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private var selectedResult: ViaSixCore.SpeedTestResult? {
        if let result = model.state.configurationTest.result, result.ip == selectedIP {
            return result
        }
        return model.state.selectedResult
    }

    private var speedTestProtocolLabel: String {
        if let result = model.state.configurationTest.result, result.ip == selectedIP {
            guard let parameters = model.state.configurationTest.parameters else {
                return "当前节点测速"
            }
            return parameters.httping ? "HTTPing" : "TCPing"
        }
        guard model.state.speedTestResultsAreCurrent else { return "需重新测速" }
        return model.parameters.httping ? "HTTPing" : "TCPing"
    }

    private var selectedIP: String {
        model.state.preferences.selectedIP
    }

    private var proxyEndpoint: String {
        model.state.proxyEndpoint.displayAddress
    }

    private var proxyEnabledBinding: Binding<Bool> {
        Binding {
            model.state.isXrayRunning
        } set: { enabled in
            if enabled {
                model.startXray()
            } else {
                model.stopXray()
            }
        }
    }

    private var exitIPDetectionModeBinding: Binding<ExitIPDetectionMode> {
        Binding {
            model.exitIPDetectionMode
        } set: { mode in
            model.exitIPDetectionMode = mode
        }
    }

    private var metricColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 145), spacing: 22)]
    }

    private var xrayStatusText: String {
        switch model.state.xrayPhase {
        case .stopped: "未启动"
        case .validating: "校验中"
        case .starting: "启动中"
        case .running: "运行中"
        case .stopping: "停止中"
        case .failed: "运行异常"
        }
    }

    private var xrayStatusColor: Color {
        switch model.state.xrayPhase {
        case .running: .green
        case .validating, .starting, .stopping: .orange
        case .stopped: .secondary
        case .failed: .red
        }
    }

    private var isXrayTransitioning: Bool {
        switch model.state.xrayPhase {
        case .validating, .starting, .stopping:
            true
        case .stopped, .running, .failed:
            false
        }
    }

    private var proxyToggleDisabled: Bool {
        model.state.launchPhase != .ready
            || model.state.runtimePhase == .installing
            || isXrayTransitioning
            || (!model.state.isXrayRunning
                && (selectedIP.isEmpty || !model.hasXrayExecutable))
    }

    private var proxyReadinessHint: String {
        if model.state.runtimePhase == .installing {
            return "运行组件安装中，完成后即可启动本地代理。"
        }
        if selectedIP.isEmpty {
            return "先选择一个节点，才能启动本地代理。"
        }
        if !model.hasXrayExecutable {
            return "尚未找到 Xray-core，请在设置中安装或指定路径。"
        }
        return "代理已停止，打开右侧开关即可启动。"
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

    private var runtimeInstallationDisabled: Bool {
        guard model.state.launchPhase == .ready else { return true }
        if model.state.runtimePhase == .installing { return true }
        if model.isCfstBusy { return true }

        switch model.state.speedTest.phase {
        case .running, .stopping:
            return true
        case .idle, .failed:
            break
        }

        switch model.state.xrayPhase {
        case .validating, .starting, .running, .stopping:
            return true
        case .stopped, .failed:
            return false
        }
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
        return model.state.runtimePhase == .installing
            || selectedIP.isEmpty
            || !model.hasCfstExecutable
            || model.isCfstBusy
    }

    private var runtimeStatusTitle: String {
        switch model.state.runtimePhase {
        case .ready: "运行组件已就绪"
        case .installing: "正在安装运行组件"
        case .checking: "正在检查运行组件"
        case .missing: "运行组件未安装"
        case .failed: "运行组件异常"
        }
    }

    private var runtimeStatusColor: Color {
        switch model.state.runtimePhase {
        case .ready: .green
        case .checking: .secondary
        case .missing, .installing: .orange
        case .failed: .red
        }
    }

    private var runtimeStatusIcon: String {
        switch model.state.runtimePhase {
        case .ready: "checkmark.circle.fill"
        case .checking, .installing: "clock"
        case .missing: "arrow.down.circle"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
}

private struct OverviewMetric: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "—" : value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
