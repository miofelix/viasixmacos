import SwiftUI

extension NodesView {
    // MARK: - Speed-test status

    var speedTestCard: some View {
        VStack(alignment: .leading, spacing: VisualStyle.spacing12) {
            speedTestStatusHeader

            if isTesting {
                Group {
                    if model.state.speedTest.total == 0 {
                        ProgressView()
                            .progressViewStyle(.linear)
                    } else {
                        ProgressView(value: model.state.speedTest.fractionCompleted)
                            .progressViewStyle(.linear)
                            .tint(VisualStyle.accent)
                    }
                }
                .accessibilityLabel("测速进度")
                .accessibilityValue(progressAccessibilityValue)

                progressSummary
            } else if isCfstBusyElsewhere {
                Label(
                    "完成当前节点测速后，即可开始新的候选节点扫描。",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                idleSummary
            }

            if let parameterValidationMessage {
                Label(parameterValidationMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(VisualStyle.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if speedTestReadinessMessage != nil {
                readinessSummary
            }
        }
        .padding(VisualStyle.spacing16)
        .cardStyle()
    }

    private var speedTestStatusHeader: some View {
        HStack(alignment: .center, spacing: VisualStyle.spacing12) {
            Image(systemName: speedTestStatusSystemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(speedTestStatusTone.color)
                .frame(width: 32, height: 32)
                .background(
                    speedTestStatusTone.color.opacity(0.1),
                    in: RoundedRectangle(
                        cornerRadius: VisualStyle.radiusSmall,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("测速状态")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(speedTestStatusText)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(speedTestStatusTone.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: VisualStyle.spacing12)

            if isTesting {
                StatusBadge(
                    isStopping ? "停止中" : "测速中",
                    tone: isStopping ? .warning : .accent,
                    systemImage: isStopping ? "hourglass" : "waveform.path.ecg"
                )
            } else if !model.state.results.isEmpty {
                StatusBadge(
                    model.state.speedTestResultsAreCurrent ? "结果可用" : "结果已过期",
                    tone: model.state.speedTestResultsAreCurrent ? .positive : .warning
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("测速状态")
        .accessibilityValue(speedTestStatusText)
    }

    private var progressSummary: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                Text(progressLabel)
                Text(progressPercentage)
                Spacer(minLength: 0)
                Text(receivedOutputLabel)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 16) {
                    Text(progressLabel)
                    Text(progressPercentage)
                }
                Text(receivedOutputLabel)
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private var idleSummary: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: VisualStyle.spacing12) {
                idleSummarySource
                Divider()
                    .frame(height: 14)
                idleSummaryParameters
                Spacer(minLength: 0)
                idleSummaryCount
            }

            VStack(alignment: .leading, spacing: 5) {
                idleSummarySource
                idleSummaryParameters
                idleSummaryCount
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var idleSummarySource: some View {
        Label(sourceSummary, systemImage: "list.bullet.rectangle")
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var idleSummaryParameters: some View {
        Text(parameterSummary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var idleSummaryCount: some View {
        if !model.state.results.isEmpty {
            Text("\(model.state.results.count) 个结果")
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var readinessSummary: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                readinessLabel
                Spacer(minLength: 8)
                settingsLink
            }

            VStack(alignment: .leading, spacing: 6) {
                readinessLabel
                settingsLink
            }
        }
    }

    private var readinessLabel: some View {
        Label(speedTestReadinessMessage ?? "", systemImage: "shippingbox")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var settingsLink: some View {
        SettingsLink {
            Text("打开设置")
        }
        .font(.caption.weight(.medium))
    }
}
