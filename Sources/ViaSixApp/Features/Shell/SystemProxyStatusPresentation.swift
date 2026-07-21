import SwiftUI

/// Presentation of the operating-system proxy state. The requested setting
/// and the applied macOS state are deliberately separate: a request can be
/// saved while the local proxy is stopped, and an operation can fail after the
/// request was accepted.
struct SystemProxyStatusPresentation: Equatable {
    enum Tone: Equatable {
        case neutral
        case pending
        case active
        case error

        var color: Color {
            appTone.color
        }

        var appTone: AppTone {
            switch self {
            case .neutral: .neutral
            case .pending: .warning
            case .active: .positive
            case .error: .negative
            }
        }
    }

    let text: String
    let tone: Tone
    let isTransitioning: Bool

    var appTone: AppTone {
        tone.appTone
    }

    init(phase: AppState.SystemProxyPhase, isRequested: Bool) {
        switch phase {
        case .disabled:
            text = isRequested ? "等待本地代理" : "未启用"
            tone = isRequested ? .pending : .neutral
            isTransitioning = false
        case .enabling:
            text = "正在启用"
            tone = .pending
            isTransitioning = true
        case .enabled:
            text = "已启用"
            tone = .active
            isTransitioning = false
        case .disabling:
            text = "正在恢复"
            tone = .pending
            isTransitioning = true
        case .failed:
            text = "操作失败"
            tone = .error
            isTransitioning = false
        }
    }
}
