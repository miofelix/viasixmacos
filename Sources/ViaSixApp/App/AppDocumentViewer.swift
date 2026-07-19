import AppKit
import SwiftUI

struct AppDocumentViewer: View {
    let document: AppDocument

    @State private var content: String?

    var body: some View {
        Group {
            if let content {
                ScrollView {
                    MarkdownDocument(content: content)
                        .frame(maxWidth: 760, alignment: .leading)
                        .padding(.horizontal, 34)
                        .padding(.vertical, 30)
                }
                .scrollIndicators(.automatic)
            } else {
                ContentUnavailableView(
                    "无法读取文档",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("应用包中没有找到\(document.displayName)。")
                )
            }
        }
        .frame(minWidth: 700, minHeight: 520)
        .background(VisualStyle.pageBackground)
        .task {
            guard let url = AppDocumentOpener.documentURL(for: document) else { return }
            content = try? String(contentsOf: url, encoding: .utf8)
        }
    }
}

private struct MarkdownDocument: View {
    let content: String

    var body: some View {
        if let attributed = try? AttributedString(markdown: content) {
            Text(attributed)
                .textSelection(.enabled)
                .font(.body)
                .lineSpacing(4)
        } else {
            Text(content)
                .textSelection(.enabled)
                .font(.system(.body, design: .monospaced))
        }
    }
}
