import ViaSixCore
import XCTest

@testable import ViaSixApp

final class SidebarProxyPresentationTests: XCTestCase {
    private let endpoint = ProxyEndpoint(host: "::1", port: 11_451)

    func testIdleAndLoadingOverrideRuntimeState() {
        for launchPhase in [AppState.LaunchPhase.idle, .loading] {
            let presentation = SidebarProxyPresentation(
                launchPhase: launchPhase,
                proxyCorePhase: .running,
                endpoint: endpoint
            )

            XCTAssertEqual(presentation.statusTitle, "正在准备 ViaSix")
            XCTAssertEqual(presentation.detailText, "正在检查应用数据与运行组件")
            XCTAssertEqual(presentation.tone, .accent)
            XCTAssertNil(presentation.endpointSummary)
            XCTAssertEqual(presentation.actionTitle, "正在准备")
            XCTAssertEqual(presentation.actionSystemImage, "hourglass")
            XCTAssertEqual(presentation.action, .none)
            XCTAssertTrue(presentation.isBusy)
        }
    }

    func testLaunchFailureOverridesRuntimeStateAndKeepsDiagnostic() {
        let presentation = SidebarProxyPresentation(
            launchPhase: .failed("无法读取应用数据"),
            proxyCorePhase: .running,
            endpoint: endpoint
        )

        XCTAssertEqual(presentation.statusTitle, "初始化失败")
        XCTAssertEqual(presentation.detailText, "无法读取应用数据")
        XCTAssertEqual(presentation.tone, .negative)
        XCTAssertNil(presentation.endpointSummary)
        XCTAssertEqual(presentation.actionTitle, "初始化未完成")
        XCTAssertEqual(
            presentation.actionSystemImage,
            "exclamationmark.triangle.fill"
        )
        XCTAssertEqual(presentation.action, .none)
        XCTAssertFalse(presentation.isBusy)
    }

    func testReadyStoppedPresentationOffersStart() {
        let presentation = readyPresentation(.stopped)

        XCTAssertEqual(presentation.statusTitle, "本地代理未启动")
        XCTAssertNil(presentation.detailText)
        XCTAssertEqual(presentation.tone, .neutral)
        XCTAssertEqual(presentation.endpointSummary, "[::1]:11451")
        XCTAssertEqual(presentation.actionTitle, "启动代理")
        XCTAssertEqual(presentation.actionSystemImage, "play.fill")
        XCTAssertEqual(presentation.action, .startProxy)
        XCTAssertFalse(presentation.isBusy)
    }

    func testReadyValidationAndStartupOfferCancellation() {
        let expectations: [(AppState.ProxyCorePhase, String)] = [
            (.validating, "正在校验配置"),
            (.starting, "正在启动代理"),
        ]

        for (phase, statusTitle) in expectations {
            let presentation = readyPresentation(phase)

            XCTAssertEqual(presentation.statusTitle, statusTitle)
            XCTAssertEqual(presentation.tone, .warning)
            XCTAssertEqual(presentation.endpointSummary, "[::1]:11451")
            XCTAssertEqual(presentation.actionTitle, "取消启动")
            XCTAssertEqual(presentation.actionSystemImage, "stop.fill")
            XCTAssertEqual(presentation.action, .stopProxy)
            XCTAssertTrue(presentation.isBusy)
        }
    }

    func testReadyRunningPresentationOffersStop() {
        let presentation = readyPresentation(.running)

        XCTAssertEqual(presentation.statusTitle, "本地代理运行中")
        XCTAssertEqual(presentation.tone, .positive)
        XCTAssertEqual(presentation.endpointSummary, "[::1]:11451")
        XCTAssertEqual(presentation.actionTitle, "停止代理")
        XCTAssertEqual(presentation.actionSystemImage, "stop.fill")
        XCTAssertEqual(presentation.action, .stopProxy)
        XCTAssertFalse(presentation.isBusy)
    }

    func testReadyStoppingPresentationDoesNotSuggestStarting() {
        let presentation = readyPresentation(.stopping)

        XCTAssertEqual(presentation.statusTitle, "正在停止代理")
        XCTAssertEqual(presentation.tone, .warning)
        XCTAssertEqual(presentation.endpointSummary, "[::1]:11451")
        XCTAssertEqual(presentation.actionTitle, "正在停止")
        XCTAssertEqual(presentation.actionSystemImage, "hourglass")
        XCTAssertEqual(presentation.action, .none)
        XCTAssertTrue(presentation.isBusy)
    }

    func testReadyFailureOffersRetryAndKeepsDiagnostic() {
        let presentation = readyPresentation(.failed("端口已被占用"))

        XCTAssertEqual(presentation.statusTitle, "本地代理异常")
        XCTAssertEqual(presentation.detailText, "端口已被占用")
        XCTAssertEqual(presentation.tone, .negative)
        XCTAssertEqual(presentation.endpointSummary, "[::1]:11451")
        XCTAssertEqual(presentation.actionTitle, "重新启动")
        XCTAssertEqual(presentation.actionSystemImage, "arrow.clockwise")
        XCTAssertEqual(presentation.action, .startProxy)
        XCTAssertFalse(presentation.isBusy)
    }

    private func readyPresentation(
        _ proxyCorePhase: AppState.ProxyCorePhase
    ) -> SidebarProxyPresentation {
        SidebarProxyPresentation(
            launchPhase: .ready,
            proxyCorePhase: proxyCorePhase,
            endpoint: endpoint
        )
    }
}
