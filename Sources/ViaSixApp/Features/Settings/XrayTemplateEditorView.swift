import AppKit
import SwiftUI
import ViaSixCore

struct XrayTemplateEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var originalText: String?
    @State private var originalData: Data?
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var draftAnalysis = XrayTemplateDraftAnalysis.empty
    @State private var draftAnalysisTask: Task<Void, Never>?
    @State private var hasExternalConflict = false
    @State private var isSaving = false
    @State private var didCopy = false
    @State private var showsDiscardConfirmation = false
    @State private var showsReloadConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            Divider()

            if let loadError, originalData == nil {
                loadFailureView(loadError)
            } else {
                editorContent
            }
        }
        .frame(minWidth: 780, minHeight: 640)
        .background(VisualStyle.pageBackground)
        .task { load() }
        .onChange(of: text) { _, _ in
            scheduleDraftAnalysis()
            if !hasExternalConflict {
                saveError = nil
            }
        }
        .onChange(of: model.state.preferences.selectedIP) { _, _ in
            scheduleDraftAnalysis()
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
                reloadFromDisk()
            }
            Button("继续编辑", role: .cancel) {}
        } message: {
            Text("重新载入会使用磁盘中的最新配置替换当前编辑内容。")
        }
    }

    private var editorHeader: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("高级服务器 JSON")
                    .font(.title3.weight(.semibold))
                Text("编辑 Xray 的 proxy 出站。本机监听地址、端口和路由行为可在“本机代理设置”中修改。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            Menu {
                Button("在访达中显示配置", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([model.paths.serverConfig])
                }
                .disabled(originalData == nil)

                Button("复制配置路径", systemImage: "doc.on.doc") {
                    copyToPasteboard(model.paths.serverConfig.path)
                }
            } label: {
                Label("更多", systemImage: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("配置文件操作")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
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
                .accessibilityLabel("Xray JSON 配置")
                .accessibilityHint("保存前会自动检查配置结构和当前连接参数")

            editorFeedback
            editorFooter
        }
        .padding(20)
    }

    private var configurationSummary: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                draftStatusBadge

                if let endpoint = draftAnalysis.endpoint {
                    Divider()
                        .frame(height: 16)
                    Label(endpoint.displayAddress, systemImage: "network")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .help("运行时使用的本地端点")
                }

                Spacer(minLength: 12)

                Button(didCopy ? "已复制" : "复制", systemImage: didCopy ? "checkmark" : "doc.on.doc") {
                    copyDraft()
                }
                .disabled(text.isEmpty || isSaving)
                .help("复制 JSON 原文")

                Button("格式化", systemImage: "text.alignleft") {
                    formatDraft()
                }
                .disabled(!draftAnalysis.canFormat || isSaving)
                .help("使用稳定的缩进和键名顺序格式化 JSON")

                Button("重新载入", systemImage: "arrow.clockwise") {
                    requestReload()
                }
                .disabled(isSaving)
                .help("载入磁盘中的最新配置")
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("应用节点")
                    .font(.caption.weight(.medium))
                Text(selectedIPDescription)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 10)
                Text("应用节点时仅替换 proxy 出站的首个服务器地址，不改动凭据。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(VisualStyle.surfaceBorder.opacity(0.78))
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
                .accessibilityLabel("配置需要修正：\(issue)")
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
            .help(draftAnalysis.isValid ? "保存配置（⌘S）" : "修正配置后才能保存")
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
                    reloadFromDisk(initialLoad: true)
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
        case .invalidJSON, .invalidConfiguration: .orange
        case .valid, .validWithoutNode: .green
        }
    }

    private func load() {
        guard originalText == nil else { return }
        reloadFromDisk(initialLoad: true)
    }

    private func requestReload() {
        if hasUnsavedChanges {
            showsReloadConfirmation = true
        } else {
            reloadFromDisk()
        }
    }

    private func reloadFromDisk(initialLoad: Bool = false) {
        do {
            let data = try Data(contentsOf: model.paths.serverConfig)
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
        draftAnalysis = XrayTemplateDraftAnalysis.inspect(
            text,
            selectedIP: model.state.preferences.selectedIP,
            local: model.state.localProxyConfiguration
        )
    }

    private func scheduleDraftAnalysis() {
        draftAnalysisTask?.cancel()
        let draft = text
        let selectedIP = model.state.preferences.selectedIP
        let local = model.state.localProxyConfiguration
        draftAnalysisTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(140))
                try Task.checkCancellation()
                let analysis = await Task.detached(priority: .userInitiated) {
                    XrayTemplateDraftAnalysis.inspect(
                        draft,
                        selectedIP: selectedIP,
                        local: local
                    )
                }.value
                guard !Task.isCancelled, text == draft,
                    model.state.preferences.selectedIP == selectedIP
                else { return }
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
            text = try XrayTemplateDraftAnalysis.formatted(text)
            if !hasExternalConflict {
                saveError = nil
            }
        } catch {
            saveError = "格式化失败：\(error.localizedDescription)"
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
        guard let data = text.data(using: .utf8) else {
            saveError = "配置不是有效的 UTF-8 文本"
            return
        }

        isSaving = true
        Task { @MainActor in
            do {
                try await model.saveServerConfiguration(data)
                originalData = data
                originalText = text
                isSaving = false
                dismiss()
            } catch is CancellationError {
                isSaving = false
            } catch AppModelError.templateChangedExternally {
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

struct XrayTemplateDraftAnalysis: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case empty
        case invalidJSON(String)
        case invalidConfiguration(String)
        case valid(ProxyEndpoint)
        case validWithoutNode(ProxyEndpoint)
    }

    let status: Status
    let canFormat: Bool

    static let empty = XrayTemplateDraftAnalysis(status: .empty, canFormat: false)

    var endpoint: ProxyEndpoint? {
        switch status {
        case .valid(let endpoint), .validWithoutNode(let endpoint):
            return endpoint
        default:
            return nil
        }
    }

    var isValid: Bool {
        endpoint != nil
    }

    var issue: String? {
        switch status {
        case .empty:
            "配置内容不能为空"
        case .invalidJSON(let message), .invalidConfiguration(let message):
            message
        case .valid, .validWithoutNode:
            nil
        }
    }

    var statusTitle: String {
        switch status {
        case .empty: "等待配置"
        case .invalidJSON: "JSON 需要修正"
        case .invalidConfiguration: "配置需要修正"
        case .valid: "配置有效"
        case .validWithoutNode: "配置有效，待选择节点"
        }
    }

    var statusIcon: String {
        switch status {
        case .empty: "doc.text"
        case .invalidJSON, .invalidConfiguration: "exclamationmark.circle.fill"
        case .valid, .validWithoutNode: "checkmark.circle.fill"
        }
    }

    static func inspect(
        _ text: String,
        selectedIP: String?,
        local: LocalProxyConfiguration = .default
    ) -> XrayTemplateDraftAnalysis {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .empty
        }
        guard let data = text.data(using: .utf8) else {
            return XrayTemplateDraftAnalysis(
                status: .invalidJSON("配置不是有效的 UTF-8 文本"),
                canFormat: false
            )
        }

        do {
            let object = try JSONSerialization.jsonObject(with: data)
            guard JSONSerialization.isValidJSONObject(object) else {
                throw ConfigTemplateError.invalidJSON
            }
        } catch {
            return XrayTemplateDraftAnalysis(
                status: .invalidJSON(ConfigTemplateError.invalidJSON.localizedDescription),
                canFormat: false
            )
        }

        do {
            let normalizedIP =
                selectedIP?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let validationIP = normalizedIP.isEmpty ? "2001:db8::2" : normalizedIP
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let endpoint: ProxyEndpoint
            let generated: Data
            if object?["inbounds"] != nil || object?["outbounds"] != nil {
                endpoint = try ConfigTemplate.validateTemplate(data)
                generated = try ConfigTemplate.replacingAddress(in: data, with: validationIP)
            } else {
                endpoint = try local.validated().endpoint
                generated = try ConfigTemplate.runtimeConfiguration(
                    server: data,
                    local: local,
                    address: validationIP
                )
            }
            try ConfigTemplate.validateForLaunch(generated)
            return XrayTemplateDraftAnalysis(
                status: normalizedIP.isEmpty ? .validWithoutNode(endpoint) : .valid(endpoint),
                canFormat: true
            )
        } catch {
            return XrayTemplateDraftAnalysis(
                status: .invalidConfiguration(error.localizedDescription),
                canFormat: true
            )
        }
    }

    static func formatted(_ text: String) throws -> String {
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ConfigTemplateError.invalidJSON
        }
        guard JSONSerialization.isValidJSONObject(object) else {
            throw ConfigTemplateError.invalidJSON
        }
        let formatted = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        return String(decoding: formatted, as: UTF8.self) + "\n"
    }
}
