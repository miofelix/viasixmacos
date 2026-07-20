import SwiftUI
import ViaSixCore

struct ServerConfigurationEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var profile = XrayServerProfile()
    @State private var serverPortText = "443"
    @State private var shareLink = ""
    @State private var shareLinkError: String?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var loadError: String?
    @State private var saveError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if isLoading {
                ProgressView("正在读取服务器配置…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                ContentUnavailableView(
                    "无法使用可视化编辑器",
                    systemImage: "curlybraces.square",
                    description: Text(loadError)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                form
            }
        }
        .frame(minWidth: 650, minHeight: 620)
        .background(VisualStyle.pageBackground)
        .task { load() }
        .onChange(of: profile.protocolName) { _, protocolName in
            if protocolName == .shadowsocks {
                profile.transport = .tcp
                profile.security = .none
                if profile.encryption == "none" {
                    profile.encryption = "chacha20-ietf-poly1305"
                }
            } else if protocolName == .trojan, profile.security == .none {
                profile.security = .tls
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("服务器连接配置")
                    .font(.title3.weight(.semibold))
                Text("填写远端服务器参数。本机监听地址和端口可在“本机代理设置”中管理。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(isSaving)
        }
        .padding(22)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ProxySectionCard(title: "从分享链接填写") {
                    HStack(spacing: 10) {
                        TextField("vless://、vmess://、trojan:// 或 ss://", text: $shareLink)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        Button("读取") { parseShareLink() }
                            .buttonStyle(.bordered)
                            .disabled(shareLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let shareLinkError {
                        Text(shareLinkError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("支持 VLESS、VMess、Trojan 和 Shadowsocks 分享链接。读取后可以继续修改字段。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ProxySectionCard(title: "服务器") {
                    fieldRow("协议") {
                        Picker("协议", selection: $profile.protocolName) {
                            ForEach(XrayServerProtocol.allCases, id: \.self) { protocolName in
                                Text(protocolName.displayName).tag(protocolName)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
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
                    fieldRow(profile.protocolName == .trojan || profile.protocolName == .shadowsocks ? "密码" : "UUID") {
                        TextField(
                            profile.protocolName == .trojan || profile.protocolName == .shadowsocks
                                ? "服务器密码"
                                : "服务器提供的 UUID",
                            text: $profile.userID
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    }
                    if profile.protocolName == .vless {
                        fieldRow("加密") {
                            TextField("none", text: $profile.encryption)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 180)
                        }
                        fieldRow("Flow（可选）") {
                            TextField("例如 xtls-rprx-vision", text: $profile.flow)
                                .textFieldStyle(.roundedBorder)
                        }
                    } else if profile.protocolName == .vmess {
                        fieldRow("Alter ID") {
                            TextField("0", value: $profile.alterID, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                        }
                        fieldRow("加密方式") {
                            TextField("auto", text: $profile.vmessSecurity)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 180)
                        }
                    } else if profile.protocolName == .shadowsocks {
                        fieldRow("加密算法") {
                            TextField("例如 chacha20-ietf-poly1305", text: $profile.encryption)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                if profile.protocolName != .shadowsocks {
                    ProxySectionCard(title: "传输") {
                        fieldRow("传输方式") {
                            Picker("传输方式", selection: $profile.transport) {
                                ForEach(XrayTransport.allCases, id: \.self) { transport in
                                    Text(transport.displayName).tag(transport)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 180)
                        }
                        if profile.transport == .websocket {
                            fieldRow("WebSocket Host") {
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

                    ProxySectionCard(title: "安全") {
                        fieldRow("安全方式") {
                            Picker("安全方式", selection: $profile.security) {
                                ForEach(XrayTransportSecurity.allCases, id: \.self) { security in
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
                            Toggle("允许不安全 TLS（不推荐）", isOn: $profile.allowInsecure)
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
                            fieldRow("Spider X") {
                                TextField("可选", text: $profile.realitySpiderX)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                }

                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Text("测速时选择的节点 IP 会自动写入服务器地址。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("取消") { dismiss() }
                        .disabled(isSaving)
                    Button {
                        save()
                    } label: {
                        HStack(spacing: 6) {
                            if isSaving { ProgressView().controlSize(.small) }
                            Text(isSaving ? "正在保存…" : "保存服务器配置")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
                }
            }
            .padding(22)
        }
    }

    private func fieldRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.caption.weight(.medium))
                .frame(width: 118, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func load() {
        do {
            let data = try Data(contentsOf: model.paths.serverConfig)
            profile = try ConfigTemplate.serverProfile(in: data)
            serverPortText = String(profile.serverPort)
            loadError = nil
        } catch {
            loadError =
                "当前服务器配置不是可视化编辑器支持的 VLESS、VMess、Trojan 或 Shadowsocks 出站结构。你仍可以返回设置，使用“高级 JSON”编辑器管理它。\n\n\(error.localizedDescription)"
        }
        isLoading = false
    }

    private func parseShareLink() {
        shareLinkError = nil
        do {
            profile = try ServerShareLinkParser.profile(from: shareLink)
            serverPortText = String(profile.serverPort)
        } catch {
            shareLinkError = error.localizedDescription
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
            let data = try ConfigTemplate.serverConfiguration(for: profile)
            isSaving = true
            Task { @MainActor in
                do {
                    try await model.saveServerConfiguration(data)
                    isSaving = false
                    dismiss()
                } catch {
                    isSaving = false
                    saveError = error.localizedDescription
                }
            }
        } catch {
            saveError = error.localizedDescription
        }
    }
}

struct ProxySectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.26), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(VisualStyle.surfaceBorder.opacity(0.78))
        }
    }
}
