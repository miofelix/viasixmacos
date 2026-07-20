import AppKit
import Foundation
import SwiftUI

struct AppDocumentViewer: View {
    let document: AppDocument

    @State private var pages: [DocumentPage] = []
    @State private var pendingAnchor: String?
    @State private var isLoading = true
    @State private var loadFailure: String?
    @State private var navigationFailure: String?

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
                loadFailureView
            }
        }
        .frame(minWidth: 700, minHeight: 520)
        .background(VisualStyle.pageBackground)
        .task {
            guard pages.isEmpty else { return }
            loadRootDocument()
        }
        .alert(
            "无法打开文档链接",
            isPresented: Binding(
                get: { navigationFailure != nil },
                set: { isPresented in
                    if !isPresented { navigationFailure = nil }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(navigationFailure ?? "请稍后再试。")
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
                let sections = page.sections.filter { $0.navigationTitle != nil }
                if sections.count > 1 {
                    Menu {
                        ForEach(sections) { section in
                            Button(section.navigationTitle ?? "未命名章节") {
                                pendingAnchor = section.id
                            }
                        }
                    } label: {
                        Label("章节", systemImage: "list.bullet")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("跳转到文档章节")
                }

                Menu {
                    Button("在访达中显示", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([page.url])
                    }
                    Button("复制文件路径", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(page.url.path, forType: .string)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .iconButtonHitTarget()
                .help("更多文档操作")
                .accessibilityLabel("更多文档操作")
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
                        Group {
                            switch page.contentKind {
                            case .markdown:
                                MarkdownDocument(
                                    content: section.content,
                                    baseURL: page.url,
                                    onOpenURL: { url in
                                        handleLink(url, from: page.url)
                                    }
                                )
                            case .plainText:
                                PlainTextDocument(content: section.content)
                            }
                        }
                        .id(section.id)
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 34)
                .padding(.vertical, 30)
            }
            .scrollbarSafeContent()
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
        guard AppDocumentOpener.isTrustedDocumentURL(normalizedURL) else {
            reportOpenFailure("此链接指向应用文档范围之外，已阻止打开。")
            return
        }

        do {
            let content: String
            let isDirectory = try normalizedURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
            guard isDirectory || DocumentFilePolicy.isReadableDocument(normalizedURL) else {
                reportOpenFailure("此链接不是可在应用内查看的文档。")
                return
            }
            if isDirectory {
                content = try directoryIndex(for: normalizedURL)
            } else {
                content = try String(contentsOf: normalizedURL, encoding: .utf8)
            }

            let page = DocumentPage(
                url: normalizedURL,
                title: title ?? DocumentDisplayTitle.resolve(normalizedURL),
                content: content,
                isDirectory: isDirectory
            )
            let resolvedAnchor: String?
            if let anchor {
                let anchorID = MarkdownSection.slug(anchor)
                guard page.sections.contains(where: { $0.id == anchorID }) else {
                    pendingAnchor = nil
                    reportOpenFailure("文档中没有找到对应章节。")
                    return
                }
                resolvedAnchor = anchorID
            } else {
                resolvedAnchor = nil
            }
            pages.append(page)
            loadFailure = nil
            pendingAnchor = resolvedAnchor
        } catch {
            reportOpenFailure("读取“\(DocumentDisplayTitle.resolve(normalizedURL))”失败：\(error.localizedDescription)")
        }
    }

    private func handleLink(_ url: URL, from sourceURL: URL) {
        let scheme = url.scheme?.lowercased() ?? ""
        if ["http", "https", "mailto"].contains(scheme) {
            if !NSWorkspace.shared.open(url) {
                reportOpenFailure("系统无法打开此链接。")
            }
            return
        }

        guard url.isFileURL else {
            reportOpenFailure("此链接类型暂不支持。")
            return
        }
        let target = fileURLWithoutFragment(url)
        let fragment = DocumentLinkResolver.decodedFragment(in: url)
        if target == fileURLWithoutFragment(sourceURL) {
            guard
                let anchor = DocumentLinkResolver.anchor(
                    for: fragment,
                    sectionIDs: page?.sections.map(\.id) ?? []
                )
            else {
                reportOpenFailure("文档中没有找到对应章节。")
                return
            }
            pendingAnchor = anchor
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
            return isDirectory || DocumentFilePolicy.isReadableDocument(candidate)
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        let links = children.map { child -> String in
            let label = DocumentDisplayTitle.resolve(child)
                .replacingOccurrences(of: "[", with: "\\[")
                .replacingOccurrences(of: "]", with: "\\]")
            let relative =
                child.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
                ?? child.lastPathComponent
            return "- [\(label)](\(relative))"
        }
        let title = DocumentDisplayTitle.resolve(url)
        let content = links.isEmpty ? "暂无可查看的文档。" : links.joined(separator: "\n")
        return "# \(title)\n\n\(content)"
    }

    private var loadFailureView: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "无法读取文档",
                systemImage: "doc.text.magnifyingglass",
                description: Text(loadFailure ?? "应用包中没有找到\(document.displayName)。")
            )
            Button("重新读取", systemImage: "arrow.clockwise") {
                loadRootDocument()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func loadRootDocument() {
        isLoading = true
        loadFailure = nil
        pages.removeAll()
        pendingAnchor = nil
        guard let url = AppDocumentOpener.documentURL(for: document) else {
            loadFailure = "应用包中没有找到\(document.displayName)。"
            isLoading = false
            return
        }
        openPage(url, title: document.displayName)
        isLoading = false
    }

    private func reportOpenFailure(_ message: String) {
        isLoading = false
        if pages.isEmpty {
            loadFailure = message
        } else {
            navigationFailure = message
        }
    }
}

enum DocumentDisplayTitle {
    static func resolve(_ url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        switch name {
        case "ThirdPartyLicenses": return "离线许可证原文"
        case "CloudflareSpeedTest-GPL-3.0": return "CloudflareSpeedTest · GPL-3.0"
        case "Xray-core-MPL-2.0": return "Xray-core · MPL-2.0"
        case "Yams-MIT": return "Yams · MIT"
        default: return name
        }
    }
}

enum DocumentFilePolicy {
    static func isReadableDocument(_ url: URL) -> Bool {
        let extensionName = url.pathExtension.lowercased()
        if extensionName.isEmpty {
            return ["license", "notice", "copying"].contains(
                url.lastPathComponent.lowercased()
            )
        }
        return ["md", "markdown", "txt", "license", "notice"].contains(extensionName)
    }
}

enum DocumentLinkResolver {
    static func decodedFragment(in url: URL) -> String? {
        url.fragment(percentEncoded: false)
    }

    static func anchor(for fragment: String?, sectionIDs: [String]) -> String? {
        guard !sectionIDs.isEmpty else { return nil }
        guard let fragment else { return sectionIDs.first }
        let anchor = MarkdownSection.slug(fragment)
        return sectionIDs.contains(anchor) ? anchor : nil
    }
}

private struct DocumentPage: Identifiable {
    let url: URL
    let title: String
    let sections: [MarkdownSection]
    let contentKind: DocumentContentKind

    init(url: URL, title: String, content: String, isDirectory: Bool) {
        self.url = url
        self.title = title
        contentKind = DocumentContentKind(url: url, isDirectory: isDirectory)
        switch contentKind {
        case .markdown:
            sections =
                isDirectory
                ? [MarkdownSection(id: "top", content: content)]
                : MarkdownSection.parse(content)
        case .plainText:
            sections = [MarkdownSection(id: "top", content: content)]
        }
    }

    var id: URL { url }
}

enum DocumentContentKind: Equatable {
    case markdown
    case plainText

    init(url: URL, isDirectory: Bool) {
        let extensionName = url.pathExtension.lowercased()
        self =
            isDirectory || extensionName == "md" || extensionName == "markdown"
            ? .markdown
            : .plainText
    }
}

struct MarkdownSection: Identifiable, Equatable {
    let id: String
    let content: String

    var navigationTitle: String? {
        guard let firstLine = content.split(separator: "\n", maxSplits: 1).first else {
            return nil
        }
        return Self.headingText(in: String(firstLine))
    }

    static func parse(_ content: String) -> [MarkdownSection] {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var sections: [MarkdownSection] = []
        var current: [String] = []
        var usedIDs: [String: Int] = [:]
        var activeFence: MarkdownBlockParser.FenceDelimiter?

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
            if let fence = activeFence {
                current.append(line)
                if MarkdownBlockParser.isClosingFence(line, matching: fence) {
                    activeFence = nil
                }
                continue
            }
            if let fence = MarkdownBlockParser.fenceDelimiter(in: line) {
                activeFence = fence
                current.append(line)
                continue
            }
            if headingText(in: line) != nil, !current.isEmpty {
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
        MarkdownBlockParser.atxHeading(in: line)?.text
    }
}

struct MarkdownBlockParser {
    enum Block: Equatable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case unorderedList([String])
        case orderedList([OrderedItem])
        case quote(String)
        case admonition(kind: AdmonitionKind, title: String?, body: String)
        case code(language: String?, content: String)
        case table(headers: [String], alignments: [TableAlignment], rows: [[String]])
        case thematicBreak
    }

    struct OrderedItem: Equatable {
        let ordinal: Int
        let text: String
    }

    enum AdmonitionKind: String, Equatable {
        case note
        case tip
        case important
        case warning
        case caution

        var displayName: String {
            switch self {
            case .note: return "说明"
            case .tip: return "提示"
            case .important: return "重要"
            case .warning: return "警告"
            case .caution: return "注意"
            }
        }
    }

    enum TableAlignment: Equatable {
        case leading
        case center
        case trailing
    }

    struct ATXHeading: Equatable {
        let level: Int
        let text: String
    }

    struct FenceDelimiter: Equatable {
        let marker: Character
        let length: Int
    }

    private enum ListKind: Equatable {
        case unordered
        case ordered
    }

    private struct ListMarker {
        let kind: ListKind
        let ordinal: Int?
        let text: String
    }

    private struct FenceOpening {
        let marker: Character
        let length: Int
        let language: String?
    }

    static func parse(_ content: String) -> [Block] {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [Block] = []
        var index = 0

        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                index += 1
                continue
            }

            if let opening = fenceOpening(in: lines[index]) {
                var codeLines: [String] = []
                index += 1
                while index < lines.count,
                    !isClosingFence(
                        lines[index],
                        marker: opening.marker,
                        minimumLength: opening.length
                    )
                {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count {
                    index += 1
                }
                blocks.append(
                    .code(
                        language: opening.language,
                        content: codeLines.joined(separator: "\n")
                    ))
                continue
            }

            if let heading = atxHeading(in: lines[index]) {
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if isThematicBreak(lines[index]) {
                blocks.append(.thematicBreak)
                index += 1
                continue
            }

            if let table = table(at: index, in: lines) {
                blocks.append(table.block)
                index = table.nextIndex
                continue
            }

            if quoteContent(in: lines[index]) != nil {
                var quoteLines: [String] = []
                while index < lines.count, let quoteLine = quoteContent(in: lines[index]) {
                    quoteLines.append(quoteLine)
                    index += 1
                }
                blocks.append(quoteBlock(from: quoteLines))
                continue
            }

            if let marker = listMarker(in: lines[index]) {
                let list = list(startingAt: index, firstMarker: marker, in: lines)
                blocks.append(list.block)
                index = list.nextIndex
                continue
            }

            var paragraphLines: [String] = []
            while index < lines.count {
                if lines[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    break
                }
                if !paragraphLines.isEmpty, startsBlock(at: index, in: lines) {
                    break
                }
                paragraphLines.append(lines[index])
                index += 1
            }
            let paragraph = paragraphLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph))
            }
        }

        return blocks
    }

    static func atxHeading(in line: String) -> ATXHeading? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var level = 0
        for character in trimmed {
            guard character == "#" else { break }
            level += 1
        }
        guard (1...6).contains(level) else { return nil }
        let separatorIndex = trimmed.index(trimmed.startIndex, offsetBy: level)
        guard separatorIndex < trimmed.endIndex,
            trimmed[separatorIndex] == " " || trimmed[separatorIndex] == "\t"
        else {
            return nil
        }
        let text = trimmed[trimmed.index(after: separatorIndex)...]
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"\s+#+$"#, with: "", options: .regularExpression)
        return ATXHeading(level: level, text: text)
    }

    static func fenceDelimiter(in line: String) -> FenceDelimiter? {
        fenceOpening(in: line).map {
            FenceDelimiter(marker: $0.marker, length: $0.length)
        }
    }

    static func isClosingFence(_ line: String, matching fence: FenceDelimiter) -> Bool {
        isClosingFence(
            line,
            marker: fence.marker,
            minimumLength: fence.length
        )
    }

    private static func startsBlock(at index: Int, in lines: [String]) -> Bool {
        fenceOpening(in: lines[index]) != nil
            || atxHeading(in: lines[index]) != nil
            || isThematicBreak(lines[index])
            || table(at: index, in: lines) != nil
            || quoteContent(in: lines[index]) != nil
            || listMarker(in: lines[index]) != nil
    }

    private static func fenceOpening(in line: String) -> FenceOpening? {
        let indentation = line.prefix { $0 == " " }.count
        guard indentation <= 3 else { return nil }
        let trimmed = line.dropFirst(indentation)
        guard let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
        let length = trimmed.prefix { $0 == marker }.count
        guard length >= 3 else { return nil }
        let info = trimmed.dropFirst(length).trimmingCharacters(in: .whitespaces)
        if marker == "`", info.contains("`") {
            return nil
        }
        let language = info.split(whereSeparator: \.isWhitespace).first.map(String.init)
        return FenceOpening(marker: marker, length: length, language: language)
    }

    private static func isClosingFence(
        _ line: String,
        marker: Character,
        minimumLength: Int
    ) -> Bool {
        let indentation = line.prefix { $0 == " " }.count
        guard indentation <= 3 else { return false }
        let trimmed = line.dropFirst(indentation)
        let markerLength = trimmed.prefix { $0 == marker }.count
        guard markerLength >= minimumLength else { return false }
        return trimmed.dropFirst(markerLength).allSatisfy(\.isWhitespace)
    }

    private static func isThematicBreak(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmed.first, marker == "-" || marker == "*" || marker == "_" else {
            return false
        }
        var count = 0
        for character in trimmed {
            if character == marker {
                count += 1
            } else if !character.isWhitespace {
                return false
            }
        }
        return count >= 3
    }

    private static func listMarker(in line: String) -> ListMarker? {
        let indentation = line.prefix { $0 == " " }.count
        guard indentation <= 3 else { return nil }
        let text = line.dropFirst(indentation)
        guard let first = text.first else { return nil }

        if first == "-" || first == "+" || first == "*" {
            let contentStart = text.index(after: text.startIndex)
            guard contentStart < text.endIndex, text[contentStart].isWhitespace else { return nil }
            let content = text[contentStart...].drop(while: \.isWhitespace)
            return ListMarker(kind: .unordered, ordinal: nil, text: String(content))
        }

        let digits = text.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= 9, let ordinal = Int(digits) else { return nil }
        let punctuationIndex = text.index(text.startIndex, offsetBy: digits.count)
        guard punctuationIndex < text.endIndex,
            text[punctuationIndex] == "." || text[punctuationIndex] == ")"
        else {
            return nil
        }
        let contentStart = text.index(after: punctuationIndex)
        guard contentStart < text.endIndex, text[contentStart].isWhitespace else { return nil }
        let content = text[contentStart...].drop(while: \.isWhitespace)
        return ListMarker(kind: .ordered, ordinal: ordinal, text: String(content))
    }

    private static func list(
        startingAt startIndex: Int,
        firstMarker: ListMarker,
        in lines: [String]
    ) -> (block: Block, nextIndex: Int) {
        var index = startIndex
        var unorderedItems: [String] = []
        var orderedItems: [OrderedItem] = []

        while index < lines.count, let marker = listMarker(in: lines[index]),
            marker.kind == firstMarker.kind
        {
            switch marker.kind {
            case .unordered:
                unorderedItems.append(marker.text)
            case .ordered:
                orderedItems.append(OrderedItem(ordinal: marker.ordinal ?? 1, text: marker.text))
            }
            index += 1

            while index < lines.count, isListContinuation(lines[index]) {
                let continuation = lines[index].trimmingCharacters(in: .whitespaces)
                switch marker.kind {
                case .unordered:
                    unorderedItems[unorderedItems.count - 1] += "\n" + continuation
                case .ordered:
                    let itemIndex = orderedItems.count - 1
                    let item = orderedItems[itemIndex]
                    orderedItems[itemIndex] = OrderedItem(
                        ordinal: item.ordinal,
                        text: item.text + "\n" + continuation
                    )
                }
                index += 1
            }
        }

        switch firstMarker.kind {
        case .unordered:
            return (.unorderedList(unorderedItems), index)
        case .ordered:
            return (.orderedList(orderedItems), index)
        }
    }

    private static func isListContinuation(_ line: String) -> Bool {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        let indentation = line.prefix { $0 == " " || $0 == "\t" }.count
        return indentation >= 2 && listMarker(in: line) == nil
    }

    private static func quoteContent(in line: String) -> String? {
        let indentation = line.prefix { $0 == " " }.count
        guard indentation <= 3 else { return nil }
        let trimmed = line.dropFirst(indentation)
        guard trimmed.first == ">" else { return nil }
        var content = trimmed.dropFirst()
        if content.first == " " || content.first == "\t" {
            content = content.dropFirst()
        }
        return String(content)
    }

    private static func quoteBlock(from lines: [String]) -> Block {
        guard let first = lines.first else { return .quote("") }
        let trimmed = first.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[!"), let closingBracket = trimmed.firstIndex(of: "]") else {
            return .quote(lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let kindStart = trimmed.index(trimmed.startIndex, offsetBy: 2)
        let marker = String(trimmed[kindStart..<closingBracket]).lowercased()
        guard let kind = AdmonitionKind(rawValue: marker) else {
            return .quote(lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let titleValue = trimmed[trimmed.index(after: closingBracket)...]
            .trimmingCharacters(in: .whitespaces)
        let body = lines.dropFirst().joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .admonition(
            kind: kind,
            title: titleValue.isEmpty ? nil : titleValue,
            body: body
        )
    }

    private static func table(
        at index: Int,
        in lines: [String]
    ) -> (block: Block, nextIndex: Int)? {
        guard index + 1 < lines.count,
            let headers = tableCells(in: lines[index]),
            headers.count >= 2,
            let delimiterCells = tableCells(in: lines[index + 1]),
            delimiterCells.count == headers.count
        else {
            return nil
        }

        var alignments: [TableAlignment] = []
        for cell in delimiterCells {
            guard let alignment = tableAlignment(in: cell) else { return nil }
            alignments.append(alignment)
        }

        var rows: [[String]] = []
        var nextIndex = index + 2
        while nextIndex < lines.count,
            !lines[nextIndex].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let cells = tableCells(in: lines[nextIndex])
        {
            if cells.count > headers.count {
                break
            }
            rows.append(cells + Array(repeating: "", count: headers.count - cells.count))
            nextIndex += 1
        }

        return (
            .table(headers: headers, alignments: alignments, rows: rows),
            nextIndex
        )
    }

    private static func tableCells(in line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return nil }
        var value = trimmed
        if value.first == "|" {
            value.removeFirst()
        }
        if value.last == "|" {
            value.removeLast()
        }

        var cells: [String] = []
        var current = ""
        var isEscaped = false
        var isInCodeSpan = false
        for character in value {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }
            if character == "\\" {
                current.append(character)
                isEscaped = true
                continue
            }
            if character == "`" {
                isInCodeSpan.toggle()
                current.append(character)
                continue
            }
            if character == "|", !isInCodeSpan {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(character)
            }
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func tableAlignment(in cell: String) -> TableAlignment? {
        var marker = cell.trimmingCharacters(in: .whitespaces)
        let isLeading = marker.first == ":"
        let isTrailing = marker.last == ":"
        if isLeading {
            marker.removeFirst()
        }
        if isTrailing, !marker.isEmpty {
            marker.removeLast()
        }
        guard marker.count >= 3, marker.allSatisfy({ $0 == "-" }) else { return nil }
        if isLeading && isTrailing {
            return .center
        }
        return isTrailing ? .trailing : .leading
    }
}

private struct MarkdownDocument: View {
    let content: String
    let baseURL: URL
    let onOpenURL: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(MarkdownBlockParser.parse(content).enumerated()), id: \.offset) { entry in
                MarkdownBlockView(block: entry.element, baseURL: baseURL)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(
            \.openURL,
            OpenURLAction { url in
                onOpenURL(url)
                return .handled
            })
    }
}

private struct PlainTextDocument: View {
    let content: String

    var body: some View {
        ScrollView(.horizontal) {
            Text(verbatim: content)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .lineSpacing(3)
                .fixedSize(horizontal: true, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .horizontalScrollbarSafeContent()
        .scrollIndicators(.automatic)
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlockParser.Block
    let baseURL: URL

    @ViewBuilder
    var body: some View {
        switch block {
        case .heading(let level, let text):
            MarkdownInlineText(source: text, baseURL: baseURL)
                .font(headingFont(for: level))
                .fontWeight(level <= 3 ? .bold : .semibold)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, level == 1 ? 2 : 6)

        case .paragraph(let text):
            MarkdownInlineText(source: text, baseURL: baseURL)
                .font(.body)

        case .unorderedList(let items):
            MarkdownUnorderedList(items: items, baseURL: baseURL)

        case .orderedList(let items):
            MarkdownOrderedList(items: items, baseURL: baseURL)

        case .quote(let text):
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.secondary.opacity(0.55))
                    .frame(width: 3)
                MarkdownInlineText(source: text, baseURL: baseURL)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
                    .padding(.vertical, 3)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .admonition(let kind, let title, let text):
            MarkdownAdmonition(kind: kind, title: title, text: text, baseURL: baseURL)

        case .code(let language, let content):
            MarkdownCodeBlock(language: language, content: content)

        case .table(let headers, let alignments, let rows):
            MarkdownTable(
                headers: headers,
                alignments: alignments,
                rows: rows,
                baseURL: baseURL
            )

        case .thematicBreak:
            Divider()
                .padding(.vertical, 5)
        }
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return .title
        case 2: return .title2
        case 3: return .title3
        case 4: return .headline
        case 5: return .subheadline
        default: return .footnote
        }
    }
}

private struct MarkdownInlineText: View {
    let source: String
    let baseURL: URL

    var body: some View {
        Group {
            if let attributed = try? AttributedString(
                markdown: source,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace),
                baseURL: baseURL
            ) {
                Text(attributed)
            } else {
                Text(source)
            }
        }
        .textSelection(.enabled)
        .lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct MarkdownUnorderedList: View {
    let items: [String]
    let baseURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(items.enumerated()), id: \.offset) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text("•")
                        .foregroundStyle(.secondary)
                        .frame(width: 14, alignment: .trailing)
                    MarkdownInlineText(source: entry.element, baseURL: baseURL)
                        .font(.body)
                }
            }
        }
        .padding(.leading, 4)
    }
}

private struct MarkdownOrderedList: View {
    let items: [MarkdownBlockParser.OrderedItem]
    let baseURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(items.enumerated()), id: \.offset) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text("\(entry.element.ordinal).")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 24, alignment: .trailing)
                    MarkdownInlineText(source: entry.element.text, baseURL: baseURL)
                        .font(.body)
                }
            }
        }
        .padding(.leading, 4)
    }
}

private struct MarkdownAdmonition: View {
    let kind: MarkdownBlockParser.AdmonitionKind
    let title: String?
    let text: String
    let baseURL: URL

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: iconName)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 6) {
                Text(title ?? kind.displayName)
                    .font(.headline)
                    .foregroundStyle(tint)
                if !text.isEmpty {
                    MarkdownInlineText(source: text, baseURL: baseURL)
                        .font(.body)
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.32), lineWidth: 1)
        }
    }

    private var tint: Color {
        switch kind {
        case .note: return .blue
        case .tip: return .green
        case .important: return .purple
        case .warning: return .orange
        case .caution: return .red
        }
    }

    private var iconName: String {
        switch kind {
        case .note: return "info.circle.fill"
        case .tip: return "lightbulb.fill"
        case .important: return "exclamationmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .caution: return "hand.raised.fill"
        }
    }
}

private struct MarkdownCodeBlock: View {
    let language: String?
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language, !language.isEmpty {
                Text(language)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                Divider()
            }
            ScrollView(.horizontal) {
                Text(verbatim: content.isEmpty ? " " : content)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .padding(12)
                    .fixedSize(horizontal: true, vertical: true)
            }
            .horizontalScrollbarSafeContent()
            .scrollIndicators(.automatic)
        }
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(VisualStyle.surfaceBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct MarkdownTable: View {
    let headers: [String]
    let alignments: [MarkdownBlockParser.TableAlignment]
    let rows: [[String]]
    let baseURL: URL

    var body: some View {
        ScrollView(.horizontal) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(headers.indices, id: \.self) { column in
                        cell(
                            headers[column],
                            alignment: alignments[column],
                            isHeader: true
                        )
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { row in
                    GridRow {
                        ForEach(headers.indices, id: \.self) { column in
                            cell(
                                row.element[column],
                                alignment: alignments[column],
                                isHeader: false
                            )
                        }
                    }
                }
            }
        }
        .horizontalScrollbarSafeContent()
        .scrollIndicators(.automatic)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(VisualStyle.surfaceBorder, lineWidth: 1)
        }
    }

    private func cell(
        _ text: String,
        alignment: MarkdownBlockParser.TableAlignment,
        isHeader: Bool
    ) -> some View {
        MarkdownInlineText(source: text, baseURL: baseURL)
            .font(isHeader ? .headline : .body)
            .frame(minWidth: 110, maxWidth: 260, alignment: alignment.swiftUIAlignment)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isHeader
                    ? Color(nsColor: .controlBackgroundColor)
                    : Color(nsColor: .textBackgroundColor).opacity(0.45)
            )
            .overlay {
                Rectangle()
                    .stroke(VisualStyle.surfaceBorder.opacity(0.7), lineWidth: 0.5)
            }
    }
}

private extension MarkdownBlockParser.TableAlignment {
    var swiftUIAlignment: Alignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}
