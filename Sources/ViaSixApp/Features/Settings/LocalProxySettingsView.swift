import SwiftUI
import ViaSixCore

struct LocalProxySettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var configuration = LocalProxyConfiguration()
    @State private var originalConfiguration: LocalProxyConfiguration?
    @State private var portText = "11451"
    @State private var controllerPortText = "9090"
    @State private var tunMTUText = "1500"
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showsDiscardConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            AppPageHeader("本机代理", subtitle: "本地监听、TUN 参数与连接行为") {
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
                transportPolicySection
                listenerSection
                tunSection
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

    private var transportPolicySection: some View {
        ConfigurationSection("IPv6 代理入口", systemImage: "6.circle") {
            Label("远程代理地址仅允许 IPv6", systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.green)

            Text("规则模式和全局模式使用当前 IPv6 节点；直连模式不加载远程代理。代理模式、系统代理和虚拟网卡开关位于首页。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var tunSection: some View {
        ConfigurationSection(
            "虚拟网卡",
            systemImage: "point.3.filled.connected.trianglepath.dotted"
        ) {
            localRow("网络栈") {
                Picker("TUN 网络栈", selection: $configuration.tunStack) {
                    ForEach(VirtualInterfaceStack.allCases, id: \.self) { stack in
                        Text(stack.displayName).tag(stack)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .disabled(isSaving)
            }

            localRow("MTU") {
                TextField("1500", text: $tunMTUText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)
            }

            behaviorRow(
                "严格路由",
                detail: "加强路由规则，减少流量绕过 TUN；与部分 VPN 共存时可关闭",
                isOn: $configuration.tunStrictRoute
            )

            Text("Mixed 适合日常使用；System 偏向原生栈，gVisor 可用于兼容性排查。TUN 自动管理路由、DNS 劫持与回环防护。")
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
            || tunMTUText != String(originalConfiguration.tunMTU)
    }

    private var tunAvailabilityDescription: String {
        switch model.state.tun.servicePhase {
        case .checking:
            "正在检查虚拟网卡服务。"
        case .notInstalled:
            "虚拟网卡服务尚未安装，请关闭此窗口后在设置中安装。"
        case .requiresApproval:
            "虚拟网卡服务等待系统批准，请在系统设置的登录项中允许。"
        case .unavailable(let detail):
            "虚拟网卡服务不可用：\(detail)"
        case .ready:
            switch model.state.tun.runtimePhase {
            case .notInstalled: "特权 Mihomo 尚未安装，请在设置中安装。"
            case .repairRequired: "特权 Mihomo 需要修复。"
            case .failed(let detail): "特权 Mihomo 不可用：\(detail)"
            case .unknown, .installing: "正在准备特权 Mihomo。"
            case .ready: "虚拟网卡服务能力不完整，请刷新或修复。"
            }
        }
    }

    private func load() {
        do {
            let data = try Data(contentsOf: model.paths.localProxyConfig)
            configuration = try JSONDecoder().decode(LocalProxyConfiguration.self, from: data).validated()
            portText = String(configuration.port)
            controllerPortText = String(configuration.controllerPort)
            tunMTUText = String(configuration.tunMTU)
        } catch {
            configuration = model.state.localProxyConfiguration
            portText = String(configuration.port)
            controllerPortText = String(configuration.controllerPort)
            tunMTUText = String(configuration.tunMTU)
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
        guard let tunMTU = Int(tunMTUText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "TUN MTU 必须是数字。"
            return
        }
        configuration.tunMTU = tunMTU
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
