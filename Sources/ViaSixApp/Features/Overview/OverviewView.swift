import SwiftUI
import ViaSixCore

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                banner

                LazyVGrid(columns: metricColumns, spacing: 14) {
                    MetricCard(
                        title: "当前节点 IP",
                        value: selectedResult?.ip ?? selectedIP,
                        detail: "Cloudflare 优选节点",
                        systemImage: "globe.asia.australia",
                        tint: .blue
                    )
                    MetricCard(
                        title: "节点地区",
                        value: selectedResult?.region ?? "",
                        detail: "数据中心地区",
                        systemImage: "mappin.and.ellipse",
                        tint: .purple
                    )
                    MetricCard(
                        title: "平均延迟",
                        value: selectedResult.map { "\($0.latency) ms" } ?? "",
                        detail: model.parameters.httping ? "HTTPing 测得" : "TCPing 测得",
                        systemImage: "gauge.with.dots.needle.50percent",
                        tint: .pink
                    )
                    MetricCard(
                        title: "下行速度",
                        value: selectedResult.map { "\($0.speed) MB/s" } ?? "",
                        detail: "CFST 下载测速",
                        systemImage: "bolt.fill",
                        tint: .green
                    )
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        proxyCard
                            .frame(maxWidth: .infinity)
                        guidanceCard
                            .frame(maxWidth: .infinity)
                    }

                    VStack(spacing: 16) {
                        proxyCard
                        guidanceCard
                    }
                }
            }
            .padding(.bottom, 4)
        }
    }

    private var banner: some View {
        ZStack(alignment: .trailing) {
            Circle()
                .fill(.white.opacity(0.09))
                .frame(width: 230, height: 230)
                .offset(x: 70, y: -64)
                .accessibilityHidden(true)

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 9) {
                    Label("ViaSix", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))
                    Text("IPv6 节点优选，一目了然")
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                    Text("节点测速、切换与本地代理都在一个应用中完成。")
                        .foregroundStyle(.white.opacity(0.76))
                }
                Spacer(minLength: 16)
                HStack(spacing: 10) {
                    Circle()
                        .fill(bannerXrayStatusColor)
                        .frame(width: 9, height: 9)
                        .accessibilityHidden(true)
                    Text(xrayStatusText)
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(.white.opacity(0.14), in: Capsule())
                .overlay { Capsule().stroke(.white.opacity(0.18)) }
            }
            .foregroundStyle(.white)
            .padding(28)
        }
        .background(VisualStyle.banner, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: VisualStyle.secondaryAccent.opacity(0.20), radius: 22, y: 9)
    }

    private var proxyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("本地代理", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)
                Spacer()
                Text(xrayStatusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(xrayStatusColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(xrayStatusColor.opacity(0.10), in: Capsule())
            }

            infoRow(label: "代理地址", value: "127.0.0.1:11451 · HTTP / SOCKS")
            infoRow(label: "节点 IP", value: selectedIP.isEmpty ? "尚未选择" : selectedIP)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("出口 IP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(model.state.exit.isDetecting ? "检测中…" : "检测") {
                        model.detectExitIP()
                    }
                    .buttonStyle(.link)
                    .disabled(model.state.exit.isDetecting || isXrayTransitioning)
                    .accessibilityHint(model.state.isXrayRunning ? "通过本地代理检测出口" : "直接检测本机出口")
                }
                Text(model.state.exit.info?.ip ?? "未检测")
                    .font(.system(.body, design: .monospaced).weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let location = model.state.exit.info?.location, !location.isEmpty {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = model.state.exit.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 9) {
                switch model.state.xrayPhase {
                case .running:
                    Button("停止", systemImage: "stop.fill", action: model.stopXray)
                    Button("重启", systemImage: "arrow.clockwise", action: model.restartXray)

                case .validating, .starting:
                    Button("取消启动", systemImage: "stop.fill", action: model.stopXray)

                case .stopping:
                    Button("正在停止…", systemImage: "hourglass") {}
                        .disabled(true)

                case .stopped, .failed:
                    Button("启动本地代理", systemImage: "play.fill", action: model.startXray)
                        .buttonStyle(.borderedProminent)
                        .tint(VisualStyle.accent)
                        .disabled(
                            model.state.launchPhase != .ready
                                || model.state.runtimePhase == .installing
                        )
                }
            }

            if case .failed(let message) = model.state.xrayPhase {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .cardStyle()
    }

    private var guidanceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("使用提示", systemImage: "lightbulb")
                    .font(.headline)
                Spacer()
                runtimeStatusBadge
            }

            TipRow(number: 1, text: "在“节点优选”中配置参数并运行 IPv4 或 IPv6 测速。")
            TipRow(number: 2, text: "选择候选节点后，ViaSix 会自动应用该节点 IP。")
            TipRow(number: 3, text: "本地代理运行时切换节点会自动重启并应用新节点。")
            TipRow(number: 4, text: "ViaSix 不修改系统代理，需要在目标应用中使用 127.0.0.1:11451。")

            if model.state.runtimePhase != .ready {
                Divider()
                HStack {
                    Text("运行组件尚未就绪")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("立即安装", action: model.installRuntime)
                        .disabled(runtimeInstallationDisabled)
                }
            }
        }
        .padding(20)
        .cardStyle()
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
    }

    private var selectedResult: ViaSixCore.SpeedTestResult? {
        model.state.selectedResult
    }

    private var selectedIP: String {
        model.state.preferences.selectedIP
    }

    private var metricColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 185), spacing: 14)]
    }

    private var xrayStatusText: String {
        switch model.state.xrayPhase {
        case .stopped: "代理未启动"
        case .validating: "校验配置中"
        case .starting: "正在启动"
        case .running: "代理运行中"
        case .stopping: "正在停止"
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

    private var bannerXrayStatusColor: Color {
        if case .stopped = model.state.xrayPhase {
            return .white.opacity(0.75)
        }
        return xrayStatusColor
    }

    private var isXrayTransitioning: Bool {
        switch model.state.xrayPhase {
        case .validating, .starting, .stopping:
            true
        case .stopped, .running, .failed:
            false
        }
    }

    private var runtimeInstallationDisabled: Bool {
        guard model.state.launchPhase == .ready else { return true }
        if model.state.runtimePhase == .installing { return true }

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

    private var runtimeStatusBadge: some View {
        let (text, color): (String, Color) = switch model.state.runtimePhase {
        case .ready: ("组件就绪", .green)
        case .installing: ("安装中", .orange)
        case .checking: ("检查中", .secondary)
        case .missing: ("缺少组件", .orange)
        case .failed: ("组件异常", .red)
        }
        return Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.10), in: Capsule())
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "—" : value)
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

private struct TipRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption2.bold())
                .foregroundStyle(VisualStyle.accent)
                .frame(width: 22, height: 22)
                .background(VisualStyle.accent.opacity(0.10), in: Circle())
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
