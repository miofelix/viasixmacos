import Foundation

/// Presentation for the candidate-node empty state. The priority order is
/// intentional: an active operation or missing capability must not fall back
/// to a generic suggestion that the user can immediately start a speed test.
struct NodeResultsEmptyPresentation: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case none
        case openSettings
        case showParameters
        case startSpeedTest
    }

    let title: String
    let description: String
    let systemImage: String
    let tone: AppTone
    let action: Action
    let actionTitle: String?
    let isBusy: Bool

    init(
        speedTestPhase: AppState.SpeedTestPhase,
        runtimeOperationDescription: String? = nil,
        isTemplateOperationBusy: Bool = false,
        isApplyingNode: Bool = false,
        isCfstBusyElsewhere: Bool = false,
        hasCfstExecutable: Bool = true,
        parameterValidationMessage: String? = nil
    ) {
        if let runtimeOperationDescription {
            title = "正在准备测速组件"
            description = runtimeOperationDescription
            systemImage = "shippingbox"
            tone = .accent
            action = .none
            actionTitle = nil
            isBusy = true
            return
        }

        if isTemplateOperationBusy {
            title = "正在处理代理配置"
            description = "代理配置处理完成后，即可开始候选节点测速。"
            systemImage = "doc.badge.gearshape"
            tone = .warning
            action = .none
            actionTitle = nil
            isBusy = true
            return
        }

        if isApplyingNode {
            title = "正在应用节点"
            description = "节点应用完成后，即可继续测速。"
            systemImage = "arrow.triangle.2.circlepath"
            tone = .warning
            action = .none
            actionTitle = nil
            isBusy = true
            return
        }

        if isCfstBusyElsewhere {
            title = "正在测试当前节点"
            description = "完成当前节点测速后，即可开始候选节点扫描。"
            systemImage = "scope"
            tone = .accent
            action = .none
            actionTitle = nil
            isBusy = true
            return
        }

        switch speedTestPhase {
        case .running:
            title = "正在生成候选节点"
            description = "测速完成后，候选节点会显示在这里。"
            systemImage = "gauge.with.dots.needle.67percent"
            tone = .accent
            action = .none
            actionTitle = nil
            isBusy = true
            return

        case .stopping:
            title = "正在停止测速"
            description = "正在安全结束当前测速任务。"
            systemImage = "hourglass"
            tone = .warning
            action = .none
            actionTitle = nil
            isBusy = true
            return

        case .idle, .failed:
            break
        }

        if !hasCfstExecutable {
            title = "需要安装测速组件"
            description = "安装 CloudflareSpeedTest 后即可扫描候选节点。"
            systemImage = "shippingbox"
            tone = .warning
            action = .openSettings
            actionTitle = "打开设置"
            isBusy = false
            return
        }

        if let parameterValidationMessage {
            title = "测速参数需要调整"
            description = parameterValidationMessage
            systemImage = "slider.horizontal.3"
            tone = .warning
            action = .showParameters
            actionTitle = "检查测速参数"
            isBusy = false
            return
        }

        switch speedTestPhase {
        case .failed(let message):
            title = "本次测速未完成"
            description =
                message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "请检查网络后重试。"
                : message
            systemImage = "exclamationmark.triangle"
            tone = .negative
            action = .startSpeedTest
            actionTitle = "重新测速"
            isBusy = false

        case .idle:
            title = "暂无测速结果"
            description = "选择地址来源并开始测速，候选节点会显示在这里。"
            systemImage = "network.slash"
            tone = .neutral
            action = .startSpeedTest
            actionTitle = "开始测速"
            isBusy = false

        case .running, .stopping:
            // Handled above so busy states always return before capability
            // and validation checks.
            preconditionFailure("Busy speed-test phases must return before readiness checks")
        }
    }
}
