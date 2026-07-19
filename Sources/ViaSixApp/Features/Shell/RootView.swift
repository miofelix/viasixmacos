import SwiftUI
import ViaSixCore

struct RootView: View {
    @State private var selection: AppSection? = .overview

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle(AppMetadata.name)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } detail: {
            ZStack {
                VisualStyle.pageBackground
                    .ignoresSafeArea()

                page(for: selection ?? .overview)
                    .padding(28)
            }
        }
        .tint(VisualStyle.accent)
        .frame(minWidth: 960, minHeight: 640)
    }

    @ViewBuilder
    private func page(for section: AppSection) -> some View {
        switch section {
        case .overview:
            OverviewPlaceholderView()
        case .nodes:
            FeaturePlaceholderView(
                title: "节点优选",
                subtitle: "Cloudflare IPv4 / IPv6 测速与节点切换",
                systemImage: "network"
            )
        case .logs:
            FeaturePlaceholderView(
                title: "运行日志",
                subtitle: "测速和 Xray 输出将在这里集中展示",
                systemImage: "text.alignleft"
            )
        case .settings:
            SettingsPlaceholderView()
        }
    }
}

private struct OverviewPlaceholderView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("ViaSix", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))

                    Text("让 IPv6 节点优选更简单")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("原生测速、智能切换与 Xray 生命周期管理。")
                        .foregroundStyle(.white.opacity(0.78))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(30)
                .background(VisualStyle.banner, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: VisualStyle.secondaryAccent.opacity(0.22), radius: 22, y: 10)

                HStack(spacing: 16) {
                    StatusCard(title: "代理状态", value: "未启动", systemImage: "power")
                    StatusCard(title: "当前节点", value: "—", systemImage: "globe.asia.australia")
                    StatusCard(title: "本地端口", value: "11451", systemImage: "point.3.connected.trianglepath.dotted")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("项目骨架已就绪")
                        .font(.headline)
                    Text("接下来的阶段会加入参数持久化、测速引擎、配置切换、Xray 管理、出口检测和菜单栏控制。")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
        }
    }
}

private struct StatusCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(VisualStyle.accent)
                .frame(width: 38, height: 38)
                .background(VisualStyle.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title2.weight(.semibold))
                .lineLimit(1)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

private struct FeaturePlaceholderView: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(subtitle))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .cardStyle()
    }
}

struct SettingsPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "设置",
            systemImage: "gearshape",
            description: Text("运行组件与应用偏好将在后续阶段加入。")
        )
        .padding(24)
    }
}

