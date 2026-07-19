import SwiftUI
import ViaSixCore

extension NodesView {
    var topResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("最快节点")
                        .font(.headline)
                    Text("按结果顺序展示前三名，点击即可切换")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            LazyVGrid(columns: resultColumns, alignment: .leading, spacing: 12) {
                ForEach(Array(model.state.results.prefix(3).enumerated()), id: \.element.id) { index, result in
                    TopResultCard(
                        rank: index + 1,
                        result: result,
                        isSelected: result.ip == model.state.preferences.selectedIP,
                        isSwitching: switchingIP == result.ip
                    ) {
                        selectIP(result.ip)
                    }
                }
            }
            .disabled(nodeSelectionDisabled)
        }
    }

    var resultsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("候选节点")
                        .font(.headline)
                    Text("点击任意一行切换节点，完整测速数据可滚动查看")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(model.state.results.count) 条")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)

                if switchingIP != nil {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在切换节点")
                }
            }

            ZStack {
                Table(model.state.results, selection: selectedResultBinding) {
                    TableColumn("IP") { result in
                        HStack(spacing: 7) {
                            if result.ip == model.state.preferences.selectedIP {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(VisualStyle.accent)
                            }

                            Text(result.ip)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .width(min: 150, ideal: 220)

                    TableColumn("已发") { result in
                        Text(metric(result.sent))
                            .monospacedDigit()
                    }
                    .width(min: 42, ideal: 52)

                    TableColumn("已收") { result in
                        Text(metric(result.received))
                            .monospacedDigit()
                    }
                    .width(min: 42, ideal: 52)

                    TableColumn("丢包") { result in
                        Text(metric(result.loss))
                            .monospacedDigit()
                    }
                    .width(min: 54, ideal: 66)

                    TableColumn("延迟 (ms)") { result in
                        Text(metric(result.latency))
                            .monospacedDigit()
                    }
                    .width(min: 68, ideal: 82)

                    TableColumn("速度 (MB/s)") { result in
                        Text(metric(result.speed))
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                    .width(min: 78, ideal: 94)

                    TableColumn("节点地区") { result in
                        Text(metric(result.region))
                    }
                    .width(min: 54, ideal: 72)
                }
                .frame(height: resultsTableHeight)
                .disabled(nodeSelectionDisabled)
                .accessibilityLabel("候选节点")

                if model.state.results.isEmpty {
                    ContentUnavailableView(
                        "暂无测速结果",
                        systemImage: "network.slash",
                        description: Text("配置参数后点击“开始测速”生成候选节点。")
                    )
                    .allowsHitTesting(false)
                }
            }
        }
        .padding(18)
        .cardStyle()
    }
}
