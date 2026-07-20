import AppKit
import SwiftUI
import ViaSixCore

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var copyNotice: String?

    var body: some View {
        // Keep the menu aligned with the most common macOS flow: open the full
        // app first, inspect connection state, operate the proxy, then use
        // secondary utilities and lifecycle commands.
        Button("打开 ViaSix", systemImage: "macwindow") {
            openMainWindow()
        }
        .keyboardShortcut("o")

        Divider()

        Label(xrayStatusTitle, systemImage: xrayStatusIcon)
            .lineLimit(1)
            .truncationMode(.middle)
        if !model.state.preferences.selectedIP.isEmpty {
            Label {
                Text("当前节点 \(model.state.preferences.selectedIP)")
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: "network")
            }
            .help("当前节点：\(model.state.preferences.selectedIP)")
        }

        if case .failed(let message) = model.state.xrayPhase {
            Text(message)
                .lineLimit(2)
                .foregroundStyle(.secondary)
        }

        Divider()

        runtimeOperationStatus

        if let proxyUnavailableMessage {
            Label(proxyUnavailableMessage, systemImage: "info.circle")
                .foregroundStyle(.secondary)
        }
        xrayActions

        Divider()

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

        SettingsLink {
            Label("设置…", systemImage: "gearshape")
        }

        Divider()

        Button("退出 ViaSix", systemImage: "power") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private var runtimeOperationStatus: some View {
        if let operation = model.state.runtimeOperation {
            Label(operation.description, systemImage: "shippingbox")
                .foregroundStyle(.secondary)
            if operation.canCancel {
                Button("取消组件操作", systemImage: "xmark.circle") {
                    model.cancelRuntimeOperation()
                }
            }
        } else if let error = model.state.runtimeOperationError {
            Text("组件操作失败：\(error)")
                .lineLimit(2)
                .foregroundStyle(.secondary)
            Button("重新安装最新组件", systemImage: "arrow.clockwise") {
                model.installRuntime()
            }
            .disabled(runtimeActionsDisabled)
        }
    }

    @ViewBuilder
    private var speedTestAction: some View {
        switch model.state.configurationTest.phase {
        case .running:
            Button("停止当前节点测速", systemImage: "stop.fill") {
                model.stopCurrentConfigurationTest()
            }
        case .stopping:
            Button("正在停止当前节点测速…", systemImage: "hourglass") {}
                .disabled(true)
        case .idle, .failed:
            if !model.state.preferences.selectedIP.isEmpty,
                !isFullSpeedTestActive
            {
                Button("测试当前节点", systemImage: "scope") {
                    model.startCurrentConfigurationTest()
                }
                .disabled(model.currentConfigurationTestUnavailableReason != nil)
            }
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
                    || model.state.runtimeOperation != nil
                    || model.isTemplateOperationBusy
                    || model.switchingIP != nil
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
            if case .failed(let currentMessage) = model.state.configurationTest.phase {
                Text("当前节点测速失败：\(currentMessage)")
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            } else if let result = model.state.configurationTest.result {
                Label(
                    "当前节点：\(result.performanceSummary)",
                    systemImage: "checkmark.circle"
                )
                .foregroundStyle(.secondary)
            } else {
                Text("测速失败：\(message)")
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            }
        case .idle:
            if case .failed(let message) = model.state.configurationTest.phase {
                Text("当前节点测速失败：\(message)")
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            } else if let result = model.state.configurationTest.result {
                Label(
                    "当前节点：\(result.performanceSummary)",
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

    private var isFullSpeedTestActive: Bool {
        switch model.state.speedTest.phase {
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
                    || model.state.runtimeOperation != nil
                    || model.isTemplateOperationBusy
                    || model.switchingIP != nil
                    || !model.hasXrayExecutable
                    || (model.requiresSelectedNodeForProxy
                        && model.state.preferences.selectedIP.isEmpty)
                    || !model.isProxyConfigurationReady
            )
        case .validating, .starting:
            Button("停止本地代理", systemImage: "stop.fill") {
                model.stopXray()
            }
        case .running:
            Button("停止本地代理", systemImage: "stop.fill") {
                model.stopXray()
            }
            Button("重启本地代理", systemImage: "arrow.clockwise") {
                model.restartXray()
            }
            .disabled(model.switchingIP != nil || model.isTemplateOperationBusy)
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
        guard model.state.launchPhase == .ready else { return nil }
        do {
            _ = try model.parameters.validated()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private var runtimeActionsDisabled: Bool {
        guard model.state.launchPhase == .ready else { return true }
        if model.state.runtimeOperation != nil
            || model.isTemplateOperationBusy
            || model.switchingIP != nil
            || model.isCfstBusy
        {
            return true
        }
        switch model.state.xrayPhase {
        case .validating, .starting, .running, .stopping:
            return true
        case .stopped, .failed:
            return false
        }
    }

    private var speedTestUnavailableMessage: String? {
        guard model.state.runtimeOperation == nil else { return nil }
        if model.isTemplateOperationBusy { return "代理配置操作进行中" }
        if model.switchingIP != nil { return "正在应用节点，完成后即可开始测速" }
        if let parameterValidationMessage {
            return "完整测速设置需要检查：\(parameterValidationMessage)"
        }
        guard model.state.launchPhase == .ready, !model.hasCfstExecutable else { return nil }
        return "请在设置中安装 CloudflareSpeedTest"
    }

    private var proxyUnavailableMessage: String? {
        guard model.state.runtimeOperation == nil else { return nil }
        if model.isTemplateOperationBusy { return "代理配置操作进行中" }
        if model.switchingIP != nil { return "正在应用节点" }
        switch model.state.xrayPhase {
        case .validating, .starting, .running, .stopping:
            return nil
        case .stopped, .failed:
            break
        }
        if model.requiresSelectedNodeForProxy
            && model.state.preferences.selectedIP.isEmpty
        {
            return "请先打开 ViaSix 选择节点"
        }
        if let issue = model.proxyConfigurationIssue {
            return "请在设置中修复代理配置：\(issue)"
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
