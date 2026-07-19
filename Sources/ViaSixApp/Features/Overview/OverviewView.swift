import SwiftUI
import ViaSixCore

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
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
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("总览")
                .font(.title2.weight(.semibold))
            Text("节点与本地代理状态")
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
                detail: model.parameters.httping ? "HTTPing" : "TCPing",
                systemImage: "timer"
            )
            OverviewMetric(
                title: "下行速度",
                value: selectedResult.map { "\($0.speed) MB/s" } ?? "",
                detail: "测速结果",
                systemImage: "arrow.down"
            )
        }
        .padding(18)
        .cardStyle()
    }

    private var proxyPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(.secondary)
                Text("本地代理")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(xrayStatusColor)
                    .frame(width: 7, height: 7)
                Text(xrayStatusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 15)

            Divider()

            detailRow(label: "代理地址", value: proxyEndpoint)
            Divider()
            detailRow(label: "协议", value: "HTTP / SOCKS")
            Divider()

            HStack(alignment: .center, spacing: 12) {
                Text("出口 IP")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 62, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.state.exit.info?.ip ?? "未检测")
                        .font(.system(.callout, design: .monospaced).weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let location = model.state.exit.info?.location, !location.isEmpty {
                        Text(location)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let error = model.state.exit.errorMessage {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()

                Button(model.state.exit.isDetecting ? "检测中…" : "检测") {
                    model.detectExitIP()
                }
                .disabled(model.state.exit.isDetecting || isXrayTransitioning)
                .accessibilityHint(model.state.isXrayRunning ? "通过本地代理检测出口" : "直接检测本机出口")
            }
            .padding(.vertical, 11)

            Divider()

            HStack(spacing: 9) {
                proxyActions
                Spacer()
            }
            .padding(.top, 14)

            if case .failed(let message) = model.state.xrayPhase {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
        .padding(18)
        .cardStyle()
    }

    @ViewBuilder
    private var proxyActions: some View {
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
                .disabled(
                    model.state.launchPhase != .ready
                        || model.state.runtimePhase == .installing
                )
        }
    }

    private var runtimePanel: some View {
        HStack(spacing: 12) {
            Image(systemName: runtimeStatusIcon)
                .foregroundStyle(runtimeStatusColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(runtimeStatusTitle)
                    .font(.callout.weight(.medium))
                Text("节点测速与本地代理需要运行组件。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("安装", systemImage: "arrow.down.circle", action: model.installRuntime)
                .disabled(runtimeInstallationDisabled)
        }
        .padding(14)
        .cardStyle()
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.vertical, 10)
    }

    private var selectedResult: ViaSixCore.SpeedTestResult? {
        model.state.selectedResult
    }

    private var selectedIP: String {
        model.state.preferences.selectedIP
    }

    private var proxyEndpoint: String {
        "\(AppMetadata.proxyHost):\(AppMetadata.proxyPort)"
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
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
