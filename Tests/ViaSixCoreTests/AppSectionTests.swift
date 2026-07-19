import XCTest

@testable import ViaSixCore

final class AppSectionTests: XCTestCase {
    func testAllSectionsHaveDisplayMetadata() {
        XCTAssertEqual(AppSection.allCases.count, 3)

        for section in AppSection.allCases {
            XCTAssertFalse(section.title.isEmpty)
            XCTAssertFalse(section.systemImage.isEmpty)
        }
    }

    func testProxyEndpointUsesProductDefaults() {
        XCTAssertEqual(AppMetadata.proxyHost, "127.0.0.1")
        XCTAssertEqual(AppMetadata.proxyPort, 11_451)
    }
}
