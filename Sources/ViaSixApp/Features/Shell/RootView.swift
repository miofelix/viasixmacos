import AppKit
import SwiftUI
import ViaSixCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Rectangle()
                .fill(VisualStyle.surfaceBorder)
                .frame(width: 1)

            detail
        }
        .background(VisualStyle.pageBackgroundColor)
        .tint(VisualStyle.accent)
        .frame(minWidth: 900, minHeight: 640)
        .comfortableInterface()
        .animation(VisualStyle.standardAnimation, value: model.state.notice?.id)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            brandHeader

            VStack(spacing: 4) {
                ForEach(AppSection.allCases) { section in
                    sidebarNavigationButton(section)
                }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: VisualStyle.spacing16)

            sidebarProxyPanel
                .padding(12)
        }
        .frame(width: VisualStyle.sidebarWidth)
        .background(VisualStyle.sidebarBackgroundColor)
    }

    private var brandHeader: some View {
        HStack(spacing: 11) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(AppMetadata.name)
                    .font(.system(size: 18, weight: .bold))
                Text("网络代理与节点测速")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 20)
    }

    private func sidebarNavigationButton(_ section: AppSection) -> some View {
        let isSelected = router.selectedSection == section

        return Button {
            router.select(section)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                    .frame(width: 20)

                Text(section.title)
                    .font(.callout.weight(isSelected ? .semibold : .medium))

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? VisualStyle.accent : Color.primary)
            .padding(.horizontal, 13)
            .frame(height: VisualStyle.navigationRowHeight)
            .background(
                isSelected ? VisualStyle.accent.opacity(0.13) : .clear,
                in: RoundedRectangle(
                    cornerRadius: VisualStyle.radiusSmall,
                    style: .continuous
                )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title)
        .accessibilityValue(isSelected ? "当前页面" : "")
    }

    private var sidebarProxyPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(sidebarPresentation.tone.color)
                    .frame(width: 7, height: 7)

                Text(sidebarPresentation.statusTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 4)

                if sidebarPresentation.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let endpoint = sidebarPresentation.endpointSummary {
                Text(endpoint)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            if let detail = sidebarPresentation.detailText {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.state.isProxyRunning, let snapshot = model.state.mihomoRuntime.snapshot {
                Divider()

                HStack(spacing: 0) {
                    sidebarMetric(
                        icon: "arrow.up",
                        value: RuntimePresentation.speed(model.state.mihomoRuntime.uploadSpeed),
                        tone: .warning
                    )
                    sidebarMetric(
                        icon: "arrow.down",
                        value: RuntimePresentation.speed(model.state.mihomoRuntime.downloadSpeed),
                        tone: .accent
                    )
                    sidebarMetric(
                        icon: "link",
                        value: "\(snapshot.connections.count)",
                        tone: .positive
                    )
                }
            }

            Button(action: performSidebarAction) {
                Label(
                    sidebarPresentation.actionTitle,
                    systemImage: sidebarPresentation.actionSystemImage
                )
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.bordered)
            .disabled(
                sidebarPresentation.action == .none
                    || sidebarProxyControlDisabled
            )
            .help(sidebarActionHelp)
            .accessibilityLabel(sidebarActionHelp)
            .accessibilityValue(sidebarPresentation.statusTitle)
        }
        .padding(12)
        .background(
            VisualStyle.surfaceColor,
            in: RoundedRectangle(
                cornerRadius: VisualStyle.radiusMedium,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: VisualStyle.radiusMedium,
                style: .continuous
            )
            .stroke(VisualStyle.surfaceBorder)
        }
    }

    private func sidebarMetric(icon: String, value: String, tone: AppTone) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tone.color)
            Text(value)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var detail: some View {
        ZStack(alignment: .bottomTrailing) {
            VisualStyle.pageBackground
                .ignoresSafeArea()

            detailContent
                .frame(maxWidth: 1_160, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, VisualStyle.pageHorizontalPadding)
                .padding(.vertical, VisualStyle.pageVerticalPadding)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            if let notice = model.state.notice {
                NoticeView(
                    notice: notice,
                    openSettings: {
                        router.select(.settings)
                    },
                    dismiss: {
                        model.clearNotice()
                    }
                )
                .padding(22)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
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
                    .controlSize(.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .ready:
            page(for: router.selectedSection)
        }
    }

    @ViewBuilder
    private func page(for section: AppSection) -> some View {
        switch section {
        case .overview:
            OverviewView(
                onSelectNodes: { router.select(.nodes) },
                onManageRuntime: { router.select(.settings) }
            )
        case .proxies:
            ProxiesView()
        case .profiles:
            ProfilesView()
        case .connections:
            ConnectionsView()
        case .rules:
            RulesView()
        case .nodes:
            NodesView()
        case .logs:
            LogsView()
        case .settings:
            SettingsView()
        }
    }

    private func performSidebarAction() {
        switch sidebarPresentation.action {
        case .stopProxy:
            model.stopProxy()
        case .startProxy:
            model.startProxy()
        case .none:
            break
        }
    }

    private var sidebarPresentation: SidebarProxyPresentation {
        SidebarProxyPresentation(
            launchPhase: model.state.launchPhase,
            proxyCorePhase: model.state.proxyCorePhase,
            endpoint: model.state.proxyEndpoint
        )
    }

    private var sidebarProxyControlDisabled: Bool {
        guard model.state.launchPhase == .ready else { return true }
        if model.state.runtimeOperation != nil || model.isTemplateOperationBusy { return true }
        switch model.state.proxyCorePhase {
        case .running, .validating, .starting:
            return false
        case .stopped, .failed:
            return model.switchingIP != nil
                || (model.state.localProxyConfiguration.networkAccessMode == .virtualInterface
                    && model.hasForeignTunSession)
                || !model.activeProxyRuntimeIsAvailable
                || !model.isProxyConfigurationReady
        case .stopping:
            return true
        }
    }

    private var sidebarActionHelp: String {
        switch model.state.launchPhase {
        case .idle, .loading:
            return "ViaSix 正在准备"
        case .failed:
            return "初始化失败，请在主内容区重试"
        case .ready:
            break
        }
        if let operation = model.state.runtimeOperation {
            return operation.description
        }
        if model.isTemplateOperationBusy {
            return "代理配置操作进行中"
        }
        return switch model.state.proxyCorePhase {
        case .running, .validating, .starting:
            "停止本地代理"
        case .stopping:
            "正在停止本地代理"
        case .stopped, .failed:
            if model.state.localProxyConfiguration.networkAccessMode == .virtualInterface,
                model.hasForeignTunSession
            {
                "虚拟网卡会话正由其他登录用户使用"
            } else if !model.activeProxyRuntimeIsAvailable {
                model.state.localProxyConfiguration.networkAccessMode == .virtualInterface
                    ? "请先在设置中准备虚拟网卡服务"
                    : "请先在设置中安装 Mihomo"
            } else if let issue = model.proxyConfigurationIssue {
                "请先在设置中修复代理配置：\(issue)"
            } else {
                "启动本地代理"
            }
        }
    }
}

private struct NoticeView: View {
    let notice: AppNotice
    let openSettings: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(notice.message)
                .font(.callout.weight(.medium))
                .lineLimit(2)
            if notice.action == .openSettings {
                Button(action: openSettings) {
                    Text("打开设置")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.borderless)
            }
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .iconButtonHitTarget()
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
    }

    private var color: Color {
        switch notice.style {
        case .info: VisualStyle.accent
        case .success: VisualStyle.positive
        case .error: VisualStyle.negative
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
