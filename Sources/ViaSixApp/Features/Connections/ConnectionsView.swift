import SwiftUI
import ViaSixCore

struct ConnectionsView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""
    @State private var collection: ConnectionCollection = .active
    @State private var sortOrder: ConnectionSortOrder = .recent
    @State private var selectedRecord: ConnectionRecord?
    @State private var showsCloseAllConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: VisualStyle.spacing16) {
            AppPageHeader("连接", subtitle: "查看当前会话与最近关闭的网络连接") {
                HStack(spacing: VisualStyle.spacing8) {
                    StatusBadge(
                        connectionMonitorTitle,
                        tone: connectionMonitorTone,
                        systemImage: connectionMonitorSystemImage
                    )

                    Button {
                        model.refreshMihomoRuntime()
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!model.state.isProxyRunning || model.isMihomoActionBusy)

                    Button(role: .destructive) {
                        showsCloseAllConfirmation = true
                    } label: {
                        Label("全部关闭", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(activeConnections.isEmpty || model.isMihomoActionBusy)
                }
            }

            if !model.state.isProxyRunning {
                unavailable
            } else {
                summaryStrip
                connectionList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $selectedRecord) { record in
            ConnectionDetailView(record: record) {
                model.closeConnection(record.connection.id)
                selectedRecord = nil
            }
        }
        .confirmationDialog(
            "关闭所有活动连接？",
            isPresented: $showsCloseAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("关闭 \(activeConnections.count) 个连接", role: .destructive) {
                model.closeAllConnections()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("应用可能会自动重新建立所需连接。")
        }
    }

    private var activeConnections: [MihomoConnection] {
        model.state.mihomoRuntime.snapshot?.connections ?? []
    }

    private var closedConnections: [AppState.MihomoClosedConnection] {
        model.state.mihomoRuntime.closedConnections
    }

    private var connectionMonitorTitle: String {
        switch model.state.mihomoRuntime.connectionMonitorPhase {
        case .unavailable: "未连接"
        case .connecting: "连接中"
        case .streaming: "实时"
        case .reconnecting: "重连中"
        }
    }

    private var connectionMonitorTone: AppTone {
        switch model.state.mihomoRuntime.connectionMonitorPhase {
        case .streaming: .positive
        case .connecting, .reconnecting: .warning
        case .unavailable: .neutral
        }
    }

    private var connectionMonitorSystemImage: String? {
        switch model.state.mihomoRuntime.connectionMonitorPhase {
        case .streaming: "bolt.horizontal.circle.fill"
        case .connecting, .reconnecting: "arrow.triangle.2.circlepath"
        case .unavailable: nil
        }
    }

    private var selectedRecords: [ConnectionRecord] {
        switch collection {
        case .active:
            activeConnections.map { ConnectionRecord(connection: $0, closedAt: nil) }
        case .closed:
            closedConnections.map {
                ConnectionRecord(connection: $0.connection, closedAt: $0.closedAt)
            }
        }
    }

    private var filteredRecords: [ConnectionRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = selectedRecords.filter { record in
            guard !query.isEmpty else { return true }
            let connection = record.connection
            return connection.metadata.destination.localizedCaseInsensitiveContains(query)
                || connection.metadata.destinationIP?.localizedCaseInsensitiveContains(query) == true
                || connection.metadata.applicationName?.localizedCaseInsensitiveContains(query) == true
                || connection.metadata.processPath?.localizedCaseInsensitiveContains(query) == true
                || connection.route.localizedCaseInsensitiveContains(query)
                || connection.rule?.localizedCaseInsensitiveContains(query) == true
                || connection.rulePayload?.localizedCaseInsensitiveContains(query) == true
        }
        return matches.sorted(by: sortOrder.areInIncreasingOrder)
    }

    private var unavailable: some View {
        SurfaceCard {
            ContentUnavailableView(
                "Mihomo 尚未运行",
                systemImage: "network.slash",
                description: Text("启动本地代理后，活动连接与本次运行的关闭历史会显示在这里。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var summaryStrip: some View {
        HStack(spacing: VisualStyle.spacing12) {
            RuntimeMetricCard(
                title: "活动连接",
                value: "\(activeConnections.count)",
                systemImage: "link",
                tone: .positive
            )
            RuntimeMetricCard(
                title: "上传速度",
                value: RuntimePresentation.speed(model.state.mihomoRuntime.uploadSpeed),
                systemImage: "arrow.up",
                tone: .warning
            )
            RuntimeMetricCard(
                title: "下载速度",
                value: RuntimePresentation.speed(model.state.mihomoRuntime.downloadSpeed),
                systemImage: "arrow.down",
                tone: .accent
            )
            RuntimeMetricCard(
                title: "内存占用",
                value: RuntimePresentation.byteCount(
                    model.state.mihomoRuntime.snapshot?.memoryUsage ?? 0
                ),
                systemImage: "memorychip",
                tone: .neutral
            )
        }
    }

    private var connectionList: some View {
        SurfaceCard {
            connectionToolbar

            Divider()

            if filteredRecords.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: emptySystemImage,
                    description: Text(emptyDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredRecords) { record in
                            connectionRow(record)
                            if record.id != filteredRecords.last?.id { Divider() }
                        }
                    }
                }
                .scrollbarSafeContent()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var connectionToolbar: some View {
        HStack(spacing: VisualStyle.spacing8) {
            Picker("连接状态", selection: $collection) {
                Text("活动 \(activeConnections.count)").tag(ConnectionCollection.active)
                Text("已关闭 \(closedConnections.count)").tag(ConnectionCollection.closed)
            }
            .pickerStyle(.segmented)
            .frame(width: 210)

            Picker("排序方式", selection: $sortOrder) {
                ForEach(ConnectionSortOrder.allCases) { order in
                    Label(order.title, systemImage: order.systemImage).tag(order)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: 108)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("搜索目标、应用、规则或代理链", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("\(filteredRecords.count) / \(selectedRecords.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            if collection == .closed, !closedConnections.isEmpty {
                Button(role: .destructive, action: model.clearClosedConnections) {
                    Label("清空历史", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .iconButtonHitTarget()
                .help("清空已关闭连接历史")
            }
        }
        .padding(.horizontal, VisualStyle.spacing12)
        .frame(minHeight: 44)
        .background(VisualStyle.elevatedSurfaceColor.opacity(0.4))
    }

    private func connectionRow(_ record: ConnectionRecord) -> some View {
        HStack(spacing: VisualStyle.spacing8) {
            Button {
                selectedRecord = record
            } label: {
                HStack(spacing: VisualStyle.spacing12) {
                    Image(
                        systemName: record.isClosed
                            ? "checkmark.circle"
                            : "arrow.left.arrow.right.circle"
                    )
                    .foregroundStyle(record.isClosed ? Color.secondary : VisualStyle.accent)
                    .frame(width: 30)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(record.connection.metadata.destination)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let app = record.connection.metadata.applicationName {
                                StatusBadge(app, tone: .neutral)
                            }
                            if record.isClosed {
                                StatusBadge("已关闭", tone: .neutral)
                            }
                        }
                        Text(record.connection.route)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let detail = connectionSecondaryDetail(record) {
                            Text(detail)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: VisualStyle.spacing12)

                    VStack(alignment: .trailing, spacing: 3) {
                        Text("↓ \(RuntimePresentation.byteCount(record.connection.download))")
                        Text("↑ \(RuntimePresentation.byteCount(record.connection.upload))")
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("查看连接详情")

            if !record.isClosed {
                Button(role: .destructive) {
                    model.closeConnection(record.connection.id)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .iconButtonHitTarget()
                .help("关闭连接")
                .disabled(model.isMihomoActionBusy)
            }
        }
        .padding(.horizontal, VisualStyle.spacing12)
        .padding(.vertical, 10)
    }

    private func connectionSecondaryDetail(_ record: ConnectionRecord) -> String? {
        if let closedAt = record.closedAt {
            return "关闭于 \(closedAt.formatted(date: .omitted, time: .standard))"
        }
        let values = [record.connection.rule, record.connection.rulePayload]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    private var emptyTitle: String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "没有匹配的连接"
        }
        return collection == .active ? "暂无活动连接" : "暂无已关闭连接"
    }

    private var emptySystemImage: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "network" : "magnifyingglass"
    }

    private var emptyDescription: String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "尝试清除搜索条件或切换连接状态。"
        }
        return collection == .active
            ? "新的网络会话会自动出现在这里。"
            : "本次 Mihomo 运行期间关闭的连接会保留在这里。"
    }
}

enum ConnectionCollection: Hashable {
    case active
    case closed
}

enum ConnectionSortOrder: String, CaseIterable, Identifiable {
    case recent
    case download
    case upload

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: "最近连接"
        case .download: "下载流量"
        case .upload: "上传流量"
        }
    }

    var systemImage: String {
        switch self {
        case .recent: "clock"
        case .download: "arrow.down"
        case .upload: "arrow.up"
        }
    }

    func areInIncreasingOrder(_ lhs: ConnectionRecord, _ rhs: ConnectionRecord) -> Bool {
        switch self {
        case .recent:
            let leftDate = RuntimePresentation.date(lhs.connection.start) ?? .distantPast
            let rightDate = RuntimePresentation.date(rhs.connection.start) ?? .distantPast
            if leftDate != rightDate { return leftDate > rightDate }
            return lhs.connection.id < rhs.connection.id
        case .download:
            if lhs.connection.download != rhs.connection.download {
                return lhs.connection.download > rhs.connection.download
            }
            return lhs.connection.id < rhs.connection.id
        case .upload:
            if lhs.connection.upload != rhs.connection.upload {
                return lhs.connection.upload > rhs.connection.upload
            }
            return lhs.connection.id < rhs.connection.id
        }
    }
}

struct ConnectionRecord: Identifiable, Equatable {
    let connection: MihomoConnection
    let closedAt: Date?

    var id: String { "\(connection.id)-\(isClosed ? "closed" : "active")" }
    var isClosed: Bool { closedAt != nil }
}

private struct RuntimeMetricCard: View {
    let title: String
    let value: String
    let systemImage: String
    let tone: AppTone

    var body: some View {
        HStack(spacing: VisualStyle.spacing12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tone.color)
                .frame(width: 34, height: 34)
                .background(tone.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(VisualStyle.spacing12)
        .frame(maxWidth: .infinity)
        .cardStyle()
    }
}
