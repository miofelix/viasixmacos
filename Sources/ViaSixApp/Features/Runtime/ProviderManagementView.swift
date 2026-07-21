import SwiftUI
import ViaSixCore

enum ProviderManagementKind {
    case proxy
    case rule

    var title: String {
        switch self {
        case .proxy: "代理 Provider"
        case .rule: "规则 Provider"
        }
    }

    var subtitle: String {
        switch self {
        case .proxy: "查看订阅用量、节点数量并请求 Mihomo 更新订阅"
        case .rule: "查看规则集状态并请求 Mihomo 重新加载远端内容"
        }
    }
}

struct ProviderManagementView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let kind: ProviderManagementKind

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: VisualStyle.spacing12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.title)
                        .font(.title2.weight(.semibold))
                    Text(kind.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("全部更新", systemImage: "arrow.triangle.2.circlepath") {
                    updateAll()
                }
                .buttonStyle(.borderedProminent)
                .disabled(providerCount == 0 || model.isMihomoActionBusy)

                Button("关闭", systemImage: "xmark", action: dismiss.callAsFunction)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .help("关闭")
            }
            .padding(VisualStyle.spacing16)

            Divider()

            content
        }
        .frame(minWidth: 660, minHeight: 500)
        .background(VisualStyle.pageBackgroundColor)
        .task { model.refreshMihomoProviders() }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = model.state.mihomoRuntime.providerSnapshot {
            let isEmpty =
                kind == .proxy
                ? snapshot.proxyProviders.isEmpty
                : snapshot.ruleProviders.isEmpty
            if isEmpty {
                ContentUnavailableView(
                    "没有 \(kind.title)",
                    systemImage: "shippingbox",
                    description: Text("当前运行配置没有返回这一类 Provider。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: VisualStyle.spacing12) {
                        switch kind {
                        case .proxy:
                            ForEach(snapshot.proxyProviders) { provider in
                                proxyProviderCard(provider)
                            }
                        case .rule:
                            ForEach(snapshot.ruleProviders) { provider in
                                ruleProviderCard(provider)
                            }
                        }
                    }
                    .padding(VisualStyle.spacing16)
                }
                .scrollbarSafeContent()
            }
        } else {
            switch model.state.mihomoRuntime.providersPhase {
            case .failed(let message):
                ContentUnavailableView {
                    Label("无法读取 Provider", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("重试", action: model.refreshMihomoProviders)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .unavailable:
                ContentUnavailableView {
                    Label("Provider 尚未载入", systemImage: "shippingbox")
                } description: {
                    Text("内核可能正在处理其他操作，请稍后重试。")
                } actions: {
                    Button("载入", action: model.refreshMihomoProviders)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loading, .available:
                ProgressView("正在读取 Provider…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var providerCount: Int {
        guard let snapshot = model.state.mihomoRuntime.providerSnapshot else { return 0 }
        return switch kind {
        case .proxy: snapshot.proxyProviders.count
        case .rule: snapshot.ruleProviders.count
        }
    }

    private func proxyProviderCard(_ provider: MihomoProxyProvider) -> some View {
        let isUpdating = model.state.mihomoRuntime.updatingProxyProviders.contains(provider.name)
        return SurfaceCard {
            providerHeader(
                name: provider.name,
                details: ["\(provider.proxyCount) 个节点", provider.vehicleType],
                updatedAt: provider.updatedAt,
                isUpdating: isUpdating
            ) {
                model.updateProxyProvider(provider.name)
            }

            if let subscription = provider.subscriptionInfo {
                Divider()
                VStack(alignment: .leading, spacing: VisualStyle.spacing8) {
                    HStack {
                        Text("订阅用量")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text(
                            "\(RuntimePresentation.byteCount(subscription.used)) / "
                                + RuntimePresentation.byteCount(subscription.total)
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }

                    ProgressView(
                        value: Double(min(subscription.used, max(subscription.total, 0))),
                        total: Double(max(subscription.total, 1))
                    )
                    .tint(
                        subscription.total > 0 && subscription.used > subscription.total
                            ? VisualStyle.negative : VisualStyle.accent
                    )

                    HStack {
                        Label(
                            "上传 \(RuntimePresentation.byteCount(subscription.upload))",
                            systemImage: "arrow.up"
                        )
                        Label(
                            "下载 \(RuntimePresentation.byteCount(subscription.download))",
                            systemImage: "arrow.down"
                        )
                        Spacer()
                        Text(RuntimePresentation.subscriptionExpiry(subscription.expire))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(VisualStyle.spacing16)
            }
        }
    }

    private func ruleProviderCard(_ provider: MihomoRuleProvider) -> some View {
        let isUpdating = model.state.mihomoRuntime.updatingRuleProviders.contains(provider.name)
        return SurfaceCard {
            providerHeader(
                name: provider.name,
                details: [
                    "\(provider.ruleCount) 条规则",
                    provider.behavior,
                    provider.format,
                    provider.vehicleType,
                ],
                updatedAt: provider.updatedAt,
                isUpdating: isUpdating
            ) {
                model.updateRuleProvider(provider.name)
            }
        }
    }

    private func providerHeader(
        name: String,
        details: [String],
        updatedAt: String?,
        isUpdating: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: VisualStyle.spacing12) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(VisualStyle.accent)
                .frame(width: 38, height: 38)
                .background(VisualStyle.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 5) {
                    ForEach(details, id: \.self) { detail in
                        StatusBadge(detail, tone: .neutral)
                    }
                }
                Text("更新于 \(RuntimePresentation.providerTimestamp(updatedAt))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button(action: action) {
                if isUpdating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("更新", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .disabled(model.isMihomoActionBusy)
        }
        .padding(VisualStyle.spacing16)
    }

    private func updateAll() {
        switch kind {
        case .proxy: model.updateAllProxyProviders()
        case .rule: model.updateAllRuleProviders()
        }
    }
}
