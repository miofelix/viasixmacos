import AppKit
import SwiftUI
import ViaSixCore

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var copyNotice: String?

    var body: some View {
        Label(xrayStatusTitle, systemImage: xrayStatusIcon)
        if !model.state.preferences.selectedIP.isEmpty {
            Text("当前节点 IP：\(model.state.preferences.selectedIP)")
        }

        if case .failed(let message) = model.state.xrayPhase {
            Text(message)
                .lineLimit(2)
                .foregroundStyle(.secondary)
        }

        Divider()

        if let proxyUnavailableMessage {
            Label(proxyUnavailableMessage, systemImage: "info.circle")
                .foregroundStyle(.secondary)
        }
        xrayActions

        if let speedTestUnavailableMessage {
            Label(speedTestUnavailableMessage, systemImage: "info.circle")
                .foregroundStyle(.secondary)
        }
        speedTestStatus
        speedTestAction

        Divider()

        if !model.state.preferences.selectedIP.isEmpty {
            Button("复制当前节点 IP", systemImage: "doc.on.doc") {
                copyToPasteboard(model.state.preferences.selectedIP, label: "节点 IP")
            }
        }
        Button("复制代理地址", systemImage: "doc.on.doc") {
            copyToPasteboard(proxyEndpoint, label: "代理地址")
        }

        if let copyNotice {
            Label(copyNotice, systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        }

        Divider()

        Button("打开 ViaSix", systemImage: "macwindow") {
            openMainWindow()
        }
        .keyboardShortcut("o")

        SettingsLink {
            Label("打开设置", systemImage: "gearshape")
        }

        Divider()

        Button("退出 ViaSix", systemImage: "power") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private var speedTestAction: some View {
        if isCurrentConfigurationTestActive {
            switch model.state.configurationTest.phase {
            case .running:
                Button("停止当前节点测速", systemImage: "stop.fill") {
                    model.stopCurrentConfigurationTest()
                }
            case .stopping:
                Button("正在停止当前节点测速…", systemImage: "hourglass") {}
                    .disabled(true)
            case .idle, .failed:
                EmptyView()
            }
        } else {
            fullSpeedTestAction
        }
    }

    @ViewBuilder
    private var fullSpeedTestAction: some View {
        switch model.state.speedTest.phase {
        case .idle, .failed:
            Button("开始节点测速", systemImage: "gauge.with.dots.needle.67percent") {
                model.startSpeedTest()
            }
            .disabled(
                model.state.launchPhase != .ready
                    || model.state.runtimePhase == .installing
                    || !model.hasCfstExecutable
                    || model.isCfstBusy
                    || parameterValidationMessage != nil
            )
        case .running:
            Button("停止节点测速", systemImage: "stop.fill") {
                model.stopSpeedTest()
            }
        case .stopping:
            Button("正在停止测速…", systemImage: "hourglass") {}
                .disabled(true)
        }
    }

    @ViewBuilder
    private var speedTestStatus: some View {
        if isCurrentConfigurationTestActive {
            switch model.state.configurationTest.phase {
            case .running:
                Label("正在测试当前节点…", systemImage: "gauge.with.dots.needle.67percent")
                    .foregroundStyle(.secondary)
            case .stopping:
                Label("正在停止当前节点测速…", systemImage: "hourglass")
                    .foregroundStyle(.secondary)
            case .idle, .failed:
                EmptyView()
            }
        } else {
            fullSpeedTestStatus
        }
    }

    @ViewBuilder
    private var fullSpeedTestStatus: some View {
        switch model.state.speedTest.phase {
        case .running:
            if model.state.speedTest.total > 0 {
                Label(
                    "测速进度：\(model.state.speedTest.current)/\(model.state.speedTest.total)",
                    systemImage: "gauge.with.dots.needle.67percent"
                )
                .foregroundStyle(.secondary)
            } else {
                Label("测速正在准备输出…", systemImage: "gauge.with.dots.needle.67percent")
                    .foregroundStyle(.secondary)
            }
        case .stopping:
            Label("正在停止测速…", systemImage: "hourglass")
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text("测速失败：\(message)")
                .lineLimit(2)
                .foregroundStyle(.secondary)
        case .idle:
            if case .failed(let message) = model.state.configurationTest.phase {
                Text("当前节点测速失败：\(message)")
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            } else if let result = model.state.configurationTest.result {
                Label(
                    "当前节点：\(result.latency) ms · \(result.speed) MB/s",
                    systemImage: "checkmark.circle"
                )
                .foregroundStyle(.secondary)
            }
        }
    }

    private var isCurrentConfigurationTestActive: Bool {
        switch model.state.configurationTest.phase {
        case .running, .stopping: true
        case .idle, .failed: false
        }
    }

    @ViewBuilder
    private var xrayActions: some View {
        switch model.state.xrayPhase {
        case .stopped, .failed:
            Button("启动本地代理", systemImage: "play.fill") {
                model.startXray()
            }
            .disabled(
                model.state.launchPhase != .ready
                    || model.state.runtimePhase == .installing
                    || !model.hasXrayExecutable
                    || model.state.preferences.selectedIP.isEmpty
            )
        case .validating, .starting:
            Button("停止本地代理", systemImage: "stop.fill") {
                model.stopXray()
            }
        case .running:
            Button("重启本地代理", systemImage: "arrow.clockwise") {
                model.restartXray()
            }
            Button("停止本地代理", systemImage: "stop.fill") {
                model.stopXray()
            }
        case .stopping:
            Button("正在停止本地代理…", systemImage: "hourglass") {}
                .disabled(true)
        }
    }

    private var xrayStatusTitle: String {
        let endpoint = model.state.proxyEndpoint.displayAddress
        return switch model.state.xrayPhase {
        case .stopped: "本地代理已停止 · \(endpoint)"
        case .validating: "正在检查代理配置"
        case .starting: "正在启动本地代理"
        case .running: "本地代理运行中 · \(endpoint)"
        case .stopping: "正在停止本地代理"
        case .failed: "本地代理运行异常"
        }
    }

    private var xrayStatusIcon: String {
        switch model.state.xrayPhase {
        case .running: "checkmark.circle.fill"
        case .validating, .starting, .stopping: "clock.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .stopped: "circle"
        }
    }

    private var proxyEndpoint: String {
        model.state.proxyEndpoint.displayAddress
    }

    private var parameterValidationMessage: String? {
        do {
            _ = try model.parameters.validated()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private var speedTestUnavailableMessage: String? {
        if let parameterValidationMessage {
            return "测速设置需要检查：\(parameterValidationMessage)"
        }
        guard model.state.launchPhase == .ready, !model.hasCfstExecutable else { return nil }
        return "请在设置中安装 CloudflareSpeedTest"
    }

    private var proxyUnavailableMessage: String? {
        switch model.state.xrayPhase {
        case .validating, .starting, .running, .stopping:
            return nil
        case .stopped, .failed:
            break
        }
        if model.state.preferences.selectedIP.isEmpty {
            return "请先打开 ViaSix 选择节点"
        }
        guard !model.hasXrayExecutable else { return nil }
        return "请在设置中安装 Xray-core"
    }

    private func copyToPasteboard(_ value: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)

        let notice = "已复制\(label)"
        copyNotice = notice
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if copyNotice == notice {
                copyNotice = nil
            }
        }
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
