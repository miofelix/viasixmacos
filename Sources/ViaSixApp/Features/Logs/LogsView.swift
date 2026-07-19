import SwiftUI

struct LogsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("测速与代理运行记录")
                        .font(.title2.weight(.bold))
                    Text("查看节点测速、本地代理与应用状态")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive, action: model.clearLogs) {
                    Label("清空", systemImage: "trash")
                }
                .disabled(model.state.logs.isEmpty)
            }

            Group {
                if model.state.logs.isEmpty {
                    ContentUnavailableView(
                        "暂无运行记录",
                        systemImage: "text.alignleft",
                        description: Text("开始节点测速或启动本地代理后，记录会显示在这里。")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(model.state.logs) { entry in
                                    LogRow(entry: entry)
                                        .id(entry.id)
                                    Divider()
                                        .opacity(0.45)
                                }
                            }
                        }
                        .onChange(of: model.state.logs.last?.id) { _, id in
                            guard let id else { return }
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                }
            }
            .padding(10)
            .cardStyle()
        }
    }
}

private struct LogRow: View {
    let entry: AppLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 18)

            Text(entry.date, format: .dateTime.hour().minute().second())
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 68, alignment: .leading)

            Text(entry.source.rawValue)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(color.opacity(0.10), in: Capsule())
                .frame(width: 58)

            Text(entry.message)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }

    private var color: Color {
        switch entry.level {
        case .info: .secondary
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }

    private var icon: String {
        switch entry.level {
        case .info: "info.circle"
        case .success: "checkmark.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.circle"
        }
    }
}
