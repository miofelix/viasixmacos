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
        .defaultSize(width: 1_240, height: 800)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)

        Settings {
            SettingsView()
                .environment(model)
                .frame(minWidth: 700, idealWidth: 760, minHeight: 600, idealHeight: 720)
                .padding(28)
                .comfortableInterface()
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

    var id: Self { self }

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
    private static var windows: [AppDocument: NSWindow] = [:]

    static func open(_ document: AppDocument) {
        if let window = windows[document] {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = document.displayName
        window.contentViewController = NSHostingController(
            rootView: AppDocumentViewer(document: document)
        )
        window.isReleasedWhenClosed = false
        window.center()
        windows[document] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func documentURL(for document: AppDocument) -> URL? {
        let fileManager = FileManager.default
        let candidates = bundledCandidates(for: document) + developmentCandidates(for: document)
        return candidates.first(where: { fileManager.fileExists(atPath: $0.path) })
    }

    static func isTrustedDocumentURL(_ url: URL) -> Bool {
        let candidate = url.standardizedFileURL.resolvingSymlinksInPath()
        return documentRoots().contains { root in
            let trustedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
            return candidate.path == trustedRoot.path
                || candidate.path.hasPrefix(trustedRoot.path + "/")
        }
    }

    private static func documentRoots() -> [URL] {
        var roots: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            roots.append(resourceURL)
        }

        let currentDirectory = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        var directory = currentDirectory
        for _ in 0..<5 {
            let hasGuide = FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("Docs/USER_GUIDE.md").path
            )
            let hasNotices = FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("THIRD_PARTY_NOTICES.md").path
            )
            if hasGuide && hasNotices {
                roots.append(directory)
                break
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { break }
            directory = parent
        }
        return roots
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
