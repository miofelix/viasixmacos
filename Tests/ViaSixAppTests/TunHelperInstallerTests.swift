import ServiceManagement
import ViaSixPrivilegedProtocol
import XCTest

@testable import ViaSixApp

final class TunHelperInstallerTests: XCTestCase {
    func testMapsEveryKnownServiceManagementStatus() {
        XCTAssertEqual(TunHelperInstaller.map(.notRegistered), .notRegistered)
        XCTAssertEqual(TunHelperInstaller.map(.enabled), .enabled)
        XCTAssertEqual(TunHelperInstaller.map(.requiresApproval), .requiresApproval)
        XCTAssertEqual(TunHelperInstaller.map(.notFound), .notFound)
    }

    func testUsesAdministratorInstallerForAdHocIdentity() {
        let identity = CodeSigningIdentity(
            identifier: TunHelperConstants.appBundleIdentifier,
            teamIdentifier: nil,
            cdHash: String(repeating: "a", count: 40)
        )
        XCTAssertEqual(TunHelperInstaller.strategy(for: identity), .localAdministrator)
    }

    func testUsesServiceManagementForTeamSignedIdentity() {
        let identity = CodeSigningIdentity(
            identifier: TunHelperConstants.appBundleIdentifier,
            teamIdentifier: "A1B2C3D4E5",
            cdHash: String(repeating: "a", count: 40)
        )
        XCTAssertEqual(TunHelperInstaller.strategy(for: identity), .serviceManagement)
    }
}
