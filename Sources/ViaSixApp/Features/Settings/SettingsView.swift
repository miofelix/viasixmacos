import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ViaSixCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showsCustomExecutables = false
    @State private var showsTemplateEditor = false
    @State private var showsServerEditor = false
    @State private var showsLocalProxyEditor = false
    @State private var exitIPEndpointDraft = ""
    @State private var exitIPEndpointError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("设置")
                        .font(.title2.weight(.semibold))
                    Text("代理配置、运行组件与应用数据")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                proxyConfigurationCard
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("运行组件", systemImage: "shippingbox")
                    .font(.headline)
                Spacer()
                runtimeBadge
            }

            componentRow(
                component: .cfst,
                url: resolvedDisplayURL(for: .cfst),
                ready: componentReady(.cfst)
            )
            Divider()
            componentRow(
                component: .xray,
                url: resolvedDisplayURL(for: .xray),
                ready: componentReady(.xray)
            )

            HStack {
                Button(runtimeInstallTitle, systemImage: "arrow.down.circle") {
                    model.installRuntime()
                }
                .disabled(runtimeActionsDisabled)

                Button("导入本地组件", systemImage: "square.and.arrow.down") {
                    importRuntime()
                }
                .disabled(runtimeActionsDisabled)

                Spacer()

                if model.state.runtimeOperation?.canCancel == true {
                    Button("取消", systemImage: "xmark.circle") {
                        model.cancelRuntimeOperation()
                    }
                }
            }

            runtimeOperationStatus

            if let issue = model.runtimeIntegrityIssue {
                Label(issue, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("自动安装会获取上游最新正式版本，并使用 Release 提供的 SHA-256 校验完整性。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let message = model.state.runtimeOperationError {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                DisclosureControl(
                    title: "自定义可执行文件",
                    summary: "指定开发版或自行构建的组件",
                    isExpanded: $showsCustomExecutables
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("自定义可执行文件")
                            .font(.subheadline.weight(.medium))
                        Text("指定开发版或自行构建的组件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if showsCustomExecutables {
                    VStack(alignment: .leading, spacing: 14) {
                        executablePicker(
                            title: "CFST 路径",
                            value: model.state.preferences.cfstPath,
                            component: .cfst
                        )
                        executablePicker(
                            title: "Xray 路径",
                            value: model.state.preferences.xrayPath,
                            component: .xray
                        )

                        Text("留空时使用 ViaSix 管理的组件，也会检查 Homebrew 与 PATH。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
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

    private var proxyConfigurationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("代理配置", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.headline)

            Text("填写服务器连接参数，并按需设置本机监听端口、UDP 和协议行为。VLESS、VMess、Trojan 和 Shadowsocks 连接可以直接使用表单。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text("本地端点")
                    .font(.caption.weight(.medium))
                Text(model.state.proxyEndpoint.displayAddress)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 10) {
                Button("配置服务器", systemImage: "server.rack") {
                    showsServerEditor = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    proxyImportDisabled
                        || !FileManager.default.fileExists(atPath: model.paths.serverConfig.path)
                )
                .help("填写服务器地址之外的远端连接参数")

                Button("本机代理设置", systemImage: "laptopcomputer.and.iphone") {
                    showsLocalProxyEditor = true
                }
                .disabled(proxyImportDisabled)

                Menu {
                    Button("高级 JSON 编辑器", systemImage: "curlybraces.square") {
                        showsTemplateEditor = true
                    }
                    .disabled(
                        proxyImportDisabled
                            || !FileManager.default.fileExists(atPath: model.paths.templateConfig.path)
                    )
                    Button("导入完整 Xray JSON…", systemImage: "square.and.arrow.down") {
                        importXrayTemplate()
                    }
                    .disabled(proxyImportDisabled)
                } label: {
                    Label("高级", systemImage: "ellipsis.circle")
                }
                .disabled(proxyImportDisabled)
            }

            if let templateOperationStatus {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(templateOperationStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(templateOperationStatus)
            } else if let error = model.state.templateOperationError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let issue = model.proxyConfigurationIssue {
                Label("代理配置尚未就绪：\(issue)", systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if proxyImportDisabled {
                Text(proxyImportBlockedMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("服务器参数和本机代理设置会保存在应用数据目录中。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .sheet(isPresented: $showsTemplateEditor) {
            XrayTemplateEditorView()
                .environment(model)
        }
        .sheet(isPresented: $showsServerEditor) {
            ServerConfigurationEditorView()
                .environment(model)
        }
        .sheet(isPresented: $showsLocalProxyEditor) {
            LocalProxySettingsView()
                .environment(model)
        }
    }

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("应用与数据", systemImage: "folder")
                .font(.headline)
            Text(model.paths.root.path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Button("打开数据目录", systemImage: "folder") {
                NSWorkspace.shared.open(model.paths.root)
            }

            Text("节点列表、测速结果、偏好设置和代理配置都保存在此目录。")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("出口 IP 检测服务")
                    .font(.caption.weight(.medium))
                HStack(spacing: 8) {
                    TextField(
                        AppMetadata.defaultExitIPEndpoint,
                        text: $exitIPEndpointDraft
                    )
                    .textFieldStyle(.roundedBorder)
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
                if let exitIPEndpointError {
                    Text(exitIPEndpointError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("自动模式使用此 HTTP/HTTPS 服务；强制 IPv4 或 IPv6 时使用对应的专用检测服务。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button("使用帮助", systemImage: "questionmark.circle") {
                    AppDocumentOpener.open(.userGuide)
                }
                Button("第三方许可", systemImage: "doc.plaintext") {
                    AppDocumentOpener.open(.thirdPartyNotices)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var runtimeBadge: some View {
        let (label, color): (String, Color) =
            if model.state.runtimeOperation != nil {
                ("操作中", VisualStyle.accent)
            } else if model.state.runtimeOperationError != nil {
                ("操作失败", .red)
            } else if model.runtimeIntegrityIssue != nil {
                ("需修复", .orange)
            } else {
                switch model.state.runtimePhase {
                case .checking: ("检查中", .secondary)
                case .missing: ("未就绪", .orange)
                case .ready: ("已就绪", .green)
                }
            }
        return HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var runtimeInstallTitle: String {
        if model.state.runtimeOperationError != nil {
            return model.hasCfstExecutable && model.hasXrayExecutable
                ? "重试更新"
                : "重试安装"
        }
        return model.hasCfstExecutable && model.hasXrayExecutable
            ? "重新安装组件"
            : "安装组件"
    }

    private func componentRow(
        component: RuntimeComponent,
        url: URL?,
        ready: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ready ? .green : .orange)
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
        }
    }

    private func executablePicker(
        title: String,
        value: String,
        component: RuntimeComponent
    ) -> some View {
        let editingDisabled = componentPathEditingDisabled(component)
        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
            HStack {
                TextField(
                    "自动查找",
                    text: Binding(
                        get: { value },
                        set: { newValue in
                            model.setCustomExecutable(
                                component,
                                url: newValue.isEmpty ? nil : URL(fileURLWithPath: newValue)
                            )
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(title)
                .disabled(editingDisabled)

                Button("选择…") {
                    chooseExecutable(component)
                }
                .disabled(editingDisabled)
                Button {
                    model.setCustomExecutable(component, url: nil)
                } label: {
                    Image(systemName: "xmark")
                }
                .iconButtonHitTarget()
                .help("清除自定义路径")
                .accessibilityLabel("清除\(title)")
                .disabled(value.isEmpty || editingDisabled)
            }
            if editingDisabled {
                Text(componentPathEditingMessage(component))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        case .xray:
            switch model.state.xrayPhase {
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
        case .xray: "本地代理运行中，停止后才能修改路径。"
        }
    }

    private func resolvedDisplayURL(for component: RuntimeComponent) -> URL? {
        let (preferredPath, managedURL, commandName): (String, URL?, String) =
            switch component {
            case .cfst:
                (model.state.preferences.cfstPath, model.state.runtimeStatus?.cfstURL, "cfst")
            case .xray:
                (
                    model.state.preferences.xrayPath,
                    model.state.runtimeStatus?.xrayIsReady == true
                        ? model.state.runtimeStatus?.xrayURL
                        : nil,
                    "xray"
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

    private var runtimeActionsDisabled: Bool {
        guard model.state.launchPhase == .ready else { return true }
        if model.state.runtimeOperation != nil
            || model.isTemplateOperationBusy
            || model.switchingIP != nil
        {
            return true
        }
        if model.isCfstBusy { return true }

        switch model.state.speedTest.phase {
        case .running, .stopping:
            return true
        case .idle, .failed:
            break
        }

        switch model.state.xrayPhase {
        case .validating, .starting, .running, .stopping:
            return true
        case .stopped, .failed:
            return false
        }
    }

    private var proxyImportDisabled: Bool {
        guard model.state.launchPhase == .ready else { return true }
        guard model.state.templateOperationPhase == .idle else { return true }
        guard model.switchingIP == nil else { return true }
        guard model.state.runtimeOperation == nil else { return true }
        return switch model.state.xrayPhase {
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
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
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

    private func importRuntime() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "导入"
        if panel.runModal() == .OK {
            model.importRuntime(from: panel.urls)
        }
    }

    private func importXrayTemplate() {
        let panel = NSOpenPanel()
        panel.title = "导入代理配置"
        panel.message = "选择包含“proxy”出站连接的 Xray JSON 配置。"
        panel.prompt = "导入"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            model.importXrayTemplate(from: url)
        }
    }
}
