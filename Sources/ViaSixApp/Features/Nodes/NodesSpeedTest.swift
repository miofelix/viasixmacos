import SwiftUI

extension NodesView {
    // MARK: - Test and Results

    var speedTestCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.title3)
                    .foregroundStyle(VisualStyle.secondaryAccent)
                    .frame(width: 40, height: 40)
                    .background(
                        VisualStyle.secondaryAccent.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 12)
                    )

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
                        model.startSpeedTest()
                    } label: {
                        Label("开始测速", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(VisualStyle.accent)
                    .disabled(
                        model.state.launchPhase != .ready
                            || model.state.runtimePhase == .installing
                    )
                }
            }

            Group {
                if isTesting && model.state.speedTest.total == 0 {
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
                Label(progressLabel, systemImage: "number")
                Label(progressPercentage, systemImage: "percent")
                Spacer()
                Label(receivedOutputLabel, systemImage: "arrow.down.circle")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .cardStyle()
    }
}
