import SwiftUI

struct LogsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("测速与代理运行记录")
                    .font(.title2.weight(.semibold))

                Spacer()

                Button(role: .destructive, action: model.clearLogs) {
                    Label("清空", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(model.state.logs.isEmpty)
            }

            Divider()

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

                                if entry.id != model.state.logs.last?.id {
                                    Divider()
                                        .opacity(0.45)
                                }
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
    }
}

private struct LogRow: View {
    let entry: AppLogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(entry.date, format: .dateTime.hour().minute().second())
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .leading)

            Text(entry.source.rawValue)
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
                .frame(width: 42, alignment: .leading)

            Text(entry.message)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 7)
    }

    private var color: Color {
        switch entry.level {
        case .info: .secondary
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }
}
