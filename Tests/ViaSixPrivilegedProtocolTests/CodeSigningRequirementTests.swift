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

    func testBuildsIdentifierRequirementForPersistentLocalService() throws {
        XCTAssertEqual(
            try CodeSigningRequirementBuilder.identifierRequirement(
                identifier: TunHelperConstants.appBundleIdentifier
            ),
            "identifier \"com.felix.viasix\""
        )
        XCTAssertThrowsError(
            try CodeSigningRequirementBuilder.identifierRequirement(
                identifier: "com.felix.viasix\" or true"
            )
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

    func testBuildsExactCDHashRequirementForAdHocInstallation() throws {
        let cdHash = String(repeating: "a", count: 40)
        XCTAssertEqual(
            try CodeSigningRequirementBuilder.exactCDHashRequirement(
                identifier: TunHelperConstants.appBundleIdentifier,
                cdHash: cdHash
            ),
            "identifier \"com.felix.viasix\" and cdhash H\"\(cdHash)\""
        )
    }

    func testRejectsInvalidExactCDHashRequirementComponents() {
        XCTAssertThrowsError(
            try CodeSigningRequirementBuilder.exactCDHashRequirement(
                identifier: "com.felix.viasix\" or true",
                cdHash: String(repeating: "a", count: 40)
            )
        )
        XCTAssertThrowsError(
            try CodeSigningRequirementBuilder.exactCDHashRequirement(
                identifier: TunHelperConstants.appBundleIdentifier,
                cdHash: String(repeating: "A", count: 40)
            )
        )
    }

    func testLocalInstallationPolicyRoundTripsAndValidatesIdentity() throws {
        let policy = try TunLocalInstallationPolicy(
            appIdentifier: TunHelperConstants.appBundleIdentifier,
            appCDHash: String(repeating: "a", count: 40),
            helperIdentifier: TunHelperConstants.helperBundleIdentifier,
            helperCDHash: String(repeating: "b", count: 40),
            authorizedUserIdentifier: 501
        )
        XCTAssertEqual(try TunLocalInstallationPolicy(data: policy.encodedPropertyList()), policy)
        XCTAssertThrowsError(
            try TunLocalInstallationPolicy(
                appIdentifier: "com.example.invalid",
                appCDHash: String(repeating: "a", count: 40),
                helperIdentifier: TunHelperConstants.helperBundleIdentifier,
                helperCDHash: String(repeating: "b", count: 40),
                authorizedUserIdentifier: 501
            )
        )
        XCTAssertThrowsError(
            try TunLocalInstallationPolicy(
                appIdentifier: TunHelperConstants.appBundleIdentifier,
                appCDHash: String(repeating: "a", count: 40),
                helperIdentifier: TunHelperConstants.helperBundleIdentifier,
                helperCDHash: String(repeating: "b", count: 40),
                authorizedUserIdentifier: 0
            )
        )
    }

    func testProtocolConstantsRemainStable() {
        XCTAssertEqual(TunHelperConstants.protocolVersion, 2)
        XCTAssertEqual(TunHelperConstants.implementationVersion, 5)
        XCTAssertEqual(TunHelperConstants.minimumCompatibleImplementationVersion, 5)
        XCTAssertEqual(TunLocalInstallationPolicy.currentSchemaVersion, 2)
        XCTAssertEqual(
            TunHelperConstants.launchDaemonPlistName,
            "com.felix.viasix.tun-helper.plist"
        )
        XCTAssertEqual(
            TunHelperConstants.machServiceName,
            TunHelperConstants.helperBundleIdentifier
        )
        XCTAssertEqual(
            TunHelperConstants.localInstalledAppPath,
            "/Library/Application Support/com.felix.viasix/InstalledApp/ViaSix.app"
        )
    }
}
