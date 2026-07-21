import Foundation
import ViaSixPrivilegedProtocol
import ViaSixTunHelperSupport

final class TunXPCListener: NSObject, NSXPCListenerDelegate {
    private let backend: any TunSessionBackend
    private let identityValidator: ClientIdentityValidator

    init(
        backend: any TunSessionBackend,
        authorizedClientUserIdentifier: UInt32? = nil
    ) {
        self.backend = backend
        identityValidator = ClientIdentityValidator(
            authorizedUserIdentifier: authorizedClientUserIdentifier
        )
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        guard
            let userIdentifier = identityValidator.validatedUserIdentifier(for: newConnection)
        else { return false }
        newConnection.exportedInterface = TunHelperXPCInterfaceFactory.make()
        newConnection.exportedObject = TunHelperService(
            clientUserIdentifier: userIdentifier,
            backend: backend
        )
        newConnection.activate()
        return true
    }
}
