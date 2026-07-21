import SwiftUI
import ViaSixCore
import ViaSixMihomoConfig

enum ServerConfigurationInputMode: String, CaseIterable, Identifiable {
    case manual
    case shareLink

    var id: Self { self }

    var title: String {
        switch self {
        case .manual: "手动配置"
        case .shareLink: "分享链接"
        }
    }
}

struct ServerConfigurationEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var profile = MihomoProxyProfile()
    @State private var originalProfile: MihomoProxyProfile?
    @State private var originalData: Data?
    @State private var inputMode: ServerConfigurationInputMode
    @State private var serverPortText = "443"
    @State private var shareLink = ""
    @State private var shareLinkError: String?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var showsDiscardConfirmation = false

    init(initialInputMode: ServerConfigurationInputMode = .manual) {
        _inputMode = State(initialValue: initialInputMode)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isLoading {
                ProgressView("正在读取服务器配置…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                loadFailureView(loadError)
            } else {
                form
            }
        }
        .frame(minWidth: 700, minHeight: editorMinimumHeight)
        .background(VisualStyle.pageBackground)
        .animation(VisualStyle.standardAnimation, value: editorMinimumHeight)
        .task { await load() }
        .onChange(of: profile.protocolName) { _, protocolName in
            applyProtocolDefaults(for: protocolName)
        }
        .interactiveDismissDisabled(isSaving || hasUnsavedChanges)
        .alert("放弃未保存的更改？", isPresented: $showsDiscardConfirmation) {
            Button("继续编辑", role: .cancel) {}
            Button("放弃更改", role: .destructive) { dismiss() }
        } message: {
            Text("关闭后，本次对服务器连接的修改将不会保留。")
        }
    }

    private var header: some View {
        AppPageHeader("服务器连接", subtitle: "远端协议、传输与安全参数") {
            Button {
                requestDismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .iconButtonHitTarget()
            .help("关闭")
            .accessibilityLabel("关闭服务器连接设置")
            .keyboardShortcut(.cancelAction)
            .disabled(isSaving)
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VisualStyle.spacing16) {
                ConfigurationSection("配置方式", systemImage: "square.and.pencil") {
                    Picker("配置方式", selection: $inputMode) {
                        ForEach(ServerConfigurationInputMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 360)
                    .disabled(isSaving)

                    if inputMode == .shareLink {
                        shareLinkForm
                    } else {
                        Text("填写服务器提供的连接参数；保存前会检查必填字段。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if inputMode == .manual {
                    manualConfigurationForm
                }

                editorFeedback
                editorFooter
            }
            .padding(VisualStyle.spacing20)
        }
        .scrollbarSafeContent()
    }

    private var shareLinkForm: some View {
        VStack(alignment: .leading, spacing: VisualStyle.spacing8) {
            HStack(spacing: VisualStyle.spacing8) {
                TextField("vless://、vmess://、trojan:// 或 ss://", text: $shareLink)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(parseShareLink)

                Button("读取并继续", systemImage: "arrow.right") {
                    parseShareLink()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    isSaving
                        || shareLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }

            if let shareLinkError {
                Label(shareLinkError, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("支持 VLESS、VMess、Trojan 和 Shadowsocks 分享链接。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, VisualStyle.spacing4)
    }

    @ViewBuilder
    private var manualConfigurationForm: some View {
        ConfigurationSection("服务器", systemImage: "server.rack") {
            serverFields
        }

        if profile.protocolName != .shadowsocks {
            ConfigurationSection("传输", systemImage: "arrow.left.arrow.right") {
                transportFields
            }

            ConfigurationSection("安全", systemImage: "lock.shield") {
                securityFields
            }
        }
    }

    @ViewBuilder
    private var serverFields: some View {
        fieldRow("协议") {
            Picker("协议", selection: $profile.protocolName) {
                ForEach(MihomoProxyProtocol.allCases, id: \.self) { protocolName in
                    Text(protocolName.displayName).tag(protocolName)
                }
            }
            .labelsHidden()
            .frame(width: 180)
        }
        fieldRow("节点名称") {
            TextField("用于在代理组中识别此节点", text: $profile.name)
                .textFieldStyle(.roundedBorder)
        }
        fieldRow("服务器地址") {
            TextField("域名或 IP", text: $profile.serverAddress)
                .textFieldStyle(.roundedBorder)
        }
        fieldRow("服务器端口") {
            TextField("443", text: $serverPortText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
        }
        fieldRow(credentialTitle) {
            if profile.protocolName == .trojan || profile.protocolName == .shadowsocks {
                SecureField(credentialPlaceholder, text: $profile.credential)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            } else {
                TextField(credentialPlaceholder, text: $profile.credential)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
        }

        switch profile.protocolName {
        case .vless:
            fieldRow("加密") {
                TextField("none", text: $profile.encryption)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
            fieldRow("Flow") {
                TextField("可选，例如 xtls-rprx-vision", text: $profile.flow)
                    .textFieldStyle(.roundedBorder)
            }
        case .vmess:
            fieldRow("Alter ID") {
                TextField("0", value: $profile.alterID, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            fieldRow("加密方式") {
                TextField("auto", text: $profile.vmessCipher)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
        case .shadowsocks:
            fieldRow("加密算法") {
                TextField("例如 chacha20-ietf-poly1305", text: $profile.encryption)
                    .textFieldStyle(.roundedBorder)
            }
        case .trojan:
            EmptyView()
        }

        fieldRow("UDP") {
            Toggle("允许此节点转发 UDP", isOn: $profile.udpEnabled)
        }
    }

    @ViewBuilder
    private var transportFields: some View {
        fieldRow("传输方式") {
            Picker("传输方式", selection: $profile.transport) {
                ForEach(MihomoTransport.allCases, id: \.self) { transport in
                    Text(transport.displayName).tag(transport)
                }
            }
            .labelsHidden()
            .frame(width: 180)
        }

        if profile.transport == .websocket || profile.transport == .http
            || profile.transport == .h2
        {
            fieldRow(transportHostTitle) {
                TextField("通常与 Server Name 相同", text: $profile.host)
                    .textFieldStyle(.roundedBorder)
            }
            fieldRow("路径") {
                TextField("/", text: $profile.path)
                    .textFieldStyle(.roundedBorder)
            }
        } else if profile.transport == .grpc {
            fieldRow("Service Name") {
                TextField("gRPC 服务名", text: $profile.serviceName)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    @ViewBuilder
    private var securityFields: some View {
        fieldRow("安全方式") {
            Picker("安全方式", selection: $profile.security) {
                ForEach(MihomoTransportSecurity.allCases, id: \.self) { security in
                    Text(security.displayName).tag(security)
                }
            }
            .labelsHidden()
            .frame(width: 180)
        }

        if profile.security != .none {
            fieldRow("Server Name") {
                TextField("TLS/REALITY 的域名", text: $profile.serverName)
                    .textFieldStyle(.roundedBorder)
            }
            fieldRow("指纹") {
                TextField("chrome", text: $profile.fingerprint)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
        }

        if profile.security == .tls {
            fieldRow("证书校验") {
                Toggle("允许不安全 TLS", isOn: $profile.allowInsecure)
                    .help("仅在服务器证书无法正常验证且你了解风险时开启")
            }
        } else if profile.security == .reality {
            fieldRow("公钥") {
                TextField("Reality publicKey", text: $profile.realityPublicKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
            fieldRow("Short ID") {
                TextField("可选", text: $profile.realityShortID)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
        }
    }

    @ViewBuilder
    private var editorFeedback: some View {
        if let saveError {
            Label(saveError, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var editorFooter: some View {
        HStack(spacing: VisualStyle.spacing12) {
            if inputMode == .manual {
                Label(
                    "\(profile.protocolName.displayName) · \(serverAddressSummary)",
                    systemImage: "server.rack"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            } else {
                Text("读取链接后可以检查并修改所有字段")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
                    Text(isSaving ? "正在保存…" : "保存服务器")
                }
                .frame(minWidth: 96)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("s", modifiers: .command)
            .disabled(isSaving || inputMode != .manual)
        }
        .padding(.top, VisualStyle.spacing4)
    }

    private var credentialTitle: String {
        profile.protocolName == .trojan || profile.protocolName == .shadowsocks
            ? "密码"
            : "UUID"
    }

    private var credentialPlaceholder: String {
        profile.protocolName == .trojan || profile.protocolName == .shadowsocks
            ? "服务器密码"
            : "服务器提供的 UUID"
    }

    private var transportHostTitle: String {
        switch profile.transport {
        case .websocket: "WebSocket Host"
        case .http: "HTTP Host"
        case .h2: "HTTP/2 Host"
        case .grpc, .tcp: "Host"
        }
    }

    private var serverAddressSummary: String {
        let address = profile.serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return address.isEmpty ? "未填写地址" : "\(address):\(serverPortText)"
    }

    private var editorMinimumHeight: CGFloat {
        if !isLoading, loadError == nil, inputMode == .shareLink {
            return 420
        }
        return 640
    }

    private var hasUnsavedChanges: Bool {
        if inputMode == .shareLink,
            !shareLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return true
        }
        guard let originalProfile else { return false }
        guard let port = Int(serverPortText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return true
        }
        var currentProfile = profile
        currentProfile.serverPort = port
        return currentProfile != originalProfile
    }

    private func loadFailureView(_ message: String) -> some View {
        VStack(spacing: VisualStyle.spacing16) {
            ContentUnavailableView(
                "无法使用表单读取当前配置",
                systemImage: "curlybraces.square",
                description: Text(message)
            )

            HStack(spacing: VisualStyle.spacing8) {
                Button("使用分享链接重新配置", systemImage: "link") {
                    beginReplacement(using: .shareLink)
                }
                .buttonStyle(.borderedProminent)

                Button("手动重新配置", systemImage: "slider.horizontal.3") {
                    beginReplacement(using: .manual)
                }

                Button("关闭") {
                    dismiss()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(VisualStyle.spacing24)
    }

    private func fieldRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: VisualStyle.spacing12) {
            Text(title)
                .font(.callout.weight(.medium))
                .frame(width: 128, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: VisualStyle.controlHeight)
    }

    private func load() async {
        guard FileManager.default.fileExists(atPath: model.paths.profileConfig.path) else {
            profile = MihomoProxyProfile()
            serverPortText = String(profile.serverPort)
            originalProfile = profile
            originalData = nil
            loadError = nil
            isLoading = false
            return
        }

        do {
            let data = try await model.loadProfileConfiguration()
            originalData = data
            profile = try MihomoGuidedProfileDraft.editableProfile(from: data)
            applyProtocolDefaults(for: profile.protocolName)
            serverPortText = String(profile.serverPort)
            originalProfile = profile
            loadError = nil
        } catch {
            loadError =
                "当前代理配置无法使用表单编辑。包含多个节点或 Proxy Provider 时，请使用高级 YAML 编辑器；也可以明确选择重新配置。\n\n\(error.localizedDescription)"
        }
        isLoading = false
    }

    private func beginReplacement(using mode: ServerConfigurationInputMode) {
        profile = MihomoProxyProfile()
        serverPortText = String(profile.serverPort)
        originalProfile = profile
        shareLink = ""
        shareLinkError = nil
        saveError = nil
        loadError = nil
        inputMode = mode
    }

    private func parseShareLink() {
        shareLinkError = nil
        do {
            profile = try MihomoShareLinkParser.profile(from: shareLink)
            applyProtocolDefaults(for: profile.protocolName)
            serverPortText = String(profile.serverPort)
            saveError = nil
            withAnimation(VisualStyle.standardAnimation) {
                inputMode = .manual
            }
        } catch {
            shareLinkError = error.localizedDescription
        }
    }

    private func applyProtocolDefaults(for protocolName: MihomoProxyProtocol) {
        if protocolName == .shadowsocks {
            profile.transport = .tcp
            profile.security = .none
            if profile.encryption == "none" {
                profile.encryption = "chacha20-ietf-poly1305"
            }
        } else if protocolName == .trojan, profile.security == .none {
            profile.security = .tls
        } else if protocolName == .vless,
            profile.encryption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            profile.encryption = "none"
        }
    }

    private func save() {
        saveError = nil
        guard let port = Int(serverPortText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            saveError = "服务器端口必须是数字。"
            return
        }
        profile.serverPort = port
        do {
            if profile.protocolName == .shadowsocks,
                profile.encryption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                saveError = "请输入 Shadowsocks 加密算法。"
                return
            }
            let data = try profile.serverConfiguration().formattedData()
            isSaving = true
            Task { @MainActor in
                do {
                    try await model.saveProfileConfiguration(
                        data,
                        expectedProfileData: originalData
                    )
                    isSaving = false
                    dismiss()
                } catch AppModelError.profileChangedExternally {
                    isSaving = false
                    saveError = "磁盘中的代理配置已发生变化，请重新打开后再保存。"
                } catch {
                    isSaving = false
                    saveError = error.localizedDescription
                }
            }
        } catch {
            saveError = error.localizedDescription
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

enum MihomoGuidedProfileDraftError: LocalizedError, Equatable {
    case requiresAdvancedEditor

    var errorDescription: String? {
        switch self {
        case .requiresAdvancedEditor:
            "当前配置包含表单不会显示的节点、Provider、代理组或规则"
        }
    }
}

struct MihomoGuidedProfileDraft {
    static func editableProfile(from data: Data) throws -> MihomoProxyProfile {
        let configuration = try MihomoServerConfiguration(data: data)
        let profile = try configuration.primaryProfile()
        let canonicalData = try configuration.formattedData()
        let guidedData = try profile.serverConfiguration().formattedData()
        guard canonicalData == guidedData else {
            throw MihomoGuidedProfileDraftError.requiresAdvancedEditor
        }
        return profile
    }
}
