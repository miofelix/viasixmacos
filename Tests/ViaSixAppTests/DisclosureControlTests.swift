import XCTest

@testable import ViaSixApp

final class DisclosureControlTests: XCTestCase {
    func testCollapsedPresentationDescribesExpansionAction() {
        let presentation = DisclosurePresentation(
            title: "测速参数",
            summary: "IPv6 · TCPing",
            isExpanded: false
        )

        XCTAssertEqual(presentation.helpText, "展开测速参数")
        XCTAssertEqual(presentation.accessibilityValue, "已收起，IPv6 · TCPing")
        XCTAssertEqual(presentation.accessibilityHint, "按下可展开")
    }

    func testExpandedPresentationDescribesCollapseAction() {
        let presentation = DisclosurePresentation(
            title: "自定义可执行文件",
            summary: nil,
            isExpanded: true
        )

        XCTAssertEqual(presentation.helpText, "收起自定义可执行文件")
        XCTAssertEqual(presentation.accessibilityValue, "已展开")
        XCTAssertEqual(presentation.accessibilityHint, "按下可收起")
    }
}
