import SwiftUI

struct LogsView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""
    @State private var sourceFilter: LogSourceFilter = .all
    @State private var levelFilter: LogLevelFilter = .all
    @State private var followState = LogFollowState()
    @State private var visibleScrollTarget: LogScrollTarget?
    @State private var showsClearConfirmation = false

    var body: some View {
        let visibleLogs = filteredLogs
        let visibleLogIDs = visibleLogs.map(\.id)
        let latestVisibleLogID = visibleLogIDs.last
        let filterIdentity = LogFilterIdentity(
            searchText: searchText,
            source: sourceFilter,
            level: levelFilter
        )
        let filteredSnapshot = FilteredLogSnapshot(
            filter: filterIdentity,
            ids: visibleLogIDs
        )

        VStack(alignment: .leading, spacing: VisualStyle.spacing16) {
            AppPageHeader(
                "日志",
                subtitle: "实时查看本地代理与节点测速记录"
            ) {
                HStack(spacing: VisualStyle.spacing8) {
                    Button {
                        followState.toggleExplicitFollowing(
                            latestEntryID: latestVisibleLogID,
                            visibleTarget: visibleScrollTarget
                        )
                    } label: {
                        Label(
                            followState.followsLatest ? "暂停跟随" : "跟随最新",
                            systemImage: followState.followsLatest
                                ? "pause.fill"
                                : "arrow.down.to.line"
                        )
                        .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(
                        followState.followsLatest
                            ? "暂停新日志到达时的自动滚动"
                            : "滚动到最新日志并恢复自动跟随"
                    )
                    .accessibilityLabel(
                        followState.followsLatest ? "暂停跟随" : "跟随最新"
                    )
                    .disabled(model.state.logs.isEmpty)

                    Button(role: .destructive) {
                        showsClearConfirmation = true
                    } label: {
                        Label("清空", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(model.state.logs.isEmpty)
                }
            }

            VStack(spacing: 0) {
                compactToolbar(
                    visibleCount: visibleLogs.count,
                    totalCount: model.state.logs.count
                )

                Divider()

                if model.state.logs.isEmpty {
                    ContentUnavailableView(
                        "暂无运行记录",
                        systemImage: "text.alignleft",
                        description: Text("开始节点测速或启动本地代理后，记录会显示在这里。")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if visibleLogs.isEmpty {
                    ContentUnavailableView {
                        Label("没有匹配的运行记录", systemImage: "magnifyingglass")
                    } description: {
                        Text("尝试更换关键词，或清除来源与级别筛选。")
                    } actions: {
                        Button("清除筛选", action: resetFilters)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(visibleLogs) { entry in
                                    VStack(spacing: 0) {
                                        LogRow(entry: entry)

                                        if entry.id != latestVisibleLogID {
                                            Divider()
                                                .opacity(0.45)
                                        }
                                    }
                                    .id(LogScrollTarget.entry(entry.id))
                                }

                                if let latestVisibleLogID {
                                    Color.clear
                                        .frame(height: 1)
                                        .id(LogScrollTarget.bottom(latestVisibleLogID))
                                        .accessibilityHidden(true)
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollPosition(id: $visibleScrollTarget, anchor: .bottom)
                        .scrollbarSafeContent()
                        .overlay(alignment: .bottomTrailing) {
                            if !followState.followsLatest {
                                Button {
                                    followState.resumeFollowing(
                                        target: latestVisibleLogID,
                                        visibleTarget: visibleScrollTarget
                                    )
                                } label: {
                                    Label(
                                        followState.pendingNewRecordCount > 0
                                            ? "有 \(followState.pendingNewRecordCount) 条新记录"
                                            : "回到最新",
                                        systemImage: "arrow.down.to.line"
                                    )
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .help("滚动到最新日志并恢复自动跟随")
                                .padding(.trailing, VisualStyle.scrollbarClearance + 8)
                                .padding(.bottom, 10)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                        .onAppear {
                            let shouldScroll = followState.beginMaintainingLatest(
                                target: latestVisibleLogID,
                                visibleTarget: visibleScrollTarget
                            )
                            guard shouldScroll else { return }
                            scrollToLatest(using: proxy, latestEntryID: latestVisibleLogID)
                        }
                        .onChange(of: filteredSnapshot) { _, current in
                            let shouldMaintainLatest = followState.beginMaintainingLatest(
                                target: current.ids.last,
                                visibleTarget: visibleScrollTarget
                            )
                            guard shouldMaintainLatest else { return }
                            scrollToLatest(using: proxy, latestEntryID: current.ids.last)
                        }
                        .onChange(of: visibleScrollTarget) { _, target in
                            followState.observeVisibleTarget(
                                target,
                                latestEntryID: latestVisibleLogID
                            )
                        }
                        .onChange(of: followState.followsLatest) { _, isFollowing in
                            guard isFollowing else { return }
                            scrollToLatest(using: proxy, latestEntryID: latestVisibleLogID)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: VisualStyle.radiusMedium,
                    style: .continuous
                )
            )
            .cardStyle()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: filteredSnapshot) { previous, current in
            if previous.filter == current.filter {
                followState.observeMatchingLogIDs(
                    previous: previous.ids,
                    current: current.ids
                )
            } else {
                followState.rebaselineMatchingRecords()
            }
        }
        .onChange(of: logIDs) { _, currentIDs in
            guard currentIDs.isEmpty else { return }
            followState.resetAfterClearingLogs()
        }
        .confirmationDialog(
            "清空所有运行记录？",
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空 \(model.state.logs.count) 条记录", role: .destructive) {
                model.clearLogs()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作无法撤销，但不会删除测速结果或应用设置。")
        }
    }

    private var filteredLogs: [AppLogEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.state.logs.filter { entry in
            guard sourceFilter.includes(entry.source), levelFilter.includes(entry.level) else {
                return false
            }
            guard !query.isEmpty else { return true }
            return entry.message.localizedCaseInsensitiveContains(query)
                || entry.source.rawValue.localizedCaseInsensitiveContains(query)
                || LogLevelFilter.title(for: entry.level).localizedCaseInsensitiveContains(query)
        }
    }

    private var logIDs: [AppLogEntry.ID] {
        model.state.logs.map(\.id)
    }

    private var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || sourceFilter != .all
            || levelFilter != .all
    }

    private func compactToolbar(visibleCount: Int, totalCount: Int) -> some View {
        HStack(spacing: VisualStyle.spacing8) {
            filterMenu

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                TextField("搜索运行记录", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("清除搜索")
                    .accessibilityLabel("清除搜索")
                }
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(
                VisualStyle.subtleFill,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(VisualStyle.surfaceBorder, lineWidth: 1)
            }

            HStack(spacing: 5) {
                Circle()
                    .fill(followState.followsLatest ? VisualStyle.positive : VisualStyle.warning)
                    .frame(width: 6, height: 6)

                Text(followState.followsLatest ? "实时" : "已暂停")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize()
            .accessibilityElement(children: .combine)
            .accessibilityLabel(followState.followsLatest ? "正在实时跟随" : "日志跟随已暂停")

            Text(isFiltering ? "\(visibleCount) / \(totalCount) 条" : "\(totalCount) 条")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .padding(.horizontal, VisualStyle.spacing12)
        .padding(.vertical, 9)
        .background(VisualStyle.elevatedSurfaceColor.opacity(0.45))
    }

    private var filterMenu: some View {
        Menu {
            Picker("来源", selection: $sourceFilter) {
                ForEach(LogSourceFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }

            Picker("级别", selection: $levelFilter) {
                ForEach(LogLevelFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }

            if sourceFilter != .all || levelFilter != .all {
                Divider()
                Button("清除来源与级别筛选") {
                    sourceFilter = .all
                    levelFilter = .all
                }
            }
        } label: {
            Label(
                filterMenuTitle,
                systemImage: sourceFilter == .all && levelFilter == .all
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill"
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.state.logs.isEmpty)
    }

    private var filterMenuTitle: String {
        switch (sourceFilter, levelFilter) {
        case (.all, .all):
            "筛选"
        case (.all, let level):
            level.title
        case (let source, .all):
            source.title
        case (let source, let level):
            "\(source.title) · \(level.title)"
        }
    }

    private func resetFilters() {
        searchText = ""
        sourceFilter = .all
        levelFilter = .all
    }

    private func scrollToLatest(
        using proxy: ScrollViewProxy,
        latestEntryID: AppLogEntry.ID?
    ) {
        guard followState.followsLatest, let latestEntryID else { return }
        proxy.scrollTo(LogScrollTarget.bottom(latestEntryID), anchor: .bottom)
    }
}

enum LogScrollTarget: Hashable {
    case entry(AppLogEntry.ID)
    case bottom(AppLogEntry.ID)

    func isBottom(for id: AppLogEntry.ID) -> Bool {
        self == .bottom(id)
    }
}

enum LogFollowMode: Equatable {
    case following
    case pausedByScroll
    case pausedExplicitly
}

struct LogFollowState {
    private(set) var mode = LogFollowMode.following
    private(set) var pendingNewRecordCount = 0
    private(set) var expectedAutomaticTargetID: AppLogEntry.ID?

    var followsLatest: Bool {
        mode == .following
    }

    mutating func toggleExplicitFollowing(
        latestEntryID: AppLogEntry.ID?,
        visibleTarget: LogScrollTarget? = nil
    ) {
        switch mode {
        case .following:
            mode = .pausedExplicitly
            expectedAutomaticTargetID = nil
        case .pausedByScroll, .pausedExplicitly:
            resumeFollowing(target: latestEntryID, visibleTarget: visibleTarget)
        }
    }

    mutating func resumeFollowing(
        target: AppLogEntry.ID?,
        visibleTarget: LogScrollTarget? = nil
    ) {
        mode = .following
        pendingNewRecordCount = 0
        expectedAutomaticTargetID = pendingTarget(target, visibleTarget: visibleTarget)
    }

    mutating func observeMatchingLogIDs(
        previous: [AppLogEntry.ID],
        current: [AppLogEntry.ID]
    ) {
        guard !followsLatest else { return }

        let previousIDs = Set(previous)
        pendingNewRecordCount += current.lazy.filter { !previousIDs.contains($0) }.count
    }

    mutating func rebaselineMatchingRecords() {
        pendingNewRecordCount = 0
    }

    mutating func resetAfterClearingLogs() {
        mode = .following
        pendingNewRecordCount = 0
        expectedAutomaticTargetID = nil
    }

    mutating func beginMaintainingLatest(
        target: AppLogEntry.ID?,
        visibleTarget: LogScrollTarget? = nil
    ) -> Bool {
        guard followsLatest, let target else {
            expectedAutomaticTargetID = nil
            return false
        }
        guard !visibleTarget.isBottom(for: target) else {
            expectedAutomaticTargetID = nil
            return false
        }
        expectedAutomaticTargetID = target
        return true
    }

    mutating func observeVisibleTarget(
        _ target: LogScrollTarget?,
        latestEntryID: AppLogEntry.ID?
    ) {
        guard let target, let latestEntryID else { return }

        if let expectedAutomaticTargetID {
            if target.isBottom(for: expectedAutomaticTargetID) {
                self.expectedAutomaticTargetID = nil
            }
            return
        }

        switch mode {
        case .following:
            if !target.isBottom(for: latestEntryID) {
                mode = .pausedByScroll
            }
        case .pausedByScroll:
            if target.isBottom(for: latestEntryID) {
                mode = .following
                pendingNewRecordCount = 0
            }
        case .pausedExplicitly:
            break
        }
    }

    private func pendingTarget(
        _ target: AppLogEntry.ID?,
        visibleTarget: LogScrollTarget?
    ) -> AppLogEntry.ID? {
        guard let target, !visibleTarget.isBottom(for: target) else { return nil }
        return target
    }
}

private extension Optional where Wrapped == LogScrollTarget {
    func isBottom(for id: AppLogEntry.ID) -> Bool {
        self?.isBottom(for: id) == true
    }
}

private struct LogFilterIdentity: Equatable {
    let searchText: String
    let source: LogSourceFilter
    let level: LogLevelFilter
}

private struct FilteredLogSnapshot: Equatable {
    let filter: LogFilterIdentity
    let ids: [AppLogEntry.ID]
}

private enum LogSourceFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case app
    case speedTest
    case proxy

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "全部来源"
        case .app: "应用"
        case .speedTest: "测速"
        case .proxy: "代理"
        }
    }

    func includes(_ source: AppLogEntry.Source) -> Bool {
        switch (self, source) {
        case (.all, _), (.app, .app), (.speedTest, .speedTest), (.proxy, .proxy):
            true
        default:
            false
        }
    }
}

private enum LogLevelFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case info
    case success
    case warning
    case error

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "全部级别"
        case .info: "信息"
        case .success: "成功"
        case .warning: "警告"
        case .error: "错误"
        }
    }

    func includes(_ level: AppLogEntry.Level) -> Bool {
        switch (self, level) {
        case (.all, _), (.info, .info), (.success, .success), (.warning, .warning),
            (.error, .error):
            true
        default:
            false
        }
    }

    static func title(for level: AppLogEntry.Level) -> String {
        switch level {
        case .info: "信息"
        case .success: "成功"
        case .warning: "警告"
        case .error: "错误"
        }
    }
}

private struct LogRow: View {
    let entry: AppLogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(entry.date, format: .dateTime.hour().minute().second())
                .font(.system(size: 11, design: .monospaced).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 68, alignment: .leading)

            CompactLogBadge(
                title: entry.source.rawValue,
                color: sourceColor
            )
            .frame(width: 43)

            CompactLogBadge(title: levelTitle, color: levelColor)
                .frame(width: 43)

            Text(entry.message)
                .font(.system(size: 12, design: .monospaced))
                .lineSpacing(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(minHeight: 34)
    }

    private var sourceColor: Color {
        switch entry.source {
        case .app: .secondary
        case .speedTest: .purple
        case .proxy: VisualStyle.accent
        }
    }

    private var levelColor: Color {
        switch entry.level {
        case .info: VisualStyle.accent
        case .success: VisualStyle.positive
        case .warning: VisualStyle.warning
        case .error: VisualStyle.negative
        }
    }

    private var levelTitle: String {
        switch entry.level {
        case .info: "信息"
        case .success: "成功"
        case .warning: "警告"
        case .error: "错误"
        }
    }
}

private struct CompactLogBadge: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .frame(minHeight: 18)
            .background(
                color.opacity(0.1),
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(color.opacity(0.18), lineWidth: 0.5)
            }
            .accessibilityElement(children: .combine)
    }
}
