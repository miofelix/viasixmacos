import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ViaSixCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("设置")
                        .font(.title2.weight(.bold))
                    Text("管理本地代理、运行组件与应用数据")
                        .foregroundStyle(.secondary)
                }

                proxyConfigurationCard
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

            Text("组件分别来自 CloudflareSpeedTest 与 Xray-core 的官方发布，并在安装前校验文件完整性。")
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

    private var proxyConfigurationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("代理配置", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.headline)

            Text("ViaSix 不提供代理账号或服务器。请导入你自己的 Xray JSON 配置，应用会将所选节点 IP 写入名为“proxy”的出站连接。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("导入 Xray JSON…", systemImage: "square.and.arrow.down") {
                    importXrayTemplate()
                }
                .buttonStyle(.borderedProminent)
                .disabled(proxyImportDisabled)

                Button("编辑当前配置", systemImage: "doc.text") {
                    NSWorkspace.shared.open(model.paths.templateConfig)
                }
                .disabled(
                    proxyImportDisabled
                        || !FileManager.default.fileExists(atPath: model.paths.templateConfig.path)
                )
            }

            if proxyImportDisabled {
                Text("请先停止本地代理，再导入或编辑连接配置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("导入前会检查 JSON 结构；当前配置文件保存在 ViaSix 应用数据目录中。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            }

            Text("节点列表、测速结果、偏好设置和代理配置都保存在此目录。")
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
            Text("原生 macOS IPv4 / IPv6 节点优选与本地代理工具。ViaSix 不会自动修改系统代理，本地代理地址为 127.0.0.1:11451，同时支持 HTTP 与 SOCKS。")
                .foregroundStyle(.secondary)

            HStack {
                Button("使用帮助", systemImage: "questionmark.circle") {
                    AppDocumentOpener.open(.userGuide)
                }
                Button("第三方许可", systemImage: "doc.plaintext") {
                    AppDocumentOpener.open(.thirdPartyNotices)
                }
            }
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
            (
                model.state.preferences.xrayPath,
                model.state.runtimeStatus?.xrayIsReady == true
                    ? model.state.runtimeStatus?.xrayURL
                    : nil,
                "xray"
            )
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

    private var proxyImportDisabled: Bool {
        guard model.state.launchPhase == .ready else { return true }
        return switch model.state.xrayPhase {
        case .validating, .starting, .running, .stopping:
            true
        case .stopped, .failed:
            false
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

    private func importXrayTemplate() {
        let panel = NSOpenPanel()
        panel.title = "导入代理配置"
        panel.message = "选择包含“proxy”出站连接的 Xray JSON 配置。"
        panel.prompt = "导入"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            model.importXrayTemplate(from: url)
        }
    }
}
