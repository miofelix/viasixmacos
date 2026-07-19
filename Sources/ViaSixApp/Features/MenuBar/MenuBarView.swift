import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("打开 ViaSix", systemImage: "macwindow") {
            openMainWindow()
        }
        .keyboardShortcut("o")

        Divider()

        Label(xrayStatusTitle, systemImage: xrayStatusIcon)
        if !model.state.preferences.selectedIP.isEmpty {
            Text("当前节点：\(model.state.preferences.selectedIP)")
        }

        Divider()

        speedTestAction
        xrayActions

        Divider()

        Button("退出 ViaSix", systemImage: "power") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private var speedTestAction: some View {
        switch model.state.speedTest.phase {
        case .idle, .failed:
            Button("开始节点测速", systemImage: "gauge.with.dots.needle.67percent") {
                model.startSpeedTest()
            }
            .disabled(
                model.state.launchPhase != .ready
                    || model.state.runtimePhase == .installing
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
    private var xrayActions: some View {
        switch model.state.xrayPhase {
        case .stopped, .failed:
            Button("启动 Xray", systemImage: "play.fill") {
                model.startXray()
            }
            .disabled(
                model.state.launchPhase != .ready
                    || model.state.runtimePhase == .installing
            )
        case .validating, .starting:
            Button("停止 Xray", systemImage: "stop.fill") {
                model.stopXray()
            }
        case .running:
            Button("重启 Xray", systemImage: "arrow.clockwise") {
                model.restartXray()
            }
            Button("停止 Xray", systemImage: "stop.fill") {
                model.stopXray()
            }
        case .stopping:
            Button("正在停止 Xray…", systemImage: "hourglass") {}
                .disabled(true)
        }
    }

    private var xrayStatusTitle: String {
        switch model.state.xrayPhase {
        case .stopped: "Xray 已停止 · 127.0.0.1:11451"
        case .validating: "正在校验 Xray 配置"
        case .starting: "正在启动 Xray"
        case .running: "Xray 运行中 · 127.0.0.1:11451"
        case .stopping: "正在停止 Xray"
        case .failed: "Xray 运行异常"
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

    private func openMainWindow() {
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
