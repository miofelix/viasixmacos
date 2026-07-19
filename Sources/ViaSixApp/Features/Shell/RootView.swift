import SwiftUI
import ViaSixCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: AppSection? = .overview

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(AppSection.allCases, selection: $selection) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
                .listStyle(.sidebar)

                Divider()

                HStack(spacing: 9) {
                    Circle()
                        .fill(sidebarStatusColor)
                        .frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(sidebarStatusTitle)
                            .font(.caption.weight(.medium))
                    }
                    Spacer()
                }
                .padding(12)
            }
            .navigationTitle(AppMetadata.name)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } detail: {
            ZStack(alignment: .bottomTrailing) {
                VisualStyle.pageBackground
                    .ignoresSafeArea()

                detailContent
                    .frame(maxWidth: 1_120, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let notice = model.state.notice {
                    NoticeView(notice: notice) {
                        model.clearNotice()
                    }
                    .padding(22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .tint(VisualStyle.accent)
        .frame(minWidth: 960, minHeight: 640)
        .animation(.easeOut(duration: 0.18), value: model.state.notice?.id)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch model.state.launchPhase {
        case .idle, .loading:
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("正在准备 ViaSix…")
                    .font(.headline)
                Text("正在检查应用数据与必要组件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message):
            ContentUnavailableView {
                Label("初始化失败", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("重试", action: model.retryBootstrap)
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .ready:
            page(for: selection ?? .overview)
        }
    }

    @ViewBuilder
    private func page(for section: AppSection) -> some View {
        switch section {
        case .overview:
            OverviewView()
        case .nodes:
            NodesView()
        case .logs:
            LogsView()
        case .settings:
            SettingsView()
        }
    }

    private var sidebarStatusColor: Color {
        switch model.state.xrayPhase {
        case .running: .green
        case .validating, .starting, .stopping: .orange
        case .failed: .red
        case .stopped: .secondary
        }
    }

    private var sidebarStatusTitle: String {
        switch model.state.xrayPhase {
        case .running: "本地代理运行中"
        case .validating: "正在校验"
        case .starting: "正在启动"
        case .stopping: "正在停止"
        case .failed: "本地代理异常"
        case .stopped: "本地代理已停止"
        }
    }
}

private struct NoticeView: View {
    let notice: AppNotice
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(notice.message)
                .font(.callout.weight(.medium))
                .lineLimit(2)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("关闭通知")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(VisualStyle.surfaceBorder)
        }
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        .onTapGesture(perform: dismiss)
    }

    private var color: Color {
        switch notice.style {
        case .info: VisualStyle.accent
        case .success: .green
        case .error: .red
        }
    }

    private var icon: String {
        switch notice.style {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .error: "xmark.circle.fill"
        }
    }
}
