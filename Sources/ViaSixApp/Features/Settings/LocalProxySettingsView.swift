import SwiftUI
import ViaSixCore

struct LocalProxySettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var configuration = LocalProxyConfiguration()
    @State private var portText = "11451"
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("本机代理设置")
                        .font(.title3.weight(.semibold))
                    Text("设置代理模式、网络接入、本地监听和协议行为。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .disabled(isSaving)
            }
            .padding(22)
            Divider()

            if isLoading {
                ProgressView("正在读取本机设置…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ProxySectionCard(title: "代理模式") {
                            ProxyRoutingModePicker(
                                selection: $configuration.routingMode,
                                isDisabled: isSaving
                            )
                            Text("模式只影响进入本地代理的连接；系统代理是否开启在网络接入中单独控制。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ProxySectionCard(title: "网络接入") {
                            Toggle(
                                "启动本地代理时使用系统代理",
                                isOn: $configuration.systemProxyEnabled
                            )
                            Text("开启后，ViaSix 会在本地代理启动成功时配置 macOS 系统代理，并在停止时恢复原设置。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("系统代理不会接管忽略 macOS 代理设置的应用流量。")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ProxySectionCard(title: "监听") {
                            localRow("监听地址") {
                                TextField("127.0.0.1", text: $configuration.listenAddress)
                                    .textFieldStyle(.roundedBorder)
                            }
                            localRow("监听端口") {
                                TextField("11451", text: $portText)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 130)
                            }
                            Text("仅允许回环地址，避免意外暴露给局域网。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ProxySectionCard(title: "协议行为") {
                            Toggle("启用 UDP", isOn: $configuration.udpEnabled)
                            Toggle("启用协议嗅探", isOn: $configuration.sniffingEnabled)
                            Toggle("私有地址直连", isOn: $configuration.bypassPrivateNetworks)
                            Text("UDP 仅在客户端通过 SOCKS5/兼容协议发起时生效；它不会把系统流量自动变成 TUN。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ProxySectionCard(title: "日志") {
                            Picker("Xray 日志级别", selection: $configuration.logLevel) {
                                ForEach(XrayLogLevel.allCases, id: \.self) { level in
                                    Text(level.displayName).tag(level)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack {
                            Spacer()
                            Button("取消") { dismiss() }
                                .disabled(isSaving)
                            Button {
                                save()
                            } label: {
                                HStack(spacing: 6) {
                                    if isSaving { ProgressView().controlSize(.small) }
                                    Text(isSaving ? "正在保存…" : "保存本机设置")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isSaving)
                        }
                    }
                    .padding(22)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 520)
        .background(VisualStyle.pageBackground)
        .task { load() }
        .interactiveDismissDisabled(isSaving)
    }

    private func localRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.caption.weight(.medium))
                .frame(width: 100, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func load() {
        do {
            let data = try Data(contentsOf: model.paths.localProxyConfig)
            configuration = try JSONDecoder().decode(LocalProxyConfiguration.self, from: data).validated()
            portText = String(configuration.port)
        } catch {
            configuration = model.state.localProxyConfiguration
            portText = String(configuration.port)
            errorMessage = "读取本机设置失败：\(error.localizedDescription)"
        }
        isLoading = false
    }

    private func save() {
        errorMessage = nil
        guard let port = Int(portText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "监听端口必须是数字。"
            return
        }
        configuration.port = port
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
}
