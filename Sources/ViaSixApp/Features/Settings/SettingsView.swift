import AppKit
import SwiftUI
import ViaSixCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("设置")
                        .font(.title2.weight(.bold))
                    Text("管理运行组件、数据文件与本机可执行路径")
                        .foregroundStyle(.secondary)
                }

                runtimeCard
                pathCard
                dataCard
                aboutCard
            }
        }
    }

    private var runtimeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("运行组件", systemImage: "shippingbox")
                    .font(.headline)
                Spacer()
                runtimeBadge
            }

            componentRow(
                title: "CloudflareSpeedTest",
                version: "v\(RuntimeManifest.cfstVersion)",
                url: resolvedDisplayURL(for: .cfst),
                ready: componentReady(.cfst)
            )
            Divider()
            componentRow(
                title: "Xray-core",
                version: "v\(RuntimeManifest.xrayVersion)",
                url: resolvedDisplayURL(for: .xray),
                ready: componentReady(.xray)
            )

            HStack {
                Button("安装官方组件", systemImage: "arrow.down.circle") {
                    model.installRuntime()
                }
                .buttonStyle(.borderedProminent)
                .disabled(runtimeActionsDisabled)

                Button("导入本地组件", systemImage: "square.and.arrow.down") {
                    importRuntime()
                }
                .disabled(runtimeActionsDisabled)

                Spacer()

                if model.state.runtimePhase == .installing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text("下载内容来自项目官方 GitHub Releases，并在安装前校验固定 SHA-256。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if case .failed(let message) = model.state.runtimePhase {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .cardStyle()
    }

    private var pathCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("自定义可执行文件", systemImage: "terminal")
                .font(.headline)

            executablePicker(
                title: "CFST 路径",
                value: model.state.preferences.cfstPath,
                component: .cfst
            )
            executablePicker(
                title: "Xray 路径",
                value: model.state.preferences.xrayPath,
                component: .xray
            )

            Text("留空时依次使用 ViaSix 管理的组件、Homebrew 路径和 PATH。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .cardStyle()
    }

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("应用数据", systemImage: "folder")
                .font(.headline)
            Text(model.paths.root.path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack {
                Button("打开数据目录", systemImage: "folder.badge.gearshape") {
                    NSWorkspace.shared.open(model.paths.root)
                }
                Button("打开 Xray 模板", systemImage: "doc.text") {
                    NSWorkspace.shared.open(model.paths.templateConfig)
                }
                .disabled(!FileManager.default.fileExists(atPath: model.paths.templateConfig.path))
            }

            Text("模板仅在首次启动时复制，后续更新不会覆盖你的修改。参考模板包含原项目的连接资料，请在分发前确认其授权与安全性。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .cardStyle()
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("关于 ViaSix", systemImage: "info.circle")
                .font(.headline)
            Text("原生 macOS IPv4 / IPv6 节点优选与 Xray 控制工具。ViaSix 不会自动修改系统代理，只在 127.0.0.1:11451 启动 mixed HTTP/SOCKS 入站。")
                .foregroundStyle(.secondary)
            Text("CloudflareSpeedTest 使用 GPL-3.0；Xray-core 使用 MPL-2.0。详情见项目 THIRD_PARTY_NOTICES.md。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .cardStyle()
    }

    private var runtimeBadge: some View {
        let (label, color): (String, Color) = switch model.state.runtimePhase {
        case .checking: ("检查中", .secondary)
        case .missing: ("未就绪", .orange)
        case .installing: ("安装中", VisualStyle.accent)
        case .ready: ("已就绪", .green)
        case .failed: ("异常", .red)
        }
        return Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.10), in: Capsule())
    }

    private func componentRow(
        title: String,
        version: String,
        url: URL?,
        ready: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ready ? .green : .orange)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(title).fontWeight(.medium)
                    Text(version)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(url?.path ?? "未找到")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
    }

    private func executablePicker(
        title: String,
        value: String,
        component: RuntimeComponent
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
            HStack {
                TextField("自动查找", text: Binding(
                    get: { value },
                    set: { newValue in
                        model.setCustomExecutable(
                            component,
                            url: newValue.isEmpty ? nil : URL(fileURLWithPath: newValue)
                        )
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(title)

                Button("选择…") {
                    chooseExecutable(component)
                }
                Button {
                    model.setCustomExecutable(component, url: nil)
                } label: {
                    Image(systemName: "xmark")
                }
                .help("清除自定义路径")
                .accessibilityLabel("清除\(title)")
                .disabled(value.isEmpty)
            }
        }
    }

    private func componentReady(_ component: RuntimeComponent) -> Bool {
        resolvedDisplayURL(for: component) != nil
    }

    private func resolvedDisplayURL(for component: RuntimeComponent) -> URL? {
        let (preferredPath, managedURL, commandName): (String, URL?, String) = switch component {
        case .cfst:
            (model.state.preferences.cfstPath, model.state.runtimeStatus?.cfstURL, "cfst")
        case .xray:
            (model.state.preferences.xrayPath, model.state.runtimeStatus?.xrayURL, "xray")
        }

        var candidates: [URL] = []
        if !preferredPath.isEmpty {
            candidates.append(URL(fileURLWithPath: preferredPath))
        }
        if let managedURL {
            candidates.append(managedURL)
        }
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/\(commandName)"))
        candidates.append(URL(fileURLWithPath: "/usr/local/bin/\(commandName)"))
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map {
                URL(fileURLWithPath: String($0)).appendingPathComponent(commandName)
            })
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private var runtimeActionsDisabled: Bool {
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

    private func chooseExecutable(_ component: RuntimeComponent) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        if panel.runModal() == .OK {
            model.setCustomExecutable(component, url: panel.url)
        }
    }

    private func importRuntime() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "导入"
        if panel.runModal() == .OK {
            model.importRuntime(from: panel.urls)
        }
    }
}
