import Charts
import SwiftUI
import ViaSixCore

struct TrafficStatsView: View {
    let snapshot: TrafficSnapshot
    let isProxyRunning: Bool

    var body: some View {
        SurfaceCard {
            CardHeader("流量统计", systemImage: "chart.xyaxis.line", tone: headerTone) {
                if isProxyRunning {
                    StatusBadge(
                        snapshot.isLive ? "实时" : "连接中",
                        tone: snapshot.isLive ? .positive : .warning,
                        systemImage: snapshot.isLive ? "antenna.radiowaves.left.and.right" : "hourglass"
                    )
                } else {
                    StatusBadge("未连接", tone: .neutral, systemImage: "circle")
                }
            }
            Divider()

            VStack(alignment: .leading, spacing: VisualStyle.spacing12) {
                trafficGraph
                    .frame(height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: VisualStyle.radiusMedium, style: .continuous))
                    .background(
                        RoundedRectangle(cornerRadius: VisualStyle.radiusMedium, style: .continuous)
                            .fill(VisualStyle.subtleFill)
                    )

                HStack(spacing: VisualStyle.spacing12) {
                    metricTile(
                        title: "上传",
                        value: ByteRateFormatter.formatRate(snapshot.up),
                        systemImage: "arrow.up.circle.fill",
                        tone: .accent
                    )
                    metricTile(
                        title: "下载",
                        value: ByteRateFormatter.formatRate(snapshot.down),
                        systemImage: "arrow.down.circle.fill",
                        tone: .positive
                    )
                    metricTile(
                        title: "内存",
                        value: ByteRateFormatter.formatBytes(snapshot.memoryInUse),
                        systemImage: "memorychip",
                        tone: .warning
                    )
                }

                if !isProxyRunning {
                    Text("启动连接后显示实时上下行速率、流量曲线与 Mihomo 内存占用。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(VisualStyle.spacing16)
        }
    }

    private var headerTone: AppTone {
        if !isProxyRunning { return .neutral }
        return snapshot.isLive ? .positive : .accent
    }

    @ViewBuilder
    private var trafficGraph: some View {
        let points = displayPoints
        if points.isEmpty {
            ZStack {
                TrafficGraphGrid()
                Text(isProxyRunning ? "等待流量数据…" : "暂无流量数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Chart {
                ForEach(points) { point in
                    AreaMark(
                        x: .value("时间", point.date),
                        y: .value("速率", point.down)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [VisualStyle.positive.opacity(0.28), VisualStyle.positive.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("时间", point.date),
                        y: .value("下载", point.down)
                    )
                    .foregroundStyle(VisualStyle.positive)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("时间", point.date),
                        y: .value("上传", point.up)
                    )
                    .foregroundStyle(VisualStyle.accent)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(Color.secondary.opacity(0.25))
                    AxisValueLabel {
                        if let rate = value.as(Double.self) {
                            Text(axisRateLabel(rate))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .padding(.horizontal, VisualStyle.spacing8)
            .padding(.vertical, VisualStyle.spacing8)
        }
    }

    private var displayPoints: [TrafficGraphPoint] {
        snapshot.points.map {
            TrafficGraphPoint(
                id: $0.timestamp.timeIntervalSinceReferenceDate,
                date: $0.timestamp,
                up: Double($0.up),
                down: Double($0.down)
            )
        }
    }

    private func metricTile(
        title: String,
        value: String,
        systemImage: String,
        tone: AppTone
    ) -> some View {
        HStack(spacing: VisualStyle.spacing8) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tone.color)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, VisualStyle.spacing12)
        .padding(.vertical, VisualStyle.spacing8)
        .background(
            RoundedRectangle(cornerRadius: VisualStyle.radiusMedium, style: .continuous)
                .fill(tone.color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: VisualStyle.radiusMedium, style: .continuous)
                .strokeBorder(tone.color.opacity(0.14), lineWidth: 1)
        )
        .frame(maxWidth: .infinity)
    }

    private func axisRateLabel(_ rate: Double) -> String {
        let clamped = max(0, rate)
        if clamped < 1_024 {
            return "\(Int(clamped)) B"
        }
        return ByteRateFormatter.formatCompactRate(UInt64(clamped)).replacingOccurrences(of: "/s", with: "")
    }
}

private struct TrafficGraphPoint: Identifiable {
    let id: TimeInterval
    let date: Date
    let up: Double
    let down: Double
}

private struct TrafficGraphGrid: View {
    var body: some View {
        Canvas { context, size in
            let rows = 3
            let columns = 6
            var path = Path()
            for row in 0...rows {
                let y = size.height * CGFloat(row) / CGFloat(rows)
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            for column in 0...columns {
                let x = size.width * CGFloat(column) / CGFloat(columns)
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            context.stroke(
                path,
                with: .color(Color.secondary.opacity(0.18)),
                style: StrokeStyle(lineWidth: 0.5, dash: [3, 3])
            )
        }
    }
}
