import SwiftUI
import ViaSixCore

struct RulesView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""
    @State private var selectedType = "全部"
    @State private var showsProviders = false

    var body: some View {
        VStack(spacing: 0) {
            AppPageHeader("规则", subtitle: "检查当前 Mihomo 配置的路由顺序与目标策略") {
                HStack(spacing: VisualStyle.spacing8) {
                    Button("Provider", systemImage: "shippingbox") {
                        showsProviders = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!model.state.isProxyRunning)

                    Button {
                        model.refreshMihomoRuntime()
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!model.state.isProxyRunning || model.isMihomoActionBusy)
                }
            }

            Group {
                if !model.state.isProxyRunning {
                    SurfaceCard {
                        ContentUnavailableView(
                            "Mihomo 尚未运行",
                            systemImage: "arrow.triangle.branch",
                            description: Text("启动本地代理后，可以查看内核实际加载的规则。")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    rulesCard
                }
            }
            .padding(.horizontal, VisualStyle.pageHorizontalPadding)
            .padding(.vertical, VisualStyle.pageVerticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: model.state.isProxyRunning) {
            if model.state.isProxyRunning { model.refreshMihomoProviders() }
        }
        .sheet(isPresented: $showsProviders) {
            ProviderManagementView(kind: .rule)
        }
    }

    private var rules: [MihomoRule] {
        model.state.mihomoRuntime.snapshot?.rules ?? []
    }

    private var ruleTypes: [String] {
        ["全部"] + Array(Set(rules.map(\.type))).sorted()
    }

    private var filteredRules: [MihomoRule] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return rules.filter { rule in
            (selectedType == "全部" || rule.type == selectedType)
                && (query.isEmpty
                    || rule.type.localizedCaseInsensitiveContains(query)
                    || rule.payload.localizedCaseInsensitiveContains(query)
                    || rule.proxy.localizedCaseInsensitiveContains(query))
        }
    }

    private var rulesCard: some View {
        SurfaceCard {
            HStack(spacing: VisualStyle.spacing8) {
                Picker("规则类型", selection: $selectedType) {
                    ForEach(ruleTypes, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 150)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                    TextField("搜索规则内容或策略", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 9)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(VisualStyle.subtleFill, in: RoundedRectangle(cornerRadius: 7))

                Text("\(filteredRules.count) / \(rules.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(VisualStyle.spacing12)

            Divider()

            if filteredRules.isEmpty {
                ContentUnavailableView(
                    rules.isEmpty ? "暂无规则" : "没有匹配的规则",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text(rules.isEmpty ? "当前内核没有返回已加载规则。" : "尝试更换类型或搜索条件。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredRules) { rule in
                            ruleRow(rule)
                            if rule.id != filteredRules.last?.id { Divider() }
                        }
                    }
                }
                .scrollbarSafeContent()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ruleRow(_ rule: MihomoRule) -> some View {
        HStack(spacing: VisualStyle.spacing12) {
            Text("\(rule.index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 34, alignment: .trailing)

            StatusBadge(rule.type, tone: ruleTone(rule.type))
                .frame(width: 140, alignment: .leading)

            Text(rule.payload.isEmpty ? "—" : rule.payload)
                .font(.callout.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            Label(rule.proxy, systemImage: "arrow.turn.down.right")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)
        }
        .padding(.horizontal, VisualStyle.spacing12)
        .frame(minHeight: 48)
    }

    private func ruleTone(_ type: String) -> AppTone {
        if type.localizedCaseInsensitiveContains("MATCH") { return .warning }
        if type.localizedCaseInsensitiveContains("DOMAIN") { return .accent }
        if type.localizedCaseInsensitiveContains("IP") { return .positive }
        return .neutral
    }
}
