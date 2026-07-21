import Charts
import SwiftUI

struct RuntimeTrafficChart: View {
    let samples: [AppState.MihomoTrafficSample]

    var body: some View {
        VStack(alignment: .leading, spacing: VisualStyle.spacing8) {
            HStack(spacing: VisualStyle.spacing12) {
                chartLegend("下载", color: VisualStyle.accent)
                chartLegend("上传", color: VisualStyle.warning)
                Spacer()
                Text("最近 \(samples.count) 个采样")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if samples.count < 2 {
                Text("正在收集流量趋势…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 88)
            } else {
                Chart {
                    ForEach(samples) { sample in
                        AreaMark(
                            x: .value("时间", sample.timestamp),
                            y: .value("下载", sample.downloadSpeed)
                        )
                        .foregroundStyle(VisualStyle.accent.opacity(0.1))
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("时间", sample.timestamp),
                            y: .value("下载", sample.downloadSpeed)
                        )
                        .foregroundStyle(VisualStyle.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("时间", sample.timestamp),
                            y: .value("上传", sample.uploadSpeed)
                        )
                        .foregroundStyle(VisualStyle.warning)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: 0...chartMaximum)
                .frame(height: 88)
                .accessibilityLabel("实时流量趋势")
            }
        }
        .padding(VisualStyle.spacing12)
        .background(VisualStyle.subtleFill, in: RoundedRectangle(cornerRadius: 8))
    }

    private var chartMaximum: Int64 {
        max(
            1,
            Int64(
                Double(samples.map { max($0.uploadSpeed, $0.downloadSpeed) }.max() ?? 0)
                    * 1.15
            )
        )
    }

    private func chartLegend(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}
