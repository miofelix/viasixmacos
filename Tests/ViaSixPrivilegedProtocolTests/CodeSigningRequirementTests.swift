import XCTest

@testable import ViaSixPrivilegedProtocol

final class CodeSigningRequirementTests: XCTestCase {
    func testBuildsSameTeamRequirementFromValidatedComponents() throws {
        XCTAssertEqual(
            try CodeSigningRequirementBuilder.sameTeamRequirement(
                identifier: "com.felix.viasix",
                teamIdentifier: "A1B2C3D4E5"
            ),
            "anchor apple generic and identifier \"com.felix.viasix\" "
                + "and certificate leaf[subject.OU] = \"A1B2C3D4E5\""
        )
    }

    func testRejectsRequirementInjectionAndInvalidTeamIdentifiers() {
        XCTAssertThrowsError(
            try CodeSigningRequirementBuilder.sameTeamRequirement(
                identifier: "com.felix.viasix\" or true",
                teamIdentifier: "A1B2C3D4E5"
            )
        )
        XCTAssertThrowsError(
            try CodeSigningRequirementBuilder.sameTeamRequirement(
                identifier: "com.felix.viasix",
                teamIdentifier: "a1b2 c3"
            )
        )
    }

    func testProtocolConstantsRemainStable() {
        XCTAssertEqual(TunHelperConstants.protocolVersion, 2)
        XCTAssertEqual(
            TunHelperConstants.launchDaemonPlistName,
            "com.felix.viasix.tun-helper.plist"
        )
        XCTAssertEqual(
            TunHelperConstants.machServiceName,
            TunHelperConstants.helperBundleIdentifier
        )
    }
}
