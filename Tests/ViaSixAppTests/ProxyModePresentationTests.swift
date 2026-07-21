import ViaSixCore
import XCTest

@testable import ViaSixApp

final class ProxyModePresentationTests: XCTestCase {
    func testRoutingModesHaveStableUserFacingPresentation() {
        XCTAssertEqual(ProxyRoutingMode.rule.displayName, "规则")
        XCTAssertEqual(ProxyRoutingMode.global.displayName, "全局")
        XCTAssertEqual(ProxyRoutingMode.direct.displayName, "直连")

        XCTAssertEqual(
            ProxyRoutingMode.rule.appDescription,
            "私有地址直连，其余流量通过代理。"
        )
        XCTAssertEqual(
            ProxyRoutingMode.global.appDescription,
            "所有经过本地代理的流量都通过代理节点。"
        )
        XCTAssertEqual(
            ProxyRoutingMode.direct.appDescription,
            "所有经过本地代理的流量都直接连接。"
        )
    }

    func testSystemProxyPresentationDistinguishesRequestedAndAppliedState() {
        let waiting = SystemProxyStatusPresentation(
            phase: .disabled,
            isRequested: true
        )
        XCTAssertEqual(waiting.text, "等待本地代理")
        XCTAssertEqual(waiting.tone, .pending)
        XCTAssertFalse(waiting.isTransitioning)

        let enabled = SystemProxyStatusPresentation(
            phase: .enabled,
            isRequested: true
        )
        XCTAssertEqual(enabled.text, "已启用")
        XCTAssertEqual(enabled.tone, .active)
        XCTAssertFalse(enabled.isTransitioning)
    }

    func testSystemProxyTransitionsAreMarkedBusy() {
        let enabling = SystemProxyStatusPresentation(
            phase: .enabling,
            isRequested: true
        )
        XCTAssertEqual(enabling.text, "正在启用")
        XCTAssertEqual(enabling.tone, .pending)
        XCTAssertTrue(enabling.isTransitioning)

        let disabling = SystemProxyStatusPresentation(
            phase: .disabling,
            isRequested: false
        )
        XCTAssertEqual(disabling.text, "正在恢复")
        XCTAssertTrue(disabling.isTransitioning)
    }

    func testSystemProxyFailureIsVisible() {
        let failed = SystemProxyStatusPresentation(
            phase: .failed("permission denied"),
            isRequested: true
        )
        XCTAssertEqual(failed.text, "操作失败")
        XCTAssertEqual(failed.tone, .error)
        XCTAssertFalse(failed.isTransitioning)
    }
}
