import SwiftUI
import ViaSixCore

struct ProxiesView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""
    @State private var showsProviders = false
    @State private var optimisticRoutingMode: ProxyRoutingMode?

    var body: some View {
        VStack(spacing: 0) {
            AppPageHeader("代理", subtitle: "管理代理组与路由模式") {
                headerActions
            }

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
                                proxyGroupCard(group)
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
        SurfaceCard {
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

    private func proxyGroupCard(_ group: MihomoProxyGroup) -> some View {
        SurfaceCard {
            CardHeader(group.name, systemImage: groupIcon(group.type)) {
                HStack(spacing: VisualStyle.spacing8) {
                    Button {
                        model.testProxyGroup(group.name)
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
                    .help("测试组内节点延迟")
                    .disabled(model.isMihomoActionBusy)

                    StatusBadge(group.type, tone: .neutral)
                    StatusBadge(group.selected.ifEmpty("未选择"), tone: .positive, systemImage: "checkmark")
                }
            }
            Divider()

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 190), spacing: VisualStyle.spacing8)],
                alignment: .leading,
                spacing: VisualStyle.spacing8
            ) {
                ForEach(group.candidates, id: \.self) { candidate in
                    proxyCandidate(candidate, in: group)
                }
            }
            .padding(VisualStyle.spacing16)
        }
    }

    private func proxyCandidate(_ candidate: String, in group: MihomoProxyGroup) -> some View {
        let selected = group.selected == candidate
        let delay = group.delays[candidate]
        let isTesting = model.state.mihomoRuntime.testingProxyGroup == group.name
        return Button {
            model.selectProxy(group: group.name, proxy: candidate)
        } label: {
            HStack(spacing: VisualStyle.spacing8) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? VisualStyle.positive : Color.secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate)
                        .font(.callout.weight(selected ? .semibold : .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(isTesting ? "测试中…" : RuntimePresentation.delay(delay))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(delayTone(delay).color)
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
        .help(selected ? "当前代理" : "切换到 \(candidate)")
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
