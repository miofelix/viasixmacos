import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    private var isTerminating = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        guard !isTerminating else { return .terminateLater }

        isTerminating = true
        Task { @MainActor [weak self] in
            await model.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
            self?.isTerminating = false
        }
        return .terminateLater
    }
}
