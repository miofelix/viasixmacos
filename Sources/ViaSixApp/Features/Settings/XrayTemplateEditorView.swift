import SwiftUI
import ViaSixCore

struct XrayTemplateEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var loadError: String?
    @State private var validationError: String?

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
                .padding(10)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(VisualStyle.surfaceBorder)
                }

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

            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                Button("保存配置", systemImage: "checkmark.circle") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 620)
        .task { load() }
    }

    private func load() {
        guard text.isEmpty else { return }
        do {
            text = try String(contentsOf: model.paths.templateConfig, encoding: .utf8)
        } catch {
            loadError = "读取配置失败：\(error.localizedDescription)"
        }
    }

    private func save() {
        validationError = nil
        guard let data = text.data(using: .utf8) else {
            validationError = "配置不是有效的 UTF-8 文本"
            return
        }
        do {
            _ = try ConfigTemplate.validateTemplate(data)
            model.saveXrayTemplate(data)
            dismiss()
        } catch {
            validationError = error.localizedDescription
        }
    }
}
