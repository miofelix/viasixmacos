import SwiftUI

extension NodesView {
    // MARK: - Test and Results

    var speedTestCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("IP 测速")
                        .font(.headline)

                    Text(speedTestStatusText)
                        .font(.caption)
                        .foregroundStyle(speedTestStatusColor)
                }

                Spacer()

                if isTesting {
                    Button(role: .destructive) {
                        model.stopSpeedTest()
                    } label: {
                        Label(isStopping ? "正在停止" : "停止", systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isStopping)
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showsParameters = false
                        }
                        model.startSpeedTest()
                    } label: {
                        Label("开始测速", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(VisualStyle.accent)
                    .disabled(!canStartSpeedTest)
                }
            }

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

                HStack(spacing: 16) {
                    Text(progressLabel)
                    Text(progressPercentage)
                    Spacer()
                    Text(receivedOutputLabel)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            } else if isCfstBusyElsewhere {
                Label("完成当前节点测速后，即可开始新的候选节点扫描。", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 12) {
                    Label(sourceSummary, systemImage: "list.bullet.rectangle")
                    Divider()
                        .frame(height: 14)
                    Text(parameterSummary)
                    Spacer()
                    if !model.state.results.isEmpty {
                        Text("\(model.state.results.count) 个结果")
                            .monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let parameterValidationMessage {
                Label(parameterValidationMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let speedTestReadinessMessage {
                HStack(spacing: 8) {
                    Label(speedTestReadinessMessage, systemImage: "shippingbox")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    SettingsLink {
                        Text("打开设置")
                    }
                    .font(.caption.weight(.medium))
                }
            }
        }
        .padding(20)
        .cardStyle()
    }
}
