import Foundation
import ViaSixCore

struct AppState: Equatable, Sendable {
    enum LaunchPhase: Equatable, Sendable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    enum RuntimePhase: Equatable, Sendable {
        case checking
        case missing
        case installing
        case ready
        case failed(String)
    }

    enum SpeedTestPhase: Equatable, Sendable {
        case idle
        case running
        case stopping
        case failed(String)
    }

    enum XrayPhase: Equatable, Sendable {
        case stopped
        case validating
        case starting
        case running
        case stopping
        case failed(String)
    }

    enum TemplateOperationPhase: Equatable, Sendable {
        case idle
        case importing
        case saving
    }

    struct SpeedTestState: Equatable, Sendable {
        var phase: SpeedTestPhase = .idle
        var current = 0
        var total = 0
        var outputBytes: Int64 = 0
        var startedAt: Date?
        var lastActivityAt: Date?

        var fractionCompleted: Double {
            guard total > 0 else { return 0 }
            return min(1, Double(current) / Double(total))
        }
    }

    struct ExitState: Equatable, Sendable {
        struct DetectionContext: Equatable, Sendable {
            enum Route: Equatable, Sendable {
                case direct
                case proxy(endpoint: ProxyEndpoint, selectedIP: String)
            }

            let route: Route
            let mode: ExitIPDetectionMode
            let serviceEndpoint: String
        }

        var info: ExitIPInfo?
        var isDetecting = false
        var errorMessage: String?
        var detectedAt: Date?
        var context: DetectionContext?
    }

    struct ConfigurationTestState: Equatable, Sendable {
        var phase: SpeedTestPhase = .idle
        var result: SpeedTestResult?
        var parameters: SpeedTestParameters?
    }

    var launchPhase: LaunchPhase = .idle
    var preferences: UserPreferences
    var results: [SpeedTestResult] = []
    var runtimePhase: RuntimePhase = .checking
    var runtimeStatus: RuntimeInstallationStatus?
    var speedTest = SpeedTestState()
    var configurationTest = ConfigurationTestState()
    var xrayPhase: XrayPhase = .stopped
    var templateOperationPhase: TemplateOperationPhase = .idle
    var proxyEndpoint = ProxyEndpoint()
    var exit = ExitState()
    var logs: [AppLogEntry] = []
    var notice: AppNotice?

    var speedTestResultsAreCurrent: Bool {
        guard !results.isEmpty, let snapshot = preferences.lastSuccessfulSpeedTestParameters else {
            return false
        }
        return snapshot == preferences.parameters
    }

    var selectedResult: SpeedTestResult? {
        guard speedTestResultsAreCurrent else { return nil }
        return results.first { $0.ip == preferences.selectedIP }
    }

    var isXrayRunning: Bool {
        xrayPhase == .running
    }
}

struct AppLogEntry: Identifiable, Equatable, Sendable {
    enum Source: String, Sendable {
        case app = "应用"
        case speedTest = "测速"
        case xray = "代理"
    }

    enum Level: Sendable {
        case info
        case success
        case warning
        case error
    }

    let id: UUID
    let date: Date
    let source: Source
    let level: Level
    let message: String

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        source: Source,
        level: Level = .info,
        message: String
    ) {
        self.id = id
        self.date = date
        self.source = source
        self.level = level
        self.message = message
    }
}

struct AppNotice: Identifiable, Equatable, Sendable {
    enum Style: Sendable {
        case info
        case success
        case error
    }

    let id: UUID
    let message: String
    let style: Style

    init(id: UUID = UUID(), message: String, style: Style = .info) {
        self.id = id
        self.message = message
        self.style = style
    }
}
