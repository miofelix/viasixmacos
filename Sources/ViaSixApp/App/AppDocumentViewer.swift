import AppKit
import Foundation
import SwiftUI

struct AppDocumentViewer: View {
    let document: AppDocument

    @State private var pages: [DocumentPage] = []
    @State private var pendingAnchor: String?
    @State private var isLoading = true

    private var page: DocumentPage? { pages.last }

    var body: some View {
        VStack(spacing: 0) {
            navigationBar
            Divider()

            if isLoading {
                ProgressView("正在读取文档…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let page {
                documentContent(page)
            } else {
                ContentUnavailableView(
                    "无法读取文档",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("应用包中没有找到\(document.displayName)。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 700, minHeight: 520)
        .background(VisualStyle.pageBackground)
        .task {
            guard pages.isEmpty else { return }
            guard let url = AppDocumentOpener.documentURL(for: document) else {
                isLoading = false
                return
            }
            openPage(url, title: document.displayName)
            isLoading = false
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 10) {
            Button {
                guard pages.count > 1 else { return }
                pages.removeLast()
                pendingAnchor = nil
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .iconButtonHitTarget()
            .help("返回上一页")
            .accessibilityLabel("返回上一页")
            .disabled(pages.count <= 1)

            Text(page?.title ?? document.displayName)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 12)

            if let page {
                Button {
                    NSWorkspace.shared.open(page.url)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .iconButtonHitTarget()
                .help("在访达中打开当前文件")
                .accessibilityLabel("在访达中打开当前文件")
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    private func documentContent(_ page: DocumentPage) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(page.sections) { section in
                        MarkdownDocument(
                            content: section.content,
                            baseURL: page.url,
                            onOpenURL: { url in
                                handleLink(url, from: page.url)
                            }
                        )
                        .id(section.id)
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 34)
                .padding(.vertical, 30)
            }
            .scrollIndicators(.automatic)
            .onChange(of: pendingAnchor, initial: true) { _, anchor in
                guard let anchor else { return }
                withAnimation(.easeInOut(duration: 0.24)) {
                    proxy.scrollTo(anchor, anchor: .top)
                }
                pendingAnchor = nil
            }
        }
    }

    private func openPage(_ url: URL, title: String? = nil, anchor: String? = nil) {
        let normalizedURL = fileURLWithoutFragment(url)
        guard AppDocumentOpener.isTrustedDocumentURL(normalizedURL) else { return }

        do {
            let content: String
            let isDirectory = (try? normalizedURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory {
                content = try directoryIndex(for: normalizedURL)
            } else {
                content = try String(contentsOf: normalizedURL, encoding: .utf8)
            }

            let page = DocumentPage(
                url: normalizedURL,
                title: title ?? displayTitle(for: normalizedURL),
                content: content,
                isDirectory: isDirectory
            )
            pages.append(page)
            pendingAnchor = anchor.map(MarkdownSection.slug)
        } catch {
            isLoading = false
        }
    }

    private func handleLink(_ url: URL, from sourceURL: URL) {
        if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
            return
        }

        guard url.isFileURL else { return }
        let target = fileURLWithoutFragment(url)
        let fragment = url.fragment
        if target == fileURLWithoutFragment(sourceURL), let fragment {
            pendingAnchor = MarkdownSection.slug(fragment)
            return
        }
        openPage(target, anchor: fragment)
    }

    private func fileURLWithoutFragment(_ url: URL) -> URL {
        URL(
            fileURLWithPath: url.path,
            isDirectory: url.hasDirectoryPath
        ).standardizedFileURL
    }

    private func directoryIndex(for url: URL) throws -> String {
        let fileManager = FileManager.default
        let children = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { candidate in
            let isDirectory = (try? candidate.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            return isDirectory || Self.isReadableDocument(candidate)
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        let links = children.map { child -> String in
            let label = child.lastPathComponent.replacingOccurrences(of: "[", with: "\\[")
            let relative =
                child.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
                ?? child.lastPathComponent
            return "- [\(label)](\(relative))"
        }
        return "# \(displayTitle(for: url))\n\n"
            + (links.isEmpty ? "暂无可查看的文件。" : links.joined(separator: "\n"))
    }

    private func displayTitle(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        switch name {
        case "ThirdPartyLicenses": return "第三方许可证原文"
        case "CloudflareSpeedTest-GPL-3.0": return "CloudflareSpeedTest · GPL-3.0"
        case "Xray-core-MPL-2.0": return "Xray-core · MPL-2.0"
        default: return name
        }
    }

    private static func isReadableDocument(_ url: URL) -> Bool {
        let extensionName = url.pathExtension.lowercased()
        return extensionName.isEmpty || ["md", "markdown", "txt", "license", "notice"].contains(extensionName)
    }
}

private struct DocumentPage: Identifiable {
    let url: URL
    let title: String
    let sections: [MarkdownSection]

    init(url: URL, title: String, content: String, isDirectory: Bool) {
        self.url = url
        self.title = title
        self.sections =
            isDirectory
            ? [MarkdownSection(id: "top", content: content)]
            : MarkdownSection.parse(content)
    }

    var id: URL { url }
}

private struct MarkdownSection: Identifiable {
    let id: String
    let content: String

    static func parse(_ content: String) -> [MarkdownSection] {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var sections: [MarkdownSection] = []
        var current: [String] = []
        var usedIDs: [String: Int] = [:]
        var inFence = false

        func appendCurrent() {
            guard !current.isEmpty else { return }
            let text = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                current.removeAll(keepingCapacity: true)
                return
            }
            let heading = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
                .first.map(String.init)
            let baseID = heading.flatMap { headingText(in: $0).map(slug) } ?? "top"
            let count = usedIDs[baseID, default: 0]
            usedIDs[baseID] = count + 1
            let id = count == 0 ? baseID : "\(baseID)-\(count)"
            sections.append(MarkdownSection(id: id, content: text))
            current.removeAll(keepingCapacity: true)
        }

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
            }
            if !inFence, headingText(in: line) != nil, !current.isEmpty {
                appendCurrent()
            }
            current.append(line)
        }
        appendCurrent()
        return sections.isEmpty ? [MarkdownSection(id: "top", content: content)] : sections
    }

    static func slug(_ value: String) -> String {
        var result = ""
        var needsSeparator = false
        for scalar in value.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" {
                if needsSeparator, !result.isEmpty, !result.hasSuffix("-") {
                    result.append("-")
                }
                result.append(String(scalar))
                needsSeparator = false
            } else if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                needsSeparator = true
            }
        }
        return result.isEmpty ? "top" : result
    }

    private static func headingText(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var level = 0
        for character in trimmed {
            guard character == "#" else { break }
            level += 1
        }
        guard (1...6).contains(level) else { return nil }
        let index = trimmed.index(trimmed.startIndex, offsetBy: level)
        guard index < trimmed.endIndex, trimmed[index] == " " || trimmed[index] == "\t" else {
            return nil
        }
        return trimmed[trimmed.index(after: index)...]
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"\s+#+$"#, with: "", options: .regularExpression)
    }
}

private struct MarkdownDocument: View {
    let content: String
    let baseURL: URL
    let onOpenURL: (URL) -> Void

    var body: some View {
        if let attributed = try? AttributedString(markdown: content, baseURL: baseURL) {
            Text(attributed)
                .textSelection(.enabled)
                .font(.body)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .environment(
                    \.openURL,
                    OpenURLAction { url in
                        onOpenURL(url)
                        return .handled
                    })
        } else {
            Text(content)
                .textSelection(.enabled)
                .font(.system(.body, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
