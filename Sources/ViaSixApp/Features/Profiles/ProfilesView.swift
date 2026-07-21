import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ViaSixCore
import ViaSixMihomoConfig

struct ProfilesView: View {
    @Environment(AppModel.self) private var model
    @State private var summary: MihomoProfileSummary?
    @State private var loadError: String?
    @State private var showsImporter = false
    @State private var showsYAMLEditor = false
    @State private var showsManualEditor = false

    var body: some View {
        VStack(spacing: 0) {
            AppPageHeader("配置", subtitle: "管理 ViaSix 使用的 Mihomo 配置档") {
                HStack(spacing: VisualStyle.spacing8) {
                    Button("导入", systemImage: "square.and.arrow.down") {
                        showsImporter = true
                    }
                    Button("新建", systemImage: "plus") {
                        showsManualEditor = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .disabled(configurationEditingDisabled)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: VisualStyle.spacing12) {
                    currentProfileCard
                    profileActionsCard
                    safetyCard
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, VisualStyle.pageHorizontalPadding)
                .padding(.vertical, VisualStyle.pageVerticalPadding)
            }
            .scrollbarSafeContent()
        }
        .task { await reloadSummary() }
        .onChange(of: model.state.templateOperationPhase) { previous, current in
            guard previous != .idle, current == .idle else { return }
            Task { await reloadSummary() }
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.plainText, .data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                model.importProxyProfile(from: url)
            }
        }
        .sheet(isPresented: $showsYAMLEditor) {
            MihomoProfileEditorView().environment(model)
        }
        .sheet(isPresented: $showsManualEditor) {
            ServerConfigurationEditorView(initialInputMode: .manual).environment(model)
        }
    }

    private var currentProfileCard: some View {
        SurfaceCard {
            CardHeader("当前配置档", systemImage: "shippingbox", tone: profileTone) {
                StatusBadge(profileStatus, tone: profileTone, systemImage: profileStatusIcon)
            }
            Divider()

            if let summary {
                VStack(alignment: .leading, spacing: VisualStyle.spacing16) {
                    HStack(spacing: VisualStyle.spacing12) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(VisualStyle.accent)
                            .frame(width: 46, height: 46)
                            .background(VisualStyle.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(summary.primaryProxyName ?? "Mihomo Profile")
                                .font(.title3.weight(.semibold))
                            Text(model.paths.profileConfig.path)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                    }

                    HStack(spacing: VisualStyle.spacing8) {
                        profileMetric("节点", value: summary.inlineProxyCount, icon: "server.rack")
                        profileMetric("Provider", value: summary.providerCount, icon: "icloud.and.arrow.down")
                        profileMetric("代理组", value: summary.groupCount, icon: "wifi")
                        profileMetric("规则", value: summary.ruleCount, icon: "arrow.triangle.branch")
                    }
                }
                .padding(VisualStyle.spacing16)
            } else if let loadError {
                ContentUnavailableView {
                    Label("配置档需要处理", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("导入配置", systemImage: "square.and.arrow.down") { showsImporter = true }
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                ProgressView("正在读取配置档…")
                    .frame(maxWidth: .infinity, minHeight: 220)
            }
        }
    }

    private var profileActionsCard: some View {
        SurfaceCard {
            CardHeader("配置操作", systemImage: "slider.horizontal.3", tone: .accent)
            Divider()
            VStack(spacing: 0) {
                SettingRow(
                    "可视化编辑",
                    detail: "配置常用的 VLESS、VMess、Trojan 或 Shadowsocks 节点",
                    systemImage: "list.bullet.rectangle"
                ) {
                    Button("编辑", systemImage: "pencil") { showsManualEditor = true }
                }
                Divider().padding(.leading, 52)
                SettingRow("Mihomo YAML", detail: "编辑代理组、Provider、规则与高级内核字段", systemImage: "curlybraces.square") {
                    Button("打开编辑器", systemImage: "chevron.left.forwardslash.chevron.right") {
                        showsYAMLEditor = true
                    }
                    .disabled(summary == nil)
                }
                Divider().padding(.leading, 52)
                SettingRow("配置文件位置", detail: "在 Finder 中显示 ViaSix 私有配置", systemImage: "folder") {
                    Button("显示", systemImage: "arrow.up.right.square") {
                        NSWorkspace.shared.activateFileViewerSelecting([model.paths.profileConfig])
                    }
                }
            }
            .padding(.horizontal, VisualStyle.spacing16)
            .padding(.bottom, VisualStyle.spacing12)
            .disabled(configurationEditingDisabled)
        }
    }

    private var safetyCard: some View {
        SurfaceCard {
            HStack(alignment: .top, spacing: VisualStyle.spacing12) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(VisualStyle.positive)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text("由 ViaSix 管理本机运行字段")
                        .font(.callout.weight(.semibold))
                    Text("导入配置中的监听地址、端口、TUN、DNS 与 Controller 设置不会直接覆盖本机安全边界；ViaSix 会保留代理、代理组、Provider 和规则，再生成可运行配置。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(VisualStyle.spacing16)
        }
    }

    private func profileMetric(_ title: String, value: Int, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(value)").font(.callout.weight(.semibold).monospacedDigit())
                Text(title).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(VisualStyle.subtleFill, in: RoundedRectangle(cornerRadius: 8))
    }

    private var configurationEditingDisabled: Bool {
        model.state.isProxyRunning || model.isTemplateOperationBusy || model.state.runtimeOperation != nil
    }

    private var profileStatus: String {
        if model.isTemplateOperationBusy { return "处理中" }
        if loadError != nil { return "需要配置" }
        return summary == nil ? "读取中" : "已就绪"
    }

    private var profileTone: AppTone {
        if model.isTemplateOperationBusy { return .accent }
        if loadError != nil { return .warning }
        return summary == nil ? .neutral : .positive
    }

    private var profileStatusIcon: String {
        switch profileTone {
        case .positive: "checkmark.circle.fill"
        case .warning: "exclamationmark.circle.fill"
        case .accent: "arrow.triangle.2.circlepath"
        case .negative: "xmark.circle.fill"
        case .neutral: "clock"
        }
    }

    @MainActor
    private func reloadSummary() async {
        do {
            let data = try await model.loadProfileConfiguration()
            summary = try MihomoServerConfiguration(data: data).summary
            loadError = nil
        } catch {
            summary = nil
            loadError = error.localizedDescription
        }
    }
}
