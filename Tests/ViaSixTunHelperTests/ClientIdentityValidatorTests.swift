import XCTest

@testable import ViaSixTunHelper

final class ClientIdentityValidatorTests: XCTestCase {
    func testLocalPolicyAcceptsOnlyInstalledUser() {
        let validator = ClientIdentityValidator(authorizedUserIdentifier: 501)

        XCTAssertTrue(validator.isAuthorizedUserIdentifier(501))
        XCTAssertFalse(validator.isAuthorizedUserIdentifier(0))
        XCTAssertFalse(validator.isAuthorizedUserIdentifier(502))
    }

    func testTeamSignedPolicyAcceptsAnyNonRootUser() {
        let validator = ClientIdentityValidator()

        XCTAssertTrue(validator.isAuthorizedUserIdentifier(501))
        XCTAssertTrue(validator.isAuthorizedUserIdentifier(502))
        XCTAssertFalse(validator.isAuthorizedUserIdentifier(0))
    }
}
