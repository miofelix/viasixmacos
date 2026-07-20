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
        case ready
    }

    enum ProxyConfigurationPhase: Equatable, Sendable {
        case checking
        case needsSetup(String)
        case ready
    }

    enum RuntimeOperation: Equatable, Sendable {
        case installing(RuntimeInstallationStage)
        case importing
        case cancelling

        var description: String {
            switch self {
            case .installing(.preparingInstallation):
                "正在准备安装运行组件"
            case .installing(.downloading(let component)):
                "正在下载 \(component.displayName)"
            case .installing(.verifying(let component)):
                "正在校验 \(component.displayName) 的 SHA-256"
            case .installing(.extracting(let component)):
                "正在解压 \(component.displayName)"
            case .installing(.committing):
                "正在完成安装，现有组件会保留到成功"
            case .importing:
                "正在检查并导入本地组件"
            case .cancelling:
                "正在取消，现有组件不会被修改"
            }
        }

        var canCancel: Bool {
            switch self {
            case .installing(.committing), .cancelling:
                false
            case .installing, .importing:
                true
            }
        }
    }

    enum SpeedTestPhase: Equatable, Sendable {
        case idle
        case running
        case stopping
        case failed(String)
    }

    enum ProxyCorePhase: Equatable, Sendable {
        case stopped
        case validating
        case starting
        case running
        case stopping
        case failed(String)
    }

    enum SystemProxyPhase: Equatable, Sendable {
        case disabled
        case enabling
        case enabled
        case disabling
        case failed(String)

        var isTransitioning: Bool {
            switch self {
            case .enabling, .disabling: true
            case .disabled, .enabled, .failed: false
            }
        }
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
        var isEnriching = false
        var errorMessage: String?
        var detectedAt: Date?
        var context: DetectionContext?
    }

    struct ConfigurationTestState: Equatable, Sendable {
        var phase: SpeedTestPhase = .idle
        var result: SpeedTestResult?
        var parameters: SpeedTestParameters?
        var startedAt: Date?
        var completedAt: Date?
    }

    var launchPhase: LaunchPhase = .idle
    var preferences: UserPreferences
    var results: [SpeedTestResult] = []
    var runtimePhase: RuntimePhase = .checking
    var runtimeStatus: RuntimeInstallationStatus?
    var runtimeOperation: RuntimeOperation?
    var runtimeOperationError: String?
    var proxyConfigurationPhase: ProxyConfigurationPhase = .checking
    var proxySupportsNodeSelection = false
    var speedTest = SpeedTestState()
    var configurationTest = ConfigurationTestState()
    var proxyCorePhase: ProxyCorePhase = .stopped
    /// Actual macOS proxy state, kept separate from the user's local
    /// preference (`localProxyConfiguration.networkAccessMode`).
    var systemProxyPhase: SystemProxyPhase = .disabled
    var templateOperationPhase: TemplateOperationPhase = .idle
    var templateOperationError: String?
    var proxyEndpoint = ProxyEndpoint()
    var localProxyConfiguration = LocalProxyConfiguration()
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

    var isProxyRunning: Bool {
        proxyCorePhase == .running
    }
}

extension SpeedTestResult {
    var latencyDisplayValue: String? {
        metricDisplayValue(latency, unit: "ms")
    }

    var speedDisplayValue: String? {
        metricDisplayValue(speed, unit: "MB/s")
    }

    var performanceSummary: String {
        [latencyDisplayValue, speedDisplayValue]
            .compactMap { $0 }
            .joined(separator: " · ")
            .ifEmpty("暂无有效测速指标")
    }

    private func metricDisplayValue(_ value: String, unit: String) -> String? {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedValue.isEmpty,
            let numericValue = Double(normalizedValue),
            numericValue.isFinite
        else { return nil }
        return "\(normalizedValue) \(unit)"
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}

struct AppLogEntry: Identifiable, Equatable, Sendable {
    enum Source: String, Sendable {
        case app = "应用"
        case speedTest = "测速"
        case proxy = "代理"
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

    enum Action: Equatable, Sendable {
        case openSettings
    }

    let id: UUID
    let message: String
    let style: Style
    let action: Action?

    init(
        id: UUID = UUID(),
        message: String,
        style: Style = .info,
        action: Action? = nil
    ) {
        self.id = id
        self.message = message
        self.style = style
        self.action = action
    }
}
