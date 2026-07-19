import AppKit
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
        .commands {
            CommandGroup(replacing: .help) {
                Button("ViaSix 使用帮助") {
                    AppDocumentOpener.open(.userGuide)
                }
                .keyboardShortcut("?", modifiers: .command)

                Button("第三方许可") {
                    AppDocumentOpener.open(.thirdPartyNotices)
                }
            }
        }
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

enum AppDocument {
    case userGuide
    case thirdPartyNotices

    var resourceName: String {
        switch self {
        case .userGuide: "USER_GUIDE"
        case .thirdPartyNotices: "THIRD_PARTY_NOTICES"
        }
    }

    var repositoryPath: String {
        switch self {
        case .userGuide: "Docs/USER_GUIDE.md"
        case .thirdPartyNotices: "THIRD_PARTY_NOTICES.md"
        }
    }

    var displayName: String {
        switch self {
        case .userGuide: "使用帮助"
        case .thirdPartyNotices: "第三方许可"
        }
    }
}

@MainActor
enum AppDocumentOpener {
    static func open(_ document: AppDocument) {
        let fileManager = FileManager.default
        let candidates = bundledCandidates(for: document) + developmentCandidates(for: document)

        if let url = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }),
           NSWorkspace.shared.open(url) {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "无法打开\(document.displayName)"
        alert.informativeText = "应用包和项目目录中都没有找到对应文档。"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private static func bundledCandidates(for document: AppDocument) -> [URL] {
        [
            Bundle.main.url(forResource: document.resourceName, withExtension: "md"),
            Bundle.main.url(
                forResource: document.resourceName,
                withExtension: "md",
                subdirectory: "Docs"
            ),
            Bundle.main.resourceURL?.appendingPathComponent("\(document.resourceName).md"),
        ].compactMap { $0 }
    }

    private static func developmentCandidates(for document: AppDocument) -> [URL] {
        let currentDirectory = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        var directories = [currentDirectory]
        var parent = currentDirectory
        for _ in 0..<4 {
            parent.deleteLastPathComponent()
            directories.append(parent)
        }

        return directories.map {
            $0.appendingPathComponent(document.repositoryPath)
        }
    }
}
