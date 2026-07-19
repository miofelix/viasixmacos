import SwiftUI
import ViaSixCore

@main
struct ViaSixMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel

    init() {
        let model = AppModel.live()
        _model = State(initialValue: model)
        appDelegate.model = model
    }

    var body: some Scene {
        Window("ViaSix", id: "main") {
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
            SettingsView()
                .environment(model)
                .frame(minWidth: 620, idealWidth: 680, minHeight: 520, idealHeight: 640)
                .padding(22)
                .task {
                    model.start()
                }
        }

        MenuBarExtra {
            MenuBarView()
                .environment(model)
                .task {
                    model.start()
                }
        } label: {
            Label(AppMetadata.name, systemImage: menuBarIcon)
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarIcon: String {
        switch model.state.xrayPhase {
        case .running:
            "network.badge.shield.half.filled"
        case .validating, .starting, .stopping, .stopped:
            "network"
        case .failed:
            "network.slash"
        }
    }
}
