import AppKit
import SwiftUI
import ViaSixCore
import ViaSixMihomoConfig

struct MihomoProfileEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var originalText: String?
    @State private var originalData: Data?
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var draftAnalysis = MihomoProfileDraftAnalysis.empty
    @State private var draftAnalysisTask: Task<Void, Never>?
    @State private var hasExternalConflict = false
    @State private var isSaving = false
    @State private var didCopy = false
    @State private var showsDiscardConfirmation = false
    @State private var showsReloadConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            editorHeader

            if let loadError, originalData == nil {
                loadFailureView(loadError)
            } else {
                editorContent
            }
        }
        .frame(minWidth: 780, minHeight: 640)
        .background(VisualStyle.pageBackground)
        .task { await load() }
        .onChange(of: text) { _, _ in
            scheduleDraftAnalysis()
            if !hasExternalConflict {
                saveError = nil
            }
        }
        .onDisappear {
            draftAnalysisTask?.cancel()
            draftAnalysisTask = nil
        }
        .interactiveDismissDisabled(isSaving || hasUnsavedChanges)
        .alert("放弃未保存的更改？", isPresented: $showsDiscardConfirmation) {
            Button("继续编辑", role: .cancel) {}
            Button("放弃更改", role: .destructive) { dismiss() }
        } message: {
            Text("关闭后，本次对代理配置的修改将不会保留。")
        }
        .confirmationDialog(
            "重新载入磁盘版本？",
            isPresented: $showsReloadConfirmation,
            titleVisibility: .visible
        ) {
            Button("放弃当前编辑并重新载入", role: .destructive) {
                Task { await reloadFromDisk() }
            }
            Button("继续编辑", role: .cancel) {}
        } message: {
            Text("重新载入会使用磁盘中的最新配置替换当前编辑内容。")
        }
    }

    private var editorHeader: some View {
        AppPageHeader("代理配置", subtitle: "编辑 profile.yaml 中的节点、Provider 与规则") {
            HStack(spacing: VisualStyle.spacing8) {
                Menu {
                    Button("在访达中显示配置", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([model.paths.profileConfig])
                    }
                    .disabled(originalData == nil)

                    Button("复制配置路径", systemImage: "doc.on.doc") {
                        copyToPasteboard(model.paths.profileConfig.path)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .iconButtonHitTarget()
                .help("配置文件操作")
                .accessibilityLabel("配置文件操作")

                Button {
                    requestDismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .iconButtonHitTarget()
                .help("关闭")
                .accessibilityLabel("关闭代理配置编辑器")
                .disabled(isSaving)
            }
        }
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            configurationSummary

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .scrollbarSafeContent()
                .padding(10)
                .background(
                    Color(nsColor: .textBackgroundColor).opacity(0.72),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(VisualStyle.surfaceBorder)
                }
                .disabled(isSaving)
                .accessibilityLabel("Mihomo YAML 配置")
                .accessibilityHint("保存前会检查节点、Provider 与规则结构")

            editorFeedback
            editorFooter
        }
        .padding(20)
    }

    private var configurationSummary: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                draftStatusBadge

                if let server = draftAnalysis.inlineServer {
                    Divider()
                        .frame(height: 16)
                    Label(server, systemImage: "server.rack")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 12)

                Button(didCopy ? "已复制" : "复制", systemImage: didCopy ? "checkmark" : "doc.on.doc") {
                    copyDraft()
                }
                .disabled(text.isEmpty || isSaving)
                .help("复制 YAML 原文")

                if draftAnalysis.canMigrate {
                    Button("迁移为 YAML", systemImage: "arrow.triangle.2.circlepath") {
                        migrateDraft()
                    }
                    .disabled(isSaving)
                    .help("将可兼容的旧配置转换为 Mihomo YAML")
                } else {
                    Button("格式化", systemImage: "text.alignleft") {
                        formatDraft()
                    }
                    .disabled(!draftAnalysis.canFormat || isSaving)
                    .help("使用稳定的键名顺序和缩进格式化 YAML")
                }

                Button("重新载入", systemImage: "arrow.clockwise") {
                    requestReload()
                }
                .disabled(isSaving)
                .help("载入磁盘中的最新配置")
            }

            configurationContext
        }
        .padding(13)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(VisualStyle.surfaceBorder.opacity(0.78))
        }
    }

    @ViewBuilder
    private var configurationContext: some View {
        switch draftAnalysis.status {
        case .inlineProxy:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("当前节点")
                    .font(.caption.weight(.medium))
                Text(selectedIPDescription)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 10)
                Text("连接时可将第一个内联节点的服务器地址替换为当前节点，不会改动凭据与 TLS 标识。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .providerOnly:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("节点来源")
                    .font(.caption.weight(.medium))
                Text("Proxy Provider")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 10)
                Text("节点由 Provider 管理，测速节点不会覆盖订阅中的服务器地址。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .legacyXrayMigratable, .legacyXrayMigrationFailed:
            Text("旧配置不会直接写入 profile.yaml；仅在迁移成功后才能保存。")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .empty, .invalidYAML, .invalidConfiguration:
            EmptyView()
        }
    }

    private var draftStatusBadge: some View {
        Label(draftAnalysis.statusTitle, systemImage: draftAnalysis.statusIcon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(draftStatusColor)
            .accessibilityLabel("配置状态：\(draftAnalysis.statusTitle)")
    }

    @ViewBuilder
    private var editorFeedback: some View {
        if let saveError {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(saveError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)

                if hasExternalConflict {
                    Button("载入最新版本", systemImage: "arrow.clockwise") {
                        showsReloadConfirmation = true
                    }
                    .help("放弃当前编辑并载入磁盘中的最新配置")
                    .accessibilityHint("当前编辑内容将被替换")
                }
            }
        } else if let issue = draftAnalysis.issue {
            Label(issue, systemImage: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("配置需要处理：\(issue)")
        }
    }

    private var editorFooter: some View {
        HStack(spacing: 12) {
            if hasUnsavedChanges {
                Label("有未保存的更改", systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("有未保存的更改")
            } else {
                Label("与磁盘版本一致", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("\(lineCount) 行 · \(text.utf8.count.formatted()) 字节")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)

            Spacer()

            Button("取消", role: .cancel) {
                requestDismiss()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(isSaving)

            Button {
                save()
            } label: {
                HStack(spacing: 6) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.circle")
                    }
                    Text(isSaving ? "正在保存…" : "保存配置")
                }
                .frame(minWidth: 96)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("s", modifiers: .command)
            .disabled(
                isSaving
                    || hasExternalConflict
                    || !hasUnsavedChanges
                    || !draftAnalysis.isValid
            )
            .help(draftAnalysis.isValid ? "保存配置（⌘S）" : "修正或迁移配置后才能保存")
        }
    }

    private func loadFailureView(_ message: String) -> some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "无法打开代理配置",
                systemImage: "doc.badge.exclamationmark",
                description: Text(message)
            )
            HStack(spacing: 10) {
                Button("重新读取", systemImage: "arrow.clockwise") {
                    Task { await reloadFromDisk(initialLoad: true) }
                }
                .buttonStyle(.borderedProminent)

                Button("打开数据目录", systemImage: "folder") {
                    NSWorkspace.shared.open(model.paths.root)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var hasUnsavedChanges: Bool {
        guard let originalText else { return false }
        return text != originalText
    }

    private var selectedIPDescription: String {
        let selectedIP = model.state.preferences.selectedIP
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return selectedIP.isEmpty ? "尚未选择节点" : selectedIP
    }

    private var lineCount: Int {
        guard !text.isEmpty else { return 0 }
        return text.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    private var draftStatusColor: Color {
        switch draftAnalysis.status {
        case .empty: .secondary
        case .invalidYAML, .invalidConfiguration, .legacyXrayMigrationFailed: .orange
        case .legacyXrayMigratable: .blue
        case .inlineProxy, .providerOnly: .green
        }
    }

    private func load() async {
        guard originalText == nil else { return }
        await reloadFromDisk(initialLoad: true)
    }

    private func requestReload() {
        if hasUnsavedChanges {
            showsReloadConfirmation = true
        } else {
            Task { await reloadFromDisk() }
        }
    }

    private func reloadFromDisk(initialLoad: Bool = false) async {
        do {
            let data = try await model.loadProfileConfiguration()
            guard let loadedText = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            text = loadedText
            originalText = loadedText
            originalData = data
            loadError = nil
            saveError = nil
            hasExternalConflict = false
            refreshDraftAnalysis()
        } catch {
            if initialLoad {
                loadError = "读取配置失败：\(error.localizedDescription)"
                originalText = nil
                originalData = nil
            } else {
                saveError = "重新载入失败：\(error.localizedDescription)"
            }
        }
    }

    private func refreshDraftAnalysis() {
        draftAnalysis = MihomoProfileDraftAnalysis.inspect(text)
    }

    private func scheduleDraftAnalysis() {
        draftAnalysisTask?.cancel()
        let draft = text
        draftAnalysisTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(140))
                try Task.checkCancellation()
                let analysis = await Task.detached(priority: .userInitiated) {
                    MihomoProfileDraftAnalysis.inspect(draft)
                }.value
                guard !Task.isCancelled, text == draft else { return }
                draftAnalysis = analysis
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func formatDraft() {
        do {
            text = try MihomoProfileDraftAnalysis.formattedYAML(text)
            if !hasExternalConflict {
                saveError = nil
            }
        } catch {
            saveError = "格式化失败：\(error.localizedDescription)"
        }
    }

    private func migrateDraft() {
        do {
            text = try MihomoProfileDraftAnalysis.migratedYAML(text)
            if !hasExternalConflict {
                saveError = nil
            }
            refreshDraftAnalysis()
        } catch {
            saveError = "迁移失败：\(error.localizedDescription)"
        }
    }

    private func copyDraft() {
        copyToPasteboard(text)
        didCopy = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            didCopy = false
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func save() {
        saveError = nil
        hasExternalConflict = false
        refreshDraftAnalysis()
        guard draftAnalysis.isValid else {
            saveError = draftAnalysis.issue ?? "请先修正代理配置"
            return
        }

        let data: Data
        do {
            data = try MihomoProfileDraftAnalysis.canonicalData(text)
        } catch {
            saveError = "配置无法保存：\(error.localizedDescription)"
            return
        }

        isSaving = true
        Task { @MainActor in
            do {
                try await model.saveProfileConfiguration(
                    data,
                    expectedProfileData: originalData
                )
                let savedText = String(decoding: data, as: UTF8.self)
                text = savedText
                originalText = savedText
                originalData = data
                isSaving = false
                dismiss()
            } catch is CancellationError {
                isSaving = false
            } catch AppModelError.profileChangedExternally {
                isSaving = false
                hasExternalConflict = true
                saveError = "磁盘中的代理配置已在编辑期间发生变化。为避免覆盖，请载入最新版本后再继续。"
            } catch {
                isSaving = false
                saveError = "保存失败：\(error.localizedDescription)"
            }
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

struct MihomoProfileDraftAnalysis: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case empty
        case inlineProxy(String)
        case providerOnly
        case invalidYAML(String)
        case invalidConfiguration(String)
        case legacyXrayMigratable(String)
        case legacyXrayMigrationFailed(String)
    }

    let status: Status

    static let empty = MihomoProfileDraftAnalysis(status: .empty)

    var inlineServer: String? {
        switch status {
        case .inlineProxy(let server), .legacyXrayMigratable(let server):
            server
        case .empty, .providerOnly, .invalidYAML, .invalidConfiguration,
            .legacyXrayMigrationFailed:
            nil
        }
    }

    var isValid: Bool {
        switch status {
        case .inlineProxy, .providerOnly: true
        case .empty, .invalidYAML, .invalidConfiguration, .legacyXrayMigratable,
            .legacyXrayMigrationFailed:
            false
        }
    }

    var canFormat: Bool { isValid }

    var canMigrate: Bool {
        if case .legacyXrayMigratable = status { true } else { false }
    }

    var issue: String? {
        switch status {
        case .empty:
            "配置内容不能为空"
        case .invalidYAML(let message), .invalidConfiguration(let message),
            .legacyXrayMigrationFailed(let message):
            message
        case .legacyXrayMigratable:
            "检测到可兼容的旧版 Xray JSON，请先迁移为 Mihomo YAML。"
        case .inlineProxy, .providerOnly:
            nil
        }
    }

    var statusTitle: String {
        switch status {
        case .empty: "等待配置"
        case .inlineProxy: "内联节点配置有效"
        case .providerOnly: "Provider 配置有效"
        case .invalidYAML: "YAML 需要修正"
        case .invalidConfiguration: "配置需要修正"
        case .legacyXrayMigratable: "可迁移旧配置"
        case .legacyXrayMigrationFailed: "旧配置无法迁移"
        }
    }

    var statusIcon: String {
        switch status {
        case .empty: "doc.text"
        case .inlineProxy: "server.rack"
        case .providerOnly: "shippingbox"
        case .invalidYAML, .invalidConfiguration, .legacyXrayMigrationFailed:
            "exclamationmark.circle.fill"
        case .legacyXrayMigratable: "arrow.triangle.2.circlepath"
        }
    }

    static func inspect(_ text: String) -> Self {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .empty
        }
        guard let data = text.data(using: .utf8) else {
            return Self(status: .invalidYAML("配置不是有效的 UTF-8 文本"))
        }

        do {
            let configuration = try MihomoServerConfiguration(data: data)
            let canonical = try configuration.formattedData()
            if let server = MihomoServerConfiguration.proxyServerAddress(in: canonical) {
                return Self(status: .inlineProxy(server))
            }
            return Self(status: .providerOnly)
        } catch let error as MihomoConfigurationError {
            switch error {
            case .legacyXrayConfiguration:
                return inspectLegacyXray(data)
            case .invalidUTF8, .invalidYAML:
                return Self(status: .invalidYAML(error.localizedDescription))
            default:
                return Self(status: .invalidConfiguration(error.localizedDescription))
            }
        } catch {
            return Self(status: .invalidConfiguration(error.localizedDescription))
        }
    }

    static func canonicalData(_ text: String) throws -> Data {
        guard let data = text.data(using: .utf8) else {
            throw MihomoConfigurationError.invalidUTF8
        }
        return try MihomoServerConfiguration(data: data).formattedData()
    }

    static func formattedYAML(_ text: String) throws -> String {
        String(decoding: try canonicalData(text), as: UTF8.self)
    }

    static func migratedYAML(_ text: String) throws -> String {
        guard let data = text.data(using: .utf8) else {
            throw MihomoConfigurationError.invalidUTF8
        }
        let migrated = try LegacyXrayConfigurationMigrator.serverConfiguration(from: data)
        return String(decoding: try migrated.formattedData(), as: UTF8.self)
    }

    private static func inspectLegacyXray(_ data: Data) -> Self {
        do {
            let migrated = try LegacyXrayConfigurationMigrator.serverConfiguration(from: data)
            let server = MihomoServerConfiguration.proxyServerAddress(in: migrated.data) ?? "内联节点"
            return Self(status: .legacyXrayMigratable(server))
        } catch {
            return Self(status: .legacyXrayMigrationFailed(error.localizedDescription))
        }
    }
}
