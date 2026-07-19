import SwiftUI

@main
struct ViaSixMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.live()

    var body: some Scene {
        WindowGroup("ViaSix", id: "main") {
            RootView()
                .environment(model)
                .task {
                    model.start()
                }
        }
        .defaultSize(width: 1_180, height: 760)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)

        Settings {
            SettingsPlaceholderView()
                .environment(model)
                .frame(width: 520, height: 320)
        }
    }
}
