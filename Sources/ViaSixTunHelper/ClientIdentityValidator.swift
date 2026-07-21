import Foundation

struct ClientIdentityValidator {
    let authorizedUserIdentifier: UInt32?

    init(authorizedUserIdentifier: UInt32? = nil) {
        self.authorizedUserIdentifier = authorizedUserIdentifier
    }

    func validatedUserIdentifier(for connection: NSXPCConnection) -> UInt32? {
        // The listener's code-signing requirement is the primary identity
        // boundary. These checks reject invalid/system contexts before an
        // exported object is attached and avoid treating PID alone as identity.
        guard
            connection.processIdentifier > 1,
            isAuthorizedUserIdentifier(connection.effectiveUserIdentifier),
            connection.auditSessionIdentifier > 0
        else { return nil }
        return connection.effectiveUserIdentifier
    }

    func isAuthorizedUserIdentifier(_ userIdentifier: UInt32) -> Bool {
        guard userIdentifier > 0 else { return false }
        return authorizedUserIdentifier == nil
            || authorizedUserIdentifier == userIdentifier
    }
}
