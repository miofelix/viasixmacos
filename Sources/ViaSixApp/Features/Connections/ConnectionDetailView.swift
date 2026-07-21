import SwiftUI

struct ConnectionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let record: ConnectionRecord
    let closeConnection: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: VisualStyle.spacing12) {
                Image(systemName: record.isClosed ? "checkmark.circle" : "network")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(record.isClosed ? Color.secondary : VisualStyle.accent)
                    .frame(width: 42, height: 42)
                    .background(
                        (record.isClosed ? Color.secondary : VisualStyle.accent).opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 9)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(record.connection.metadata.destination)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(record.isClosed ? "已关闭连接" : "活动连接")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !record.isClosed {
                    Button("关闭连接", systemImage: "xmark.circle", role: .destructive) {
                        closeConnection()
                    }
                    .buttonStyle(.bordered)
                }

                Button("关闭", systemImage: "xmark", action: dismiss.callAsFunction)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .help("关闭详情")
            }
            .padding(VisualStyle.spacing16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: VisualStyle.spacing16) {
                    detailSection("连接", systemImage: "link") {
                        detailRow("目标", value: record.connection.metadata.destination)
                        detailRow("来源", value: sourceEndpoint)
                        detailRow("目标地址", value: destinationEndpoint)
                        detailRow("网络类型", value: networkType)
                        detailRow("DNS 模式", value: display(record.connection.metadata.dnsMode))
                    }

                    detailSection("路由", systemImage: "point.3.connected.trianglepath.dotted") {
                        detailRow("代理链", value: record.connection.route)
                        detailRow("匹配规则", value: ruleDescription)
                    }

                    detailSection("进程与时间", systemImage: "app.badge") {
                        detailRow(
                            "应用",
                            value: display(record.connection.metadata.applicationName)
                        )
                        detailRow("进程路径", value: display(record.connection.metadata.processPath))
                        detailRow(
                            "开始时间",
                            value: RuntimePresentation.connectionTimestamp(record.connection.start)
                        )
                        detailRow("持续时间", value: duration)
                        if let closedAt = record.closedAt {
                            detailRow(
                                "关闭时间",
                                value: closedAt.formatted(date: .abbreviated, time: .standard)
                            )
                        }
                    }

                    detailSection("流量", systemImage: "arrow.up.arrow.down") {
                        detailRow(
                            "已下载",
                            value: RuntimePresentation.byteCount(record.connection.download)
                        )
                        detailRow(
                            "已上传",
                            value: RuntimePresentation.byteCount(record.connection.upload)
                        )
                        detailRow("连接 ID", value: record.connection.id)
                    }
                }
                .padding(VisualStyle.spacing16)
            }
            .scrollbarSafeContent()
        }
        .frame(minWidth: 560, minHeight: 540)
        .background(VisualStyle.pageBackgroundColor)
    }

    private var sourceEndpoint: String {
        endpoint(
            address: record.connection.metadata.sourceIP,
            port: record.connection.metadata.sourcePort
        )
    }

    private var destinationEndpoint: String {
        endpoint(
            address: record.connection.metadata.destinationIP,
            port: record.connection.metadata.destinationPort
        )
    }

    private var networkType: String {
        [record.connection.metadata.type, record.connection.metadata.network]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value.uppercased()
            }
            .joined(separator: " / ")
            .ifEmpty("未知")
    }

    private var ruleDescription: String {
        [record.connection.rule, record.connection.rulePayload]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " · ")
            .ifEmpty("未匹配")
    }

    private var duration: String {
        RuntimePresentation.connectionDuration(
            start: record.connection.start,
            end: record.closedAt ?? Date()
        )
    }

    private func endpoint(address: String?, port: String?) -> String {
        guard let address, !address.isEmpty else { return "未知" }
        guard let port, !port.isEmpty else { return address }
        return address.contains(":") ? "[\(address)]:\(port)" : "\(address):\(port)"
    }

    private func display(_ value: String?) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else { return "未知" }
        return value
    }

    private func detailSection<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        SurfaceCard {
            CardHeader(title, systemImage: systemImage)
            Divider()
            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, VisualStyle.spacing16)
            .padding(.vertical, VisualStyle.spacing8)
        }
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: VisualStyle.spacing16) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 7)
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
