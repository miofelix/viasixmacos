import SwiftUI
import ViaSixCore

struct XrayTemplateEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var originalText: String?
    @State private var originalData: Data?
    @State private var loadError: String?
    @State private var validationError: String?
    @State private var saveError: String?
    @State private var hasExternalConflict = false
    @State private var isSaving = false
    @State private var showsDiscardConfirmation = false
    @State private var showsReloadConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("编辑代理配置")
                    .font(.title3.weight(.semibold))
                Text("保存前会检查回环 mixed 入站和 proxy 出站；凭据仍只保存在本机。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .scrollbarSafeContent()
                .padding(10)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(VisualStyle.surfaceBorder)
                }
                .disabled(isSaving)
                .accessibilityLabel("Xray JSON 配置")

            if let loadError {
                Label(loadError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let validationError {
                Label(validationError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let saveError {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(saveError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)

                    if hasExternalConflict {
                        Button("重新载入磁盘版本", systemImage: "arrow.clockwise") {
                            showsReloadConfirmation = true
                        }
                        .buttonStyle(.borderless)
                        .help("放弃当前编辑并载入最新配置")
                        .accessibilityHint("当前编辑内容将被替换")
                    }
                }
            }

            HStack {
                if hasUnsavedChanges {
                    Label("有未保存的更改", systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("有未保存的更改")
                }
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
                    .frame(minWidth: 92)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(
                    isSaving
                        || hasExternalConflict
                        || !hasUnsavedChanges
                        || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 620)
        .task { load() }
        .onChange(of: text) {
            validationError = nil
            if !hasExternalConflict {
                saveError = nil
            }
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

    private var hasUnsavedChanges: Bool {
        guard let originalText else { return false }
        return text != originalText
    }

    private func load() {
        guard originalText == nil else { return }
        reloadFromDisk(initialLoad: true)
    }

    private func reloadFromDisk(initialLoad: Bool = false) {
        do {
            let data = try Data(contentsOf: model.paths.templateConfig)
            guard let loadedText = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            text = loadedText
            originalText = text
            originalData = data
            loadError = nil
            validationError = nil
            saveError = nil
            hasExternalConflict = false
        } catch {
            if initialLoad {
                loadError = "读取配置失败：\(error.localizedDescription)"
                originalText = ""
                originalData = nil
            } else {
                saveError = "重新载入失败：\(error.localizedDescription)"
            }
        }
    }

    private func save() {
        validationError = nil
        if !hasExternalConflict {
            saveError = nil
        }
        guard let data = text.data(using: .utf8) else {
            validationError = "配置不是有效的 UTF-8 文本"
            return
        }
        do {
            _ = try ConfigTemplate.validateTemplate(data)
        } catch {
            validationError = error.localizedDescription
            return
        }

        saveError = nil
        hasExternalConflict = false
        isSaving = true
        Task { @MainActor in
            do {
                try await model.saveXrayTemplate(data, expectedTemplateData: originalData)
                originalData = data
                originalText = text
                isSaving = false
                dismiss()
            } catch is CancellationError {
                isSaving = false
            } catch AppModelError.templateChangedExternally {
                isSaving = false
                hasExternalConflict = true
                saveError = "磁盘中的代理配置已在编辑器打开后发生变化。为避免覆盖，请重新载入最新版本。"
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
