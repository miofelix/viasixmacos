import SwiftUI
import ViaSixCore

extension NodesView {
    var resultsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            resultsHeader

            ZStack {
                Table(
                    sortedResults,
                    selection: $candidateSelection,
                    sortOrder: $resultSortOrder
                ) {
                    TableColumn("IP", sortUsing: NodeResultSortComparator(.ip)) { result in
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

                    TableColumn("已发", sortUsing: NodeResultSortComparator(.sent)) { result in
                        Text(metric(result.sent))
                            .monospacedDigit()
                    }
                    .width(min: 42, ideal: 52)

                    TableColumn("已收", sortUsing: NodeResultSortComparator(.received)) { result in
                        Text(metric(result.received))
                            .monospacedDigit()
                    }
                    .width(min: 42, ideal: 52)

                    TableColumn("丢包", sortUsing: NodeResultSortComparator(.loss)) { result in
                        Text(metric(result.loss))
                            .monospacedDigit()
                    }
                    .width(min: 54, ideal: 66)

                    TableColumn("延迟 (ms)", sortUsing: NodeResultSortComparator(.latency)) { result in
                        Text(metric(result.latency))
                            .monospacedDigit()
                    }
                    .width(min: 68, ideal: 82)

                    TableColumn("速度 (MB/s)", sortUsing: NodeResultSortComparator(.speed)) { result in
                        Text(metric(result.speed))
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                    .width(min: 78, ideal: 94)

                    TableColumn("节点地区", sortUsing: NodeResultSortComparator(.region)) { result in
                        Text(metric(result.region))
                            .padding(.trailing, VisualStyle.scrollbarClearance)
                    }
                    .width(min: 76, ideal: 94)
                }
                .frame(height: resultsTableHeight)
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
        .padding(22)
        .cardStyle()
    }

    private var sortedResults: [SpeedTestResult] {
        NodeResultSorting.sorted(model.state.results, using: resultSortOrder)
    }

    private var resultsHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                resultsHeading
                Spacer(minLength: 10)
                resultsCount
                resultsActions
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    resultsHeading
                    Spacer(minLength: 10)
                    resultsCount
                }

                HStack(spacing: 9) {
                    Spacer(minLength: 0)
                    resultsActions
                }
            }
        }
    }

    private var resultsHeading: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("候选节点")
                .font(.headline)
            Text(resultsSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var resultsCount: some View {
        Text("\(model.state.results.count) 条")
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var resultsActions: some View {
        Button(action: copyCandidateIP) {
            Image(
                systemName: candidateSelection != nil
                    && copiedCandidateIP == candidateSelection
                    ? "checkmark"
                    : "doc.on.doc"
            )
        }
        .buttonStyle(.borderless)
        .iconButtonHitTarget()
        .help(
            candidateSelection != nil && copiedCandidateIP == candidateSelection
                ? "已复制"
                : "复制所选 IP"
        )
        .accessibilityLabel(
            candidateSelection != nil && copiedCandidateIP == candidateSelection
                ? "已复制所选 IP"
                : "复制所选 IP"
        )
        .disabled(candidateSelection == nil)

        if model.switchingIP != nil {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("正在切换节点")
        }

        Button(action: requestCandidateApplication) {
            Label(applyButtonTitle, systemImage: "checkmark.circle")
        }
        .buttonStyle(.bordered)
        .tint(VisualStyle.accent)
        .disabled(applySelectionDisabled)
    }
}
