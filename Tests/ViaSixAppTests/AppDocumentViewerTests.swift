import XCTest

@testable import ViaSixApp

final class AppDocumentViewerTests: XCTestCase {
    func testMarkdownParserCreatesSemanticBlocks() {
        let markdown = """
            # 概览

            这是一个带有[文档链接](guide.md)的段落。

            - 第一项
            - 第二项 **强调**

            1. 首先
            2. 然后

            > 普通引用，保留[链接](https://example.com)。

            > [!WARNING] 发布前确认
            > 这是警告正文。

            ```swift
            let value = "| not a table |"
            ```

            | 名称 | 状态 | 备注 |
            | --- | :---: | ---: |
            | ViaSix | 好 | `ready` |

            ***
            """

        let blocks = MarkdownBlockParser.parse(markdown)
        XCTAssertEqual(blocks.count, 9)
        XCTAssertEqual(blocks[0], .heading(level: 1, text: "概览"))
        XCTAssertEqual(
            blocks[1],
            .paragraph("这是一个带有[文档链接](guide.md)的段落。")
        )
        XCTAssertEqual(blocks[2], .unorderedList(["第一项", "第二项 **强调**"]))
        XCTAssertEqual(
            blocks[3],
            .orderedList([
                .init(ordinal: 1, text: "首先"),
                .init(ordinal: 2, text: "然后"),
            ])
        )
        XCTAssertEqual(
            blocks[4],
            .quote("普通引用，保留[链接](https://example.com)。")
        )
        XCTAssertEqual(
            blocks[5],
            .admonition(
                kind: .warning,
                title: "发布前确认",
                body: "这是警告正文。"
            )
        )
        XCTAssertEqual(
            blocks[6],
            .code(language: "swift", content: "let value = \"| not a table |\"")
        )
        XCTAssertEqual(
            blocks[7],
            .table(
                headers: ["名称", "状态", "备注"],
                alignments: [.leading, .center, .trailing],
                rows: [["ViaSix", "好", "`ready`"]]
            )
        )
        XCTAssertEqual(blocks[8], .thematicBreak)
    }

    func testMarkdownParserKeepsHeadingsAndPipesInsideFencedCode() {
        let markdown = """
            ~~~text
            # 不是标题
            | 不是 | 表格 |
            ~~~

            ## 真正的标题
            """

        XCTAssertEqual(
            MarkdownBlockParser.parse(markdown),
            [
                .code(
                    language: "text",
                    content: "# 不是标题\n| 不是 | 表格 |"
                ),
                .heading(level: 2, text: "真正的标题"),
            ]
        )
    }

    func testSectionsGenerateStableAnchorsAndIgnoreFencedHeadings() {
        let markdown = """
            # 同一标题

            ```
            # 代码中的标题
            ```

            ## 同一标题
            """

        let sections = MarkdownSection.parse(markdown)
        XCTAssertEqual(sections.map(\.id), ["同一标题", "同一标题-1"])
        XCTAssertTrue(sections[0].content.contains("# 代码中的标题"))
        XCTAssertFalse(sections[1].content.contains("代码中的标题"))
    }

    func testSectionsExposeSemanticNavigationTitles() {
        let sections = MarkdownSection.parse(
            """
            开场说明

            ## 安装与更新

            内容

            ### 常见问题
            """
        )

        XCTAssertEqual(
            sections.compactMap(\.navigationTitle),
            ["安装与更新", "常见问题"]
        )
    }

    func testKnownLicenseFilesUseReadableTitles() {
        XCTAssertEqual(
            DocumentDisplayTitle.resolve(
                URL(fileURLWithPath: "/tmp/ThirdPartyLicenses")
            ),
            "离线许可证原文"
        )
        XCTAssertEqual(
            DocumentDisplayTitle.resolve(
                URL(fileURLWithPath: "/tmp/CloudflareSpeedTest-GPL-3.0.txt")
            ),
            "CloudflareSpeedTest · GPL-3.0"
        )
        XCTAssertEqual(
            DocumentDisplayTitle.resolve(
                URL(fileURLWithPath: "/tmp/Xray-core-MPL-2.0.txt")
            ),
            "Xray-core · MPL-2.0"
        )
        XCTAssertEqual(
            DocumentDisplayTitle.resolve(
                URL(fileURLWithPath: "/tmp/Yams-MIT.txt")
            ),
            "Yams · MIT"
        )
    }

    func testPlainTextDocumentsDoNotUseMarkdownBlockParsing() {
        XCTAssertEqual(
            DocumentContentKind(url: URL(fileURLWithPath: "/tmp/LICENSE"), isDirectory: false),
            .plainText
        )
        XCTAssertEqual(
            DocumentContentKind(url: URL(fileURLWithPath: "/tmp/ThirdParty.md"), isDirectory: false),
            .markdown
        )
        XCTAssertEqual(
            DocumentContentKind(url: URL(fileURLWithPath: "/tmp/ThirdPartyLicenses"), isDirectory: true),
            .markdown
        )
    }

    func testDocumentLinkResolverDecodesLocalizedAnchor() throws {
        let url = try XCTUnwrap(
            URL(string: "file:///tmp/guide.md#1-%E8%AE%A4%E8%AF%86-viasix")
        )

        let fragment = try XCTUnwrap(DocumentLinkResolver.decodedFragment(in: url))
        XCTAssertEqual(fragment, "1-认识-viasix")
        XCTAssertEqual(MarkdownSection.slug(fragment), "1-认识-viasix")
    }

    func testDocumentLinkResolverUsesFirstSectionAndRejectsUnknownAnchors() {
        let sectionIDs = ["概览", "安装与更新"]
        XCTAssertEqual(
            DocumentLinkResolver.anchor(for: nil, sectionIDs: sectionIDs),
            "概览"
        )
        XCTAssertEqual(
            DocumentLinkResolver.anchor(for: "安装与更新", sectionIDs: sectionIDs),
            "安装与更新"
        )
        XCTAssertNil(
            DocumentLinkResolver.anchor(for: "不存在", sectionIDs: sectionIDs)
        )
    }

    func testDocumentFilePolicyRejectsNonDocumentExtensions() {
        XCTAssertTrue(
            DocumentFilePolicy.isReadableDocument(URL(fileURLWithPath: "/tmp/LICENSE"))
        )
        XCTAssertTrue(
            DocumentFilePolicy.isReadableDocument(URL(fileURLWithPath: "/tmp/license.txt"))
        )
        XCTAssertTrue(
            DocumentFilePolicy.isReadableDocument(URL(fileURLWithPath: "/tmp/guide.MD"))
        )
        XCTAssertFalse(
            DocumentFilePolicy.isReadableDocument(URL(fileURLWithPath: "/tmp/config.json"))
        )
        XCTAssertFalse(
            DocumentFilePolicy.isReadableDocument(URL(fileURLWithPath: "/tmp/tool.command"))
        )
        XCTAssertFalse(
            DocumentFilePolicy.isReadableDocument(URL(fileURLWithPath: "/tmp/Makefile"))
        )
    }
}
