import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ViaSixCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showsTemplateEditor = false
    @State private var showsLocalProxyEditor = false
    @State private var presentedServerEditorMode: ServerConfigurationInputMode?
    @State private var exitIPEndpointDraft = ""
    @State private var exitIPEndpointError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VisualStyle.spacing20) {
                AppPageHeader("设置", subtitle: "连接、网络接入与运行组件")

                serverConfigurationCard
                localProxyCard
                runtimeCard
                dataCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollbarSafeContent()
        .onAppear {
            if exitIPEndpointDraft.isEmpty {
                exitIPEndpointDraft = model.exitIPEndpoint
            }
        }
        .onChange(of: model.exitIPEndpoint) { _, endpoint in
            if endpoint != exitIPEndpointDraft {
                exitIPEndpointDraft = endpoint
                exitIPEndpointError = nil
            }
        }
    }

    private var runtimeCard: some View {
        SurfaceCard {
            CardHeader("运行组件", systemImage: "shippingbox") {
                runtimeBadge
            }
            Divider()

            VStack(alignment: .leading, spacing: 0) {
                runtimeComponentSection(.cfst)
                Divider()
                    .padding(.vertical, VisualStyle.spacing4)
                runtimeComponentSection(.mihomo)

                if model.state.runtimeOperation != nil {
                    Divider()
                        .padding(.top, VisualStyle.spacing8)

                    HStack(spacing: VisualStyle.spacing12) {
                        runtimeOperationStatus
                        Spacer()
                        if model.state.runtimeOperation?.canCancel == true {
                            Button("取消", systemImage: "xmark.circle") {
                                model.cancelRuntimeOperation()
                            }
                        }
                    }
                    .padding(.vertical, VisualStyle.spacing12)
                }

                if let issue = model.runtimeIntegrityIssue {
                    Label(issue, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, VisualStyle.spacing12)
                }

                if let message = model.state.runtimeOperationError {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, VisualStyle.spacing12)
                }
            }
            .padding(.horizontal, VisualStyle.spacing16)
            .padding(.bottom, VisualStyle.spacing12)
        }
    }

    @ViewBuilder
    private var runtimeOperationStatus: some View {
        if let operation = model.state.runtimeOperation {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(operation.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(operation.description)
        }
    }

    private var serverConfigurationCard: some View {
        SurfaceCard {
            CardHeader("服务器连接", systemImage: "server.rack", tone: serverStatusTone) {
                StatusBadge(
                    serverStatusTitle,
                    tone: serverStatusTone,
                    systemImage: serverStatusSystemImage
                )
            }
            Divider()

            VStack(alignment: .leading, spacing: 0) {
                SettingRow(
                    "连接方式",
                    detail: "VLESS、VMess、Trojan、Shadowsocks",
                    systemImage: "point.3.connected.trianglepath.dotted"
                ) {
                    HStack(spacing: VisualStyle.spacing8) {
                        Button("分享链接", systemImage: "link") {
                            presentedServerEditorMode = .shareLink
                        }
                        .disabled(serverEditorDisabled)

                        Button("手动配置", systemImage: "slider.horizontal.3") {
                            presentedServerEditorMode = .manual
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(serverEditorDisabled)
                    }
                }

                Divider()
                    .padding(.leading, 52)

                SettingRow(
                    "高级配置",
                    detail: "直接编辑或导入 Mihomo YAML",
                    systemImage: "curlybraces.square"
                ) {
                    Menu {
                        Button("编辑 Mihomo YAML", systemImage: "curlybraces.square") {
                            showsTemplateEditor = true
                        }
                        .disabled(!serverConfigurationExists)

                        Button("导入代理配置…", systemImage: "square.and.arrow.down") {
                            importProxyProfile()
                        }
                    } label: {
                        Label("高级", systemImage: "ellipsis.circle")
                    }
                    .disabled(proxyImportDisabled)
                }

                proxyConfigurationFeedback
            }
            .padding(.horizontal, VisualStyle.spacing16)
            .padding(.bottom, VisualStyle.spacing12)
        }
        .sheet(isPresented: $showsTemplateEditor) {
            MihomoProfileEditorView()
                .environment(model)
        }
        .sheet(item: $presentedServerEditorMode) { mode in
            ServerConfigurationEditorView(initialInputMode: mode)
                .environment(model)
        }
    }

    private var localProxyCard: some View {
        SurfaceCard {
            CardHeader("本机代理", systemImage: "laptopcomputer", tone: .accent) {
                Button("编辑", systemImage: "slider.horizontal.3") {
                    showsLocalProxyEditor = true
                }
                .disabled(proxyImportDisabled)
            }
            Divider()

            VStack(spacing: 0) {
                SettingRow(
                    "代理模式",
                    detail: model.state.localProxyConfiguration.routingMode.appDescription,
                    systemImage: model.state.localProxyConfiguration.routingMode.appSystemImage
                ) {
                    StatusBadge(
                        model.state.localProxyConfiguration.routingMode.displayName,
                        tone: .accent
                    )
                }

                Divider()
                    .padding(.leading, 52)

                SettingRow(
                    "网络接入",
                    detail: networkAccessConfigurationDetail,
                    systemImage: "network"
                ) {
                    StatusBadge(
                        model.state.localProxyConfiguration.networkAccessMode.displayName,
                        tone: networkAccessTone,
                        systemImage: networkAccessSystemImage
                    )
                }

                Divider()
                    .padding(.leading, 52)

                SettingRow(
                    "监听端点",
                    detail: "HTTP 与 SOCKS 共用本地 mixed 入口",
                    systemImage: "dot.radiowaves.left.and.right"
                ) {
                    Text(model.state.proxyEndpoint.displayAddress)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, VisualStyle.spacing16)
            .padding(.bottom, VisualStyle.spacing12)
        }
        .sheet(isPresented: $showsLocalProxyEditor) {
            LocalProxySettingsView()
                .environment(model)
        }
    }

    private var dataCard: some View {
        SurfaceCard {
            CardHeader("应用与数据", systemImage: "folder", tone: .neutral)
            Divider()

            VStack(alignment: .leading, spacing: 0) {
                SettingRow(
                    "数据目录",
                    detail: model.paths.root.path,
                    systemImage: "folder"
                ) {
                    Button("打开", systemImage: "arrow.up.right.square") {
                        NSWorkspace.shared.open(model.paths.root)
                    }
                }

                Divider()
                    .padding(.leading, 52)

                SettingRow(
                    "出口 IP 检测服务",
                    detail: exitIPEndpointError ?? "自动检测出口地址时使用",
                    systemImage: "location"
                ) {
                    HStack(spacing: VisualStyle.spacing8) {
                        TextField(
                            AppMetadata.defaultExitIPEndpoint,
                            text: $exitIPEndpointDraft
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 220, idealWidth: 320, maxWidth: 380)
                        .accessibilityLabel("出口 IP 检测服务地址")
                        .accessibilityHint("使用 HTTP 或 HTTPS 地址")
                        .onChange(of: exitIPEndpointDraft) { _, value in
                            validateAndSaveExitIPEndpoint(value)
                        }

                        Button {
                            exitIPEndpointDraft = AppMetadata.defaultExitIPEndpoint
                            validateAndSaveExitIPEndpoint(exitIPEndpointDraft)
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.borderless)
                        .iconButtonHitTarget()
                        .help("恢复默认检测服务")
                        .accessibilityLabel("恢复默认检测服务")
                        .disabled(exitIPEndpointDraft == AppMetadata.defaultExitIPEndpoint)
                    }
                }

                Divider()

                HStack(spacing: VisualStyle.spacing8) {
                    Button("使用帮助", systemImage: "questionmark.circle") {
                        AppDocumentOpener.open(.userGuide)
                    }
                    Button("第三方许可", systemImage: "doc.plaintext") {
                        AppDocumentOpener.open(.thirdPartyNotices)
                    }
                    Spacer()
                }
                .padding(.vertical, VisualStyle.spacing12)
            }
            .padding(.horizontal, VisualStyle.spacing16)
            .padding(.bottom, VisualStyle.spacing12)
        }
    }

    @ViewBuilder
    private var proxyConfigurationFeedback: some View {
        if let templateOperationStatus {
            Divider()
            HStack(spacing: VisualStyle.spacing8) {
                ProgressView()
                    .controlSize(.small)
                Text(templateOperationStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, VisualStyle.spacing12)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(templateOperationStatus)
        } else if let error = model.state.templateOperationError {
            Divider()
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, VisualStyle.spacing12)
        } else if let issue = model.proxyConfigurationIssue {
            Divider()
            Label(issue, systemImage: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, VisualStyle.spacing12)
        } else if proxyImportDisabled {
            Divider()
            Text(proxyImportBlockedMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, VisualStyle.spacing12)
        }
    }

    private var serverConfigurationExists: Bool {
        FileManager.default.fileExists(atPath: model.paths.profileConfig.path)
    }

    private var serverEditorDisabled: Bool {
        proxyImportDisabled
    }

    private var serverStatusTitle: String {
        if model.state.templateOperationPhase != .idle { return "处理中" }
        if model.state.templateOperationError != nil { return "操作失败" }
        if !serverConfigurationExists { return "未配置" }
        if model.proxyConfigurationIssue != nil { return "需要检查" }
        return "可用"
    }

    private var serverStatusTone: AppTone {
        if model.state.templateOperationPhase != .idle { return .accent }
        if model.state.templateOperationError != nil { return .negative }
        if !serverConfigurationExists || model.proxyConfigurationIssue != nil { return .warning }
        return .positive
    }

    private var serverStatusSystemImage: String {
        switch serverStatusTone {
        case .accent: "arrow.triangle.2.circlepath"
        case .positive: "checkmark.circle.fill"
        case .warning: "exclamationmark.circle.fill"
        case .negative: "xmark.circle.fill"
        case .neutral: "circle"
        }
    }

    private var networkAccessConfigurationDetail: String {
        switch model.state.localProxyConfiguration.networkAccessMode {
        case .localProxy:
            "仅提供本机 mixed 代理端口"
        case .systemProxy:
            "本地代理运行后接入 macOS 系统代理"
        case .virtualInterface:
            "通过虚拟网卡接管应用流量"
        }
    }

    private var systemProxyPresentation: SystemProxyStatusPresentation {
        SystemProxyStatusPresentation(
            phase: model.state.systemProxyPhase,
            isRequested: model.state.localProxyConfiguration.networkAccessMode.usesSystemProxy
        )
    }

    private var networkAccessTone: AppTone {
        switch model.state.localProxyConfiguration.networkAccessMode {
        case .localProxy: .neutral
        case .systemProxy: systemProxyPresentation.appTone
        case .virtualInterface: .accent
        }
    }

    private var networkAccessSystemImage: String {
        switch model.state.localProxyConfiguration.networkAccessMode {
        case .localProxy: "dot.radiowaves.left.and.right"
        case .systemProxy: systemProxyStatusSystemImage
        case .virtualInterface: "point.3.filled.connected.trianglepath.dotted"
        }
    }

    private var systemProxyStatusSystemImage: String {
        if systemProxyPresentation.isTransitioning {
            return "hourglass"
        }
        return switch systemProxyPresentation.tone {
        case .active: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        case .pending: "clock.fill"
        case .neutral: "circle"
        }
    }

    private var runtimeBadge: some View {
        let (label, tone, systemImage): (String, AppTone, String) =
            if model.state.runtimeOperation != nil {
                ("操作中", .accent, "arrow.triangle.2.circlepath")
            } else if model.state.runtimeOperationError != nil {
                ("操作失败", .negative, "xmark.circle.fill")
            } else if model.runtimeIntegrityIssue != nil {
                ("需修复", .warning, "exclamationmark.circle.fill")
            } else {
                switch model.state.runtimePhase {
                case .checking: ("检查中", .neutral, "arrow.triangle.2.circlepath")
                case .missing: ("未就绪", .warning, "exclamationmark.circle.fill")
                case .ready: ("已就绪", .positive, "checkmark.circle.fill")
                }
            }
        return StatusBadge(label, tone: tone, systemImage: systemImage)
    }

    private func runtimeComponentSection(_ component: RuntimeComponent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            componentRow(
                component: component,
                url: resolvedDisplayURL(for: component),
                ready: componentReady(component)
            )

            Divider()
                .padding(.leading, 52)

            customExecutableRow(component)
        }
    }

    private func componentRow(
        component: RuntimeComponent,
        url: URL?,
        ready: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ready ? .green : .orange)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Link(destination: component.repositoryURL) {
                    HStack(spacing: 6) {
                        Text(component.displayName)
                            .fontWeight(.medium)
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("在 GitHub 打开 \(component.displayName)")
                Text(url?.path ?? "未找到")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()

            Button(
                componentInstallTitle(component),
                systemImage: componentOperationIsActive(component)
                    ? "arrow.triangle.2.circlepath"
                    : "arrow.down.circle"
            ) {
                model.installRuntime(component)
            }
            .buttonStyle(.bordered)
            .tint(VisualStyle.accent)
            .controlSize(.small)
            .disabled(componentInstallDisabled(component))
        }
        .frame(minHeight: VisualStyle.settingsRowHeight)
    }

    private func customExecutableRow(_ component: RuntimeComponent) -> some View {
        let value = customExecutablePath(component)
        let editingDisabled = componentPathEditingDisabled(component)
        return VStack(alignment: .leading, spacing: VisualStyle.spacing8) {
            HStack(spacing: VisualStyle.spacing12) {
                Image(systemName: "terminal")
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text("自定义可执行文件")
                        .font(.subheadline.weight(.medium))
                    Text(value.isEmpty ? "未指定；使用托管组件、Homebrew 或 PATH" : value)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button(value.isEmpty ? "导入…" : "更换…", systemImage: "folder") {
                    chooseExecutable(component)
                }
                .controlSize(.small)
                .disabled(editingDisabled)

                if !value.isEmpty {
                    Button {
                        model.setCustomExecutable(component, url: nil)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .iconButtonHitTarget()
                    .help("清除 \(component.displayName) 自定义路径")
                    .accessibilityLabel("清除 \(component.displayName) 自定义可执行文件")
                    .disabled(editingDisabled)
                }
            }

            if editingDisabled {
                Text(componentPathEditingMessage(component))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 36)
            }
        }
        .frame(minHeight: VisualStyle.settingsRowHeight)
    }

    private func customExecutablePath(_ component: RuntimeComponent) -> String {
        switch component {
        case .cfst:
            model.state.preferences.cfstPath
        case .mihomo:
            model.state.preferences.mihomoPath
        }
    }

    private func componentInstallTitle(_ component: RuntimeComponent) -> String {
        if componentOperationIsActive(component) { return "安装中" }
        if managedComponentInvalid(component) { return "修复" }
        return managedComponentReady(component) ? "重新安装" : "安装"
    }

    private func componentOperationIsActive(_ component: RuntimeComponent) -> Bool {
        model.state.runtimeOperation?.installingComponent == component
    }

    private func managedComponentReady(_ component: RuntimeComponent) -> Bool {
        switch component {
        case .cfst:
            model.state.runtimeStatus?.cfstIsReady == true
        case .mihomo:
            model.state.runtimeStatus?.mihomoIsReady == true
        }
    }

    private func managedComponentInvalid(_ component: RuntimeComponent) -> Bool {
        let payload: RuntimePayloadFile =
            switch component {
            case .cfst: .cfst
            case .mihomo: .mihomo
            }
        return model.state.runtimeStatus?.invalidFiles.contains(payload) == true
    }

    private func componentInstallDisabled(_ component: RuntimeComponent) -> Bool {
        guard model.state.launchPhase == .ready else { return true }
        guard model.state.runtimeOperation == nil else { return true }
        guard model.state.templateOperationPhase == .idle else { return true }
        guard model.switchingIP == nil else { return true }

        return switch component {
        case .cfst:
            model.isCfstBusy
        case .mihomo:
            switch model.state.proxyCorePhase {
            case .validating, .starting, .running, .stopping:
                true
            case .stopped, .failed:
                false
            }
        }
    }

    private func componentReady(_ component: RuntimeComponent) -> Bool {
        resolvedDisplayURL(for: component) != nil
    }

    private func componentPathEditingDisabled(_ component: RuntimeComponent) -> Bool {
        if model.state.runtimeOperation != nil { return true }
        return switch component {
        case .cfst:
            model.isCfstBusy
        case .mihomo:
            switch model.state.proxyCorePhase {
            case .validating, .starting, .running, .stopping:
                true
            case .stopped, .failed:
                false
            }
        }
    }

    private func componentPathEditingMessage(_ component: RuntimeComponent) -> String {
        if let operation = model.state.runtimeOperation {
            return "\(operation.description)，完成后才能修改路径。"
        }
        return switch component {
        case .cfst: "测速进行中，停止后才能修改路径。"
        case .mihomo: "本地代理运行中，停止后才能修改路径。"
        }
    }

    private func resolvedDisplayURL(for component: RuntimeComponent) -> URL? {
        let (preferredPath, managedURL, commandName): (String, URL?, String) =
            switch component {
            case .cfst:
                (model.state.preferences.cfstPath, model.state.runtimeStatus?.cfstURL, "cfst")
            case .mihomo:
                (
                    model.state.preferences.mihomoPath,
                    model.state.runtimeStatus?.mihomoIsReady == true
                        ? model.state.runtimeStatus?.mihomoURL
                        : nil,
                    "mihomo"
                )
            }

        var candidates: [URL] = []
        if !preferredPath.isEmpty {
            candidates.append(URL(fileURLWithPath: preferredPath))
        }
        if let managedURL {
            candidates.append(managedURL)
        }
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/\(commandName)"))
        candidates.append(URL(fileURLWithPath: "/usr/local/bin/\(commandName)"))
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(
                contentsOf: path.split(separator: ":").map {
                    URL(fileURLWithPath: String($0)).appendingPathComponent(commandName)
                })
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private var proxyImportDisabled: Bool {
        guard model.state.launchPhase == .ready else { return true }
        guard model.state.templateOperationPhase == .idle else { return true }
        guard model.switchingIP == nil else { return true }
        guard model.state.runtimeOperation == nil else { return true }
        return switch model.state.proxyCorePhase {
        case .validating, .starting, .running, .stopping:
            true
        case .stopped, .failed:
            false
        }
    }

    private var proxyImportBlockedMessage: String {
        switch model.state.launchPhase {
        case .idle, .loading:
            return "正在加载应用数据，完成后即可导入或编辑连接配置。"
        case .failed(let message):
            return "应用初始化失败：\(message)"
        case .ready:
            break
        }
        if let operation = model.state.runtimeOperation {
            return "\(operation.description)，完成后再导入或编辑连接配置。"
        }
        if model.switchingIP != nil {
            return "正在应用节点，完成后再导入或编辑连接配置。"
        }
        return "请先停止本地代理，再导入或编辑连接配置。"
    }

    private var templateOperationStatus: String? {
        switch model.state.templateOperationPhase {
        case .idle:
            nil
        case .importing:
            "正在导入代理配置，请稍候…"
        case .saving:
            "正在保存代理配置，请稍候…"
        }
    }

    private func chooseExecutable(_ component: RuntimeComponent) {
        let panel = NSOpenPanel()
        panel.title = "导入 \(component.displayName) 自定义可执行文件"
        panel.message = "该文件只覆盖 \(component.displayName) 的自动查找路径，不会复制或修改另一个组件。"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "使用此文件"
        if panel.runModal() == .OK {
            model.setCustomExecutable(component, url: panel.url)
        }
    }

    private func validateAndSaveExitIPEndpoint(_ value: String) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            exitIPEndpointError = "检测服务地址不能为空；可点击右侧按钮恢复默认地址。"
            return
        }
        guard
            let url = URL(string: normalized),
            ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
            url.host != nil
        else {
            exitIPEndpointError = "请输入有效的 HTTP 或 HTTPS 地址。"
            return
        }
        exitIPEndpointError = nil
        model.exitIPEndpoint = normalized
    }

    private func importProxyProfile() {
        let panel = NSOpenPanel()
        panel.title = "导入代理配置"
        panel.message = "选择 Mihomo YAML、分享配置，或可迁移的旧版 JSON。"
        panel.prompt = "导入"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "yaml"),
            UTType(filenameExtension: "yml"),
            .json,
        ].compactMap { $0 }
        if panel.runModal() == .OK, let url = panel.url {
            model.importProxyProfile(from: url)
        }
    }
}
