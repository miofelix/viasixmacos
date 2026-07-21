import SwiftUI
import ViaSixCore

struct LocalProxySettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var configuration = LocalProxyConfiguration()
    @State private var originalConfiguration: LocalProxyConfiguration?
    @State private var portText = "11451"
    @State private var controllerPortText = "9090"
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showsDiscardConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            AppPageHeader("本机代理", subtitle: "代理模式、macOS 接入与本地监听") {
                Button {
                    requestDismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .iconButtonHitTarget()
                .help("关闭")
                .accessibilityLabel("关闭本机代理设置")
                .keyboardShortcut(.cancelAction)
                .disabled(isSaving)
            }
            .padding(.horizontal, VisualStyle.spacing20)
            .padding(.vertical, VisualStyle.spacing4)
            Divider()

            if isLoading {
                ProgressView("正在读取本机设置…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                editor
            }
        }
        .frame(minWidth: 680, minHeight: 620)
        .background(VisualStyle.pageBackground)
        .task { load() }
        .interactiveDismissDisabled(isSaving || hasUnsavedChanges)
        .alert("放弃未保存的更改？", isPresented: $showsDiscardConfirmation) {
            Button("继续编辑", role: .cancel) {}
            Button("放弃更改", role: .destructive) { dismiss() }
        } message: {
            Text("关闭后，本次对本机代理设置的修改将不会保留。")
        }
    }

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VisualStyle.spacing16) {
                LazyVGrid(
                    columns: [
                        GridItem(
                            .flexible(),
                            spacing: VisualStyle.spacing16,
                            alignment: .top
                        ),
                        GridItem(.flexible(), alignment: .top),
                    ],
                    alignment: .leading,
                    spacing: VisualStyle.spacing16
                ) {
                    routingModeSection
                    networkAccessSection
                }

                listenerSection
                behaviorSection

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                editorFooter
            }
            .padding(VisualStyle.spacing20)
        }
        .scrollbarSafeContent()
    }

    private var routingModeSection: some View {
        ConfigurationSection("代理模式", systemImage: configuration.routingMode.appSystemImage) {
            ProxyRoutingModePicker(
                selection: $configuration.routingMode,
                isDisabled: isSaving,
                showsDescription: false
            )
            Text(configuration.routingMode.appDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var networkAccessSection: some View {
        ConfigurationSection("网络接入", systemImage: "network") {
            Picker("网络接入", selection: $configuration.networkAccessMode) {
                ForEach(NetworkAccessMode.allCases, id: \.self) { mode in
                    Text(mode.displayName)
                        .tag(mode)
                        .disabled(mode == .virtualInterface)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(isSaving)

            Text(networkAccessDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(systemProxyCurrentStateDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var listenerSection: some View {
        ConfigurationSection("本地监听", systemImage: "dot.radiowaves.left.and.right") {
            localRow("监听地址") {
                TextField("127.0.0.1", text: $configuration.listenAddress)
                    .textFieldStyle(.roundedBorder)
            }
            localRow("监听端口") {
                TextField("11451", text: $portText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)
            }
            localRow("内核控制端口") {
                TextField("9090", text: $controllerPortText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)
            }
            Text("仅允许 localhost、127.0.0.0/8 或 ::1。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Controller 仅绑定 127.0.0.1，并使用 ViaSix 自动生成的本机密钥。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var behaviorSection: some View {
        ConfigurationSection("连接行为", systemImage: "switch.2") {
            behaviorRow(
                "UDP",
                detail: "允许兼容客户端通过本地代理转发 UDP",
                isOn: $configuration.udpEnabled
            )
            Divider()
            behaviorRow(
                "协议嗅探",
                detail: "识别连接中的域名以改善路由判断",
                isOn: $configuration.sniffingEnabled
            )
            Divider()
            behaviorRow(
                "私有地址直连",
                detail: "局域网与本机地址不经过代理服务器",
                isOn: $configuration.bypassPrivateNetworks
            )
            Divider()
            SettingRow("日志级别", detail: "代理内核运行日志") {
                Picker("代理日志级别", selection: $configuration.logLevel) {
                    ForEach(ProxyLogLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 130)
                .disabled(isSaving)
            }
        }
    }

    private func behaviorRow(
        _ title: String,
        detail: String,
        isOn: Binding<Bool>
    ) -> some View {
        SettingRow(title, detail: detail) {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .disabled(isSaving)
        }
    }

    private var editorFooter: some View {
        HStack(spacing: VisualStyle.spacing12) {
            Label(endpointSummary, systemImage: "dot.radiowaves.left.and.right")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            Spacer()

            Button("取消") { requestDismiss() }
                .disabled(isSaving)

            Button {
                save()
            } label: {
                HStack(spacing: 6) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isSaving ? "正在保存…" : "保存本机设置")
                }
                .frame(minWidth: 104)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("s", modifiers: .command)
            .disabled(isSaving)
        }
        .padding(.top, VisualStyle.spacing4)
    }

    private func localRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: VisualStyle.spacing12) {
            Text(title)
                .font(.callout.weight(.medium))
                .frame(width: 112, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: VisualStyle.controlHeight)
    }

    private var endpointSummary: String {
        let host = configuration.listenAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayHost = host.isEmpty ? "未填写地址" : host
        return "\(displayHost):\(portText)"
    }

    private var hasUnsavedChanges: Bool {
        guard let originalConfiguration else { return false }
        return configuration != originalConfiguration
            || portText != String(originalConfiguration.port)
            || controllerPortText != String(originalConfiguration.controllerPort)
    }

    private var systemProxyCurrentStateDescription: String {
        let presentation = SystemProxyStatusPresentation(
            phase: model.state.systemProxyPhase,
            isRequested: model.state.localProxyConfiguration.networkAccessMode.usesSystemProxy
        )
        if case .failed(let message) = model.state.systemProxyPhase {
            return "当前状态：\(presentation.text)。\(message)"
        }
        return "当前状态：\(presentation.text)。"
    }

    private var networkAccessDescription: String {
        switch configuration.networkAccessMode {
        case .localProxy:
            "仅提供本机 mixed 代理端口，不修改 macOS 网络设置。"
        case .systemProxy:
            "本地代理运行后自动配置 macOS 系统代理。"
        case .virtualInterface:
            "接管支持 TUN 的应用流量；需要安装并授权虚拟网卡服务。"
        }
    }

    private func load() {
        do {
            let data = try Data(contentsOf: model.paths.localProxyConfig)
            configuration = try JSONDecoder().decode(LocalProxyConfiguration.self, from: data).validated()
            portText = String(configuration.port)
            controllerPortText = String(configuration.controllerPort)
        } catch {
            configuration = model.state.localProxyConfiguration
            portText = String(configuration.port)
            controllerPortText = String(configuration.controllerPort)
            errorMessage = "读取本机设置失败：\(error.localizedDescription)"
        }
        originalConfiguration = configuration
        isLoading = false
    }

    private func save() {
        errorMessage = nil
        guard let port = Int(portText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "监听端口必须是数字。"
            return
        }
        guard
            let controllerPort = Int(
                controllerPortText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        else {
            errorMessage = "内核控制端口必须是数字。"
            return
        }
        configuration.port = port
        configuration.controllerPort = controllerPort
        do {
            let validated = try configuration.validated()
            isSaving = true
            Task { @MainActor in
                do {
                    try await model.saveLocalProxyConfiguration(validated)
                    isSaving = false
                    dismiss()
                } catch {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func requestDismiss() {
        if hasUnsavedChanges {
            showsDiscardConfirmation = true
        } else {
            dismiss()
        }
    }
}
