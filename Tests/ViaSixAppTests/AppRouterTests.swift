import ViaSixCore
import XCTest

@testable import ViaSixApp

@MainActor
final class AppRouterTests: XCTestCase {
    func testRouterStartsAtOverviewAndSelectsRequestedSection() {
        let router = AppRouter()

        XCTAssertEqual(router.selectedSection, .overview)

        router.select(.nodes)
        XCTAssertEqual(router.selectedSection, .nodes)

        router.select(.settings)
        XCTAssertEqual(router.selectedSection, .settings)
    }
}
