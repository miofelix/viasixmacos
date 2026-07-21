import XCTest

@testable import ViaSixApp

final class NodeResultsEmptyPresentationTests: XCTestCase {
    func testRuntimeOperationTakesPriorityOverOtherEmptyStates() {
        let presentation = NodeResultsEmptyPresentation(
            speedTestPhase: .failed("旧错误"),
            runtimeOperationDescription: "正在下载 CloudflareSpeedTest",
            isTemplateOperationBusy: true,
            isApplyingNode: true,
            isCfstBusyElsewhere: true,
            hasCfstExecutable: false,
            parameterValidationMessage: "端口无效"
        )

        XCTAssertEqual(presentation.title, "正在准备测速组件")
        XCTAssertEqual(presentation.description, "正在下载 CloudflareSpeedTest")
        XCTAssertEqual(presentation.systemImage, "shippingbox")
        XCTAssertEqual(presentation.tone, .accent)
        XCTAssertEqual(presentation.action, .none)
        XCTAssertNil(presentation.actionTitle)
        XCTAssertTrue(presentation.isBusy)
    }

    func testCurrentNodeTestExplainsWhyCandidateScanCannotStart() {
        let presentation = NodeResultsEmptyPresentation(
            speedTestPhase: .idle,
            isCfstBusyElsewhere: true
        )

        XCTAssertEqual(presentation.title, "正在测试当前节点")
        XCTAssertEqual(
            presentation.description,
            "完成当前节点测速后，即可开始候选节点扫描。"
        )
        XCTAssertEqual(presentation.systemImage, "scope")
        XCTAssertEqual(presentation.action, .none)
        XCTAssertTrue(presentation.isBusy)
    }

    func testProxyConfigurationOperationBlocksEmptyStateAction() {
        let presentation = NodeResultsEmptyPresentation(
            speedTestPhase: .idle,
            isTemplateOperationBusy: true
        )

        XCTAssertEqual(presentation.title, "正在处理代理配置")
        XCTAssertEqual(
            presentation.description,
            "代理配置处理完成后，即可开始候选节点测速。"
        )
        XCTAssertEqual(presentation.systemImage, "doc.badge.gearshape")
        XCTAssertEqual(presentation.tone, .warning)
        XCTAssertEqual(presentation.action, .none)
        XCTAssertTrue(presentation.isBusy)
    }

    func testApplyingNodeBlocksEmptyStateAction() {
        let presentation = NodeResultsEmptyPresentation(
            speedTestPhase: .idle,
            isApplyingNode: true
        )

        XCTAssertEqual(presentation.title, "正在应用节点")
        XCTAssertEqual(presentation.description, "节点应用完成后，即可继续测速。")
        XCTAssertEqual(presentation.systemImage, "arrow.triangle.2.circlepath")
        XCTAssertEqual(presentation.tone, .warning)
        XCTAssertEqual(presentation.action, .none)
        XCTAssertTrue(presentation.isBusy)
    }

    func testRunningAndStoppingStatesDoNotOfferImpossibleActions() {
        let running = NodeResultsEmptyPresentation(speedTestPhase: .running)
        XCTAssertEqual(running.title, "正在生成候选节点")
        XCTAssertEqual(running.tone, .accent)
        XCTAssertEqual(running.action, .none)
        XCTAssertNil(running.actionTitle)
        XCTAssertTrue(running.isBusy)

        let stopping = NodeResultsEmptyPresentation(speedTestPhase: .stopping)
        XCTAssertEqual(stopping.title, "正在停止测速")
        XCTAssertEqual(stopping.tone, .warning)
        XCTAssertEqual(stopping.action, .none)
        XCTAssertNil(stopping.actionTitle)
        XCTAssertTrue(stopping.isBusy)
    }

    func testMissingComponentDirectsTheUserToSettings() {
        let presentation = NodeResultsEmptyPresentation(
            speedTestPhase: .failed("找不到可执行文件"),
            hasCfstExecutable: false,
            parameterValidationMessage: "端口无效"
        )

        XCTAssertEqual(presentation.title, "需要安装测速组件")
        XCTAssertEqual(
            presentation.description,
            "安装 CloudflareSpeedTest 后即可扫描候选节点。"
        )
        XCTAssertEqual(presentation.tone, .warning)
        XCTAssertEqual(presentation.action, .openSettings)
        XCTAssertEqual(presentation.actionTitle, "打开设置")
        XCTAssertFalse(presentation.isBusy)
    }

    func testInvalidParametersDirectTheUserToParameterControls() {
        let presentation = NodeResultsEmptyPresentation(
            speedTestPhase: .idle,
            parameterValidationMessage: "测速端口必须在 1–65535 之间"
        )

        XCTAssertEqual(presentation.title, "测速参数需要调整")
        XCTAssertEqual(
            presentation.description,
            "测速端口必须在 1–65535 之间"
        )
        XCTAssertEqual(presentation.systemImage, "slider.horizontal.3")
        XCTAssertEqual(presentation.action, .showParameters)
        XCTAssertEqual(presentation.actionTitle, "检查测速参数")
        XCTAssertFalse(presentation.isBusy)
    }

    func testFailureOffersRetryAndKeepsDiagnostic() {
        let presentation = NodeResultsEmptyPresentation(
            speedTestPhase: .failed("连接超时")
        )

        XCTAssertEqual(presentation.title, "本次测速未完成")
        XCTAssertEqual(presentation.description, "连接超时")
        XCTAssertEqual(presentation.tone, .negative)
        XCTAssertEqual(presentation.action, .startSpeedTest)
        XCTAssertEqual(presentation.actionTitle, "重新测速")
        XCTAssertFalse(presentation.isBusy)
    }

    func testBlankFailureUsesReadableFallback() {
        let presentation = NodeResultsEmptyPresentation(
            speedTestPhase: .failed("  \n")
        )

        XCTAssertEqual(presentation.description, "请检查网络后重试。")
    }

    func testIdleStateOffersInitialSpeedTest() {
        let presentation = NodeResultsEmptyPresentation(speedTestPhase: .idle)

        XCTAssertEqual(presentation.title, "暂无测速结果")
        XCTAssertEqual(
            presentation.description,
            "选择地址来源并开始测速，候选节点会显示在这里。"
        )
        XCTAssertEqual(presentation.systemImage, "network.slash")
        XCTAssertEqual(presentation.tone, .neutral)
        XCTAssertEqual(presentation.action, .startSpeedTest)
        XCTAssertEqual(presentation.actionTitle, "开始测速")
        XCTAssertFalse(presentation.isBusy)
    }
}
