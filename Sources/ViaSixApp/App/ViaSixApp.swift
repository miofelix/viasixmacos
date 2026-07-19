import SwiftUI

@main
struct ViaSixMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("ViaSix", id: "main") {
            RootView()
        }
        .defaultSize(width: 1_180, height: 760)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)

        Settings {
            SettingsPlaceholderView()
                .frame(width: 520, height: 320)
        }
    }
}

