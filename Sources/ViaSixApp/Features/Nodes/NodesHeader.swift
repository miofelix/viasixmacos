import SwiftUI

extension NodesView {
    // MARK: - Header

    var pageHeader: some View {
        AppPageHeader(
            "节点测速",
            subtitle: "比较候选节点，确认后应用到本地代理"
        ) {
            HStack(spacing: VisualStyle.spacing12) {
                currentNodeSummary

                Button {
                    showsParameters = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .iconButtonHitTarget()
                .help("打开测速设置")
                .accessibilityLabel("打开测速设置")

                primarySpeedTestAction
            }
        }
    }

    private var currentNodeSummary: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("当前节点")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(currentIPLabel)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .frame(minWidth: 92, maxWidth: 180, alignment: .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("当前节点")
        .accessibilityValue(currentIPLabel)
    }

    @ViewBuilder
    private var primarySpeedTestAction: some View {
        if isTesting {
            Button(role: .destructive) {
                model.stopSpeedTest()
            } label: {
                Label(
                    isStopping ? "正在停止" : "停止测速",
                    systemImage: isStopping ? "hourglass" : "stop.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(isStopping)
            .help(isStopping ? "正在停止节点测速" : "停止节点测速")
        } else {
            Button(action: startSpeedTest) {
                Label("开始测速", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(VisualStyle.accent)
            .disabled(!canStartSpeedTest)
            .help(speedTestStartHelp)
        }
    }
}
