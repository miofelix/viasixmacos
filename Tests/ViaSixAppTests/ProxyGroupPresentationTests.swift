import XCTest

@testable import ViaSixApp
@testable import ViaSixCore

final class ProxyGroupPresentationTests: XCTestCase {
    func testDelaySortingPlacesMeasurementsBeforeTimeoutErrorsAndUnknownValues() {
        let group = makeGroup(
            candidates: ["unknown", "slow", "timeout", "error", "fast"],
            delays: ["slow": 480, "timeout": 0, "error": 100_001, "fast": 32]
        )

        let result = ProxyGroupPresentation.candidates(
            in: group,
            filterText: "",
            sortMode: .delay
        )

        XCTAssertEqual(result.map(\.name), ["fast", "slow", "timeout", "error", "unknown"])
    }

    func testDefaultAndNameSortingMatchClashBehavior() {
        let group = makeGroup(candidates: ["Tokyo 2", "Hong Kong", "Tokyo 1"])

        XCTAssertEqual(
            ProxyGroupPresentation.candidates(
                in: group,
                filterText: "",
                sortMode: .defaultOrder
            ).map(\.name),
            ["Tokyo 2", "Hong Kong", "Tokyo 1"]
        )
        XCTAssertEqual(
            ProxyGroupPresentation.candidates(
                in: group,
                filterText: "",
                sortMode: .name
            ).map(\.name),
            ["Hong Kong", "Tokyo 1", "Tokyo 2"]
        )
    }

    func testFiltersByNameTypeAndDelayExpressions() {
        let group = makeGroup(
            candidates: ["HK VLESS", "JP SS", "US Timeout", "DE Error"],
            delays: ["HK VLESS": 88, "JP SS": 360, "US Timeout": 0, "DE Error": 100_000],
            types: ["HK VLESS": "VLESS", "JP SS": "Shadowsocks"]
        )

        XCTAssertEqual(filteredNames(group, "hk"), ["HK VLESS"])
        XCTAssertEqual(filteredNames(group, "type=vless"), ["HK VLESS"])
        XCTAssertEqual(filteredNames(group, "delay<250"), ["HK VLESS", "US Timeout"])
        XCTAssertEqual(filteredNames(group, "delay=timeout"), ["US Timeout"])
        XCTAssertEqual(filteredNames(group, "delay=error"), ["DE Error"])
    }

    private func filteredNames(_ group: MihomoProxyGroup, _ filter: String) -> [String] {
        ProxyGroupPresentation.candidates(
            in: group,
            filterText: filter,
            sortMode: .defaultOrder
        ).map(\.name)
    }

    private func makeGroup(
        candidates: [String],
        delays: [String: Int] = [:],
        types: [String: String] = [:]
    ) -> MihomoProxyGroup {
        MihomoProxyGroup(
            name: "GLOBAL",
            type: "Selector",
            selected: candidates.first ?? "",
            candidates: candidates,
            delays: delays,
            candidateTypes: types
        )
    }
}
