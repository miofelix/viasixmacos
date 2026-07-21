import Foundation
import ViaSixPrivilegedProtocol
import ViaSixTunHelperSupport

final class TunXPCListener: NSObject, NSXPCListenerDelegate {
    private let journalController: TunSessionJournalController
    private let identityValidator: ClientIdentityValidator

    init(
        journalController: TunSessionJournalController,
        identityValidator: ClientIdentityValidator = ClientIdentityValidator()
    ) {
        self.journalController = journalController
        self.identityValidator = identityValidator
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
            journalController: journalController
        )
        newConnection.activate()
        return true
    }
}
