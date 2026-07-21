import SwiftUI
import ViaSixCore

struct ProxiesView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""
    @State private var showsProviders = false
    @State private var optimisticRoutingMode: ProxyRoutingMode?
    @State private var groupStates: [String: ProxyGroupViewState] = [:]

    var body: some View {
        VStack(spacing: 0) {
            AppPageHeader("代理", subtitle: "管理代理组与路由模式") {
                headerActions
            }

            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: VisualStyle.spacing12) {
                        searchField

                        if !model.state.isProxyRunning {
                            unavailableCard
                        } else if let snapshot = model.state.mihomoRuntime.snapshot {
                            if filteredGroups(in: snapshot).isEmpty {
                                ContentUnavailableView(
                                    "没有匹配的代理组",
                                    systemImage: "magnifyingglass",
                                    description: Text("尝试清除搜索条件，或检查当前配置是否包含 proxy-groups。")
                                )
                                .frame(maxWidth: .infinity, minHeight: 320)
                            } else {
                                ForEach(filteredGroups(in: snapshot)) { group in
                                    proxyGroupCard(group, scrollProxy: scrollProxy)
                                }
                            }
                        } else {
                            loadingCard
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, VisualStyle.pageHorizontalPadding)
                    .padding(.vertical, VisualStyle.pageVerticalPadding)
                }
                .scrollbarSafeContent()
            }
        }
        .task(id: model.state.isProxyRunning) {
            if model.state.isProxyRunning { model.refreshMihomoProviders() }
        }
        .sheet(isPresented: $showsProviders) {
            ProviderManagementView(kind: .proxy)
        }
        .onChange(of: model.state.localProxyConfiguration.routingMode) { _, mode in
            if optimisticRoutingMode == mode {
                optimisticRoutingMode = nil
            }
        }
        .onChange(of: model.isRoutingModeChanging) { _, isChanging in
            if !isChanging {
                optimisticRoutingMode = nil
            }
        }
    }

    private var headerActions: some View {
        HStack(spacing: VisualStyle.spacing8) {
            Button {
                showsProviders = true
            } label: {
                Label("Provider", systemImage: "shippingbox")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!model.state.isProxyRunning)

            ProxyRoutingModePicker(
                selection: Binding(
                    get: { displayedRoutingMode },
                    set: { selectRoutingMode($0) }
                ),
                isDisabled: routingModePickerDisabled,
                showsDescription: false
            )
            .frame(width: 224)

            Button {
                model.refreshMihomoRuntime()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .help("刷新代理组")
            .disabled(!model.state.isProxyRunning || model.isMihomoActionBusy)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
            TextField("搜索代理组或节点", text: $searchText)
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
        .padding(.horizontal, 9)
        .frame(maxWidth: 340, minHeight: 30)
        .background(VisualStyle.subtleFill, in: RoundedRectangle(cornerRadius: 7))
    }

    private var displayedRoutingMode: ProxyRoutingMode {
        optimisticRoutingMode ?? model.state.localProxyConfiguration.routingMode
    }

    private var routingModePickerDisabled: Bool {
        guard model.state.launchPhase == .ready else { return true }
        if model.isRoutingModeChanging
            || model.isSystemProxyTransitioning
            || model.isMihomoActionBusy
            || model.state.runtimeOperation != nil
            || model.isTemplateOperationBusy
            || model.switchingIP != nil
        {
            return true
        }
        switch model.state.proxyCorePhase {
        case .stopped, .running, .failed:
            return false
        case .validating, .starting, .stopping:
            return true
        }
    }

    private func selectRoutingMode(_ mode: ProxyRoutingMode) {
        guard mode != displayedRoutingMode, !routingModePickerDisabled else { return }
        model.setRoutingMode(mode)
        optimisticRoutingMode = model.isRoutingModeChanging ? mode : nil
    }

    private var unavailableCard: some View {
        return SurfaceCard {
            ContentUnavailableView {
                Label("Mihomo 尚未运行", systemImage: "wifi.slash")
            } description: {
                Text("启动本地代理后，可以在这里查看代理组并切换出站节点。")
            } actions: {
                Button("启动本地代理", systemImage: "play.fill", action: model.startProxy)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.activeProxyRuntimeIsAvailable || !model.isProxyConfigurationReady)
            }
            .frame(maxWidth: .infinity, minHeight: 320)
        }
    }

    private var loadingCard: some View {
        SurfaceCard {
            VStack(spacing: VisualStyle.spacing12) {
                ProgressView()
                    .controlSize(.large)
                Text(runtimeLoadingTitle)
                    .font(.headline)
                if case .failed(let message) = model.state.mihomoRuntime.phase {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(VisualStyle.negative)
                        .multilineTextAlignment(.center)
                    Button("重试", action: model.refreshMihomoRuntime)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 320)
        }
    }

    private var runtimeLoadingTitle: String {
        if case .failed = model.state.mihomoRuntime.phase { return "无法读取代理组" }
        return "正在读取代理组…"
    }

    private func filteredGroups(in snapshot: MihomoRuntimeSnapshot) -> [MihomoProxyGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return snapshot.proxyGroups }
        return snapshot.proxyGroups.filter { group in
            group.name.localizedCaseInsensitiveContains(query)
                || group.selected.localizedCaseInsensitiveContains(query)
                || group.candidates.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private func proxyGroupCard(
        _ group: MihomoProxyGroup,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        let state = groupState(for: group.name)
        let candidates = ProxyGroupPresentation.candidates(
            in: group,
            filterText: state.filterText,
            sortMode: state.sortMode
        )

        return SurfaceCard {
            CardHeader(group.name, systemImage: groupIcon(group.type)) {
                HStack(spacing: VisualStyle.spacing8) {
                    StatusBadge(group.type, tone: .neutral)
                    StatusBadge(group.selected.ifEmpty("未选择"), tone: .positive, systemImage: "checkmark")

                    Button {
                        updateGroupState(group.name) { $0.isExpanded.toggle() }
                    } label: {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(state.isExpanded ? 90 : 0))
                    }
                    .buttonStyle(.borderless)
                    .iconButtonHitTarget()
                    .help(state.isExpanded ? "折叠代理组" : "展开代理组")
                }
            }
            Divider()

            groupToolbar(group, state: state, scrollProxy: scrollProxy)

            if state.isExpanded {
                Divider()

                if candidates.isEmpty {
                    ContentUnavailableView(
                        "没有匹配的节点",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("支持节点名称、type=VLESS、delay<250、delay=timeout 等条件。")
                    )
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 190), spacing: VisualStyle.spacing8)],
                        alignment: .leading,
                        spacing: VisualStyle.spacing8
                    ) {
                        ForEach(candidates) { candidate in
                            proxyCandidate(
                                candidate,
                                in: group,
                                showsType: state.showsType
                            )
                            .id(candidateID(candidate.name, group: group.name))
                        }
                    }
                    .padding(VisualStyle.spacing16)
                }
            }
        }
    }

    private func groupToolbar(
        _ group: MihomoProxyGroup,
        state: ProxyGroupViewState,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        HStack(spacing: VisualStyle.spacing8) {
            if state.inputMode == .filter {
                TextField(
                    "筛选节点，支持 delay<250、delay=timeout、type=VLESS",
                    text: groupStateBinding(group.name, \.filterText)
                )
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)
            } else if state.inputMode == .testURL {
                TextField(
                    AppMetadata.proxyDelayTestURL,
                    text: groupStateBinding(group.name, \.testURL)
                )
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)
                .accessibilityLabel("延迟测试 URL")
            }

            Spacer(minLength: 0)

            Button {
                locateSelectedProxy(group, scrollProxy: scrollProxy)
            } label: {
                Label("定位当前节点", systemImage: "location")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .iconButtonHitTarget()
            .help("定位当前节点")
            .disabled(group.selected.isEmpty)

            Button {
                model.testProxyGroup(group.name, url: state.testURL)
            } label: {
                if model.state.mihomoRuntime.testingProxyGroup == group.name {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("测试延迟", systemImage: "gauge.with.dots.needle.67percent")
                        .labelStyle(.iconOnly)
                }
            }
            .buttonStyle(.borderless)
            .iconButtonHitTarget()
            .help(state.testURL.isEmpty ? "测试组内节点延迟" : "使用自定义 URL 测试延迟")
            .disabled(model.isMihomoActionBusy)

            Button {
                updateGroupState(group.name) {
                    $0.isExpanded = true
                    $0.sortMode = $0.sortMode.next
                }
            } label: {
                Label(state.sortMode.title, systemImage: state.sortMode.systemImage)
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .iconButtonHitTarget()
            .help(state.sortMode.title)

            Button {
                updateGroupState(group.name) {
                    $0.inputMode = $0.inputMode == .testURL ? nil : .testURL
                }
            } label: {
                Label(
                    "自定义延迟测试 URL",
                    systemImage: state.inputMode == .testURL
                        ? "wifi.circle.fill" : "wifi.circle"
                )
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .iconButtonHitTarget()
            .help("自定义延迟测试 URL")

            Button {
                updateGroupState(group.name) {
                    $0.isExpanded = true
                    $0.showsType.toggle()
                }
            } label: {
                Label(
                    state.showsType ? "隐藏节点类型" : "显示节点类型",
                    systemImage: state.showsType ? "eye" : "eye.slash"
                )
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .iconButtonHitTarget()
            .help(state.showsType ? "隐藏节点类型" : "显示节点类型")

            Button {
                updateGroupState(group.name) {
                    $0.isExpanded = true
                    $0.inputMode = $0.inputMode == .filter ? nil : .filter
                }
            } label: {
                Label(
                    "筛选节点",
                    systemImage: state.inputMode == .filter
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .iconButtonHitTarget()
            .help("筛选节点")
        }
        .padding(.horizontal, VisualStyle.spacing16)
        .padding(.vertical, VisualStyle.spacing8)
    }

    private func proxyCandidate(
        _ candidate: ProxyCandidatePresentation,
        in group: MihomoProxyGroup,
        showsType: Bool
    ) -> some View {
        let selected = group.selected == candidate.name
        let delay = candidate.delay
        let isTesting = model.state.mihomoRuntime.testingProxyGroup == group.name
        return Button {
            model.selectProxy(group: group.name, proxy: candidate.name)
        } label: {
            HStack(spacing: VisualStyle.spacing8) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? VisualStyle.positive : Color.secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.name)
                        .font(.callout.weight(selected ? .semibold : .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        Text(isTesting ? "测试中…" : RuntimePresentation.delay(delay))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(delayTone(delay).color)
                        if showsType {
                            Text(candidate.type)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(VisualStyle.subtleFill, in: Capsule())
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, VisualStyle.spacing12)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .background(
                selected ? VisualStyle.positive.opacity(0.1) : VisualStyle.subtleFill,
                in: RoundedRectangle(cornerRadius: VisualStyle.radiusSmall)
            )
            .overlay {
                RoundedRectangle(cornerRadius: VisualStyle.radiusSmall)
                    .stroke(selected ? VisualStyle.positive.opacity(0.5) : VisualStyle.surfaceBorder)
            }
        }
        .buttonStyle(.plain)
        .disabled(selected || model.isMihomoActionBusy)
        .help(selected ? "当前代理" : "切换到 \(candidate.name)")
    }

    private func groupState(for name: String) -> ProxyGroupViewState {
        groupStates[name] ?? ProxyGroupViewState()
    }

    private func updateGroupState(
        _ name: String,
        update: (inout ProxyGroupViewState) -> Void
    ) {
        var state = groupState(for: name)
        update(&state)
        groupStates[name] = state
    }

    private func groupStateBinding<Value>(
        _ name: String,
        _ keyPath: WritableKeyPath<ProxyGroupViewState, Value>
    ) -> Binding<Value> {
        Binding {
            groupState(for: name)[keyPath: keyPath]
        } set: { value in
            updateGroupState(name) { $0[keyPath: keyPath] = value }
        }
    }

    private func locateSelectedProxy(
        _ group: MihomoProxyGroup,
        scrollProxy: ScrollViewProxy
    ) {
        guard !group.selected.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            updateGroupState(group.name) { $0.isExpanded = true }
            scrollProxy.scrollTo(
                candidateID(group.selected, group: group.name),
                anchor: .center
            )
        }
    }

    private func candidateID(_ candidate: String, group: String) -> String {
        "proxy-candidate-\(group)-\(candidate)"
    }

    private func groupIcon(_ type: String) -> String {
        switch type.lowercased() {
        case "urltest", "fallback": "gauge.with.dots.needle.67percent"
        case "loadbalance": "arrow.triangle.branch"
        default: "wifi"
        }
    }

    private func delayTone(_ delay: Int?) -> AppTone {
        guard let delay else { return .neutral }
        if delay == 0 { return .negative }
        guard delay > 0 else { return .neutral }
        if delay < 250 { return .positive }
        if delay < 600 { return .warning }
        return .negative
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
