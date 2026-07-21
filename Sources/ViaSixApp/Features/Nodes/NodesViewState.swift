import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ViaSixCore

extension NodesView {
    // MARK: - Derived State

    var currentIPLabel: String {
        let selectedIP = model.state.preferences.selectedIP
        return selectedIP.isEmpty ? "尚未选择" : selectedIP
    }

    var parameterSummary: String {
        var parts = [
            model.parameters.httping ? "HTTPing" : "TCPing",
            "端口 \(model.parameters.port)",
            "线程 \(model.parameters.threads)",
        ]
        if !model.parameters.colo.isEmpty {
            parts.append("区域 \(model.parameters.colo)")
        }
        return parts.joined(separator: " · ")
    }

    var sourceSummary: String {
        switch model.ipSourceMode {
        case .ipv6: "内置 IPv6 列表"
        case .ipv4: "内置 IPv4 列表"
        case .file:
            model.parameters.ipFile.isEmpty
                ? "尚未选择自定义文件"
                : URL(fileURLWithPath: model.parameters.ipFile).lastPathComponent
        case .range:
            model.parameters.ipRange.isEmpty ? "自定义 CIDR" : model.parameters.ipRange
        }
    }

    var isTesting: Bool {
        return switch model.state.speedTest.phase {
        case .running, .stopping: true
        case .idle, .failed: false
        }
    }

    var isCfstBusyElsewhere: Bool {
        model.isCfstBusy && !isTesting
    }

    var isStopping: Bool {
        if case .stopping = model.state.speedTest.phase { return true }
        return false
    }

    var speedTestStatusText: String {
        if isCfstBusyElsewhere {
            return "连接页正在测试当前节点"
        }
        if let operation = model.state.runtimeOperation {
            return operation.description
        }
        if model.isTemplateOperationBusy {
            return "正在处理代理配置"
        }
        if model.switchingIP != nil {
            return "正在应用节点"
        }
        return switch model.state.speedTest.phase {
        case .idle:
            model.state.results.isEmpty ? "准备就绪" : "上次结果可用"
        case .running:
            model.state.speedTest.total > 0 ? "正在扫描并测试候选 IP" : "正在等待测速进度"
        case .stopping:
            "正在停止测速"
        case .failed(let message):
            "测速失败：\(message)"
        }
    }

    var speedTestStatusTone: AppTone {
        if isCfstBusyElsewhere || model.state.runtimeOperation != nil {
            return .accent
        }
        if model.isTemplateOperationBusy || model.switchingIP != nil {
            return .warning
        }
        return switch model.state.speedTest.phase {
        case .failed: .negative
        case .running: .accent
        case .stopping: .warning
        case .idle: .neutral
        }
    }

    var speedTestStatusSystemImage: String {
        if isCfstBusyElsewhere { return "scope" }
        if model.state.runtimeOperation != nil { return "shippingbox" }
        if model.isTemplateOperationBusy { return "doc.badge.gearshape" }
        if model.switchingIP != nil { return "arrow.triangle.2.circlepath" }

        return switch model.state.speedTest.phase {
        case .idle: "gauge.with.dots.needle.67percent"
        case .running: "waveform.path.ecg"
        case .stopping: "hourglass"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var progressLabel: String {
        let progress = model.state.speedTest
        guard progress.total > 0 else { return "— / —" }
        return "\(progress.current) / \(progress.total)"
    }

    var progressPercentage: String {
        guard model.state.speedTest.total > 0 else { return "—" }
        return model.state.speedTest.fractionCompleted.formatted(
            .percent.precision(.fractionLength(0))
        )
    }

    var receivedOutputLabel: String {
        let bytes = model.state.speedTest.outputBytes
        guard bytes > 0 else { return "等待输出" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var progressAccessibilityValue: String {
        guard model.state.speedTest.total > 0 else {
            return isTesting ? "正在等待进度" : "尚未开始"
        }
        return "已完成 \(model.state.speedTest.current) 项，共 \(model.state.speedTest.total) 项，\(progressPercentage)"
    }

    var parameterValidationMessage: String? {
        guard model.state.launchPhase == .ready else { return nil }
        do {
            _ = try model.parameters.validated()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var speedTestUnavailableReason: String? {
        guard model.state.launchPhase == .ready else {
            return switch model.state.launchPhase {
            case .idle, .loading: "ViaSix 正在准备"
            case .failed: "应用初始化失败，请先重试"
            case .ready: nil
            }
        }
        if let operation = model.state.runtimeOperation {
            return operation.description
        }
        if model.isTemplateOperationBusy {
            return "代理配置操作进行中"
        }
        if model.switchingIP != nil {
            return "正在应用节点"
        }
        if isTesting {
            return isStopping ? "候选节点测速正在停止" : "候选节点测速正在进行"
        }
        if !model.hasCfstExecutable {
            return "请先安装 CloudflareSpeedTest"
        }
        if isCfstBusyElsewhere {
            return "当前节点测速正在进行"
        }
        if let parameterValidationMessage {
            return parameterValidationMessage
        }
        return nil
    }

    var canStartSpeedTest: Bool {
        speedTestUnavailableReason == nil
    }

    var speedTestStartHelp: String {
        speedTestUnavailableReason ?? "开始候选节点测速"
    }

    var speedTestReadinessMessage: String? {
        guard model.state.launchPhase == .ready, !model.hasCfstExecutable else { return nil }
        return "尚未找到 CloudflareSpeedTest，请在设置中安装或指定路径。"
    }

    var resultsSubtitle: String {
        guard !model.state.results.isEmpty else {
            return "按延迟、丢包率和速度比较测速结果"
        }

        switch model.state.speedTest.phase {
        case .running, .stopping:
            return "测速进行中，当前显示上次成功结果"
        case .failed:
            return "本次测速未完成，当前显示上次成功结果"
        case .idle:
            if !model.state.speedTestResultsAreCurrent {
                return "测速参数已变更，旧结果仅供参考，请重新测速"
            }
            return "选择候选节点后，再点击“应用节点”"
        }
    }

    var emptyResultsPresentation: NodeResultsEmptyPresentation {
        NodeResultsEmptyPresentation(
            speedTestPhase: model.state.speedTest.phase,
            runtimeOperationDescription: model.state.runtimeOperation?.description,
            isTemplateOperationBusy: model.isTemplateOperationBusy,
            isApplyingNode: model.switchingIP != nil,
            isCfstBusyElsewhere: isCfstBusyElsewhere,
            hasCfstExecutable: model.hasCfstExecutable,
            parameterValidationMessage: parameterValidationMessage
        )
    }

    var applySelectionDisabled: Bool {
        guard let candidateSelection else { return true }
        guard model.state.proxySupportsNodeSelection else { return true }
        guard model.state.speedTestResultsAreCurrent else { return true }
        guard case .idle = model.state.speedTest.phase else { return true }
        if candidateSelection == model.state.preferences.selectedIP { return true }
        if model.switchingIP != nil || model.isCfstBusy || model.isTemplateOperationBusy { return true }

        switch model.state.proxyCorePhase {
        case .validating, .starting, .stopping:
            return true
        case .stopped, .running, .failed:
            return false
        }
    }

    var applyButtonTitle: String {
        guard let candidateSelection else { return "应用节点" }
        if model.switchingIP == candidateSelection { return "正在应用" }
        if candidateSelection == model.state.preferences.selectedIP { return "已应用" }
        return model.state.isProxyRunning ? "应用并重连" : "应用节点"
    }

    var applySelectionHelp: String {
        guard let candidateSelection else { return "请先选择一个候选节点" }
        guard model.state.proxySupportsNodeSelection else {
            return "当前代理配置不支持直接应用测速节点"
        }
        guard model.state.speedTestResultsAreCurrent else { return "测速参数已变更，请重新测速" }
        switch model.state.speedTest.phase {
        case .running: return "候选节点测速正在进行"
        case .stopping: return "候选节点测速正在停止"
        case .failed: return "本次测速未完成，请重新测速"
        case .idle: break
        }
        if candidateSelection == model.state.preferences.selectedIP {
            return "所选节点已应用"
        }
        if model.switchingIP != nil { return "正在应用节点" }
        if model.isCfstBusy { return "测速进行中，暂时不能应用节点" }
        if model.isTemplateOperationBusy { return "代理配置操作进行中" }
        switch model.state.proxyCorePhase {
        case .validating: return "正在校验代理配置"
        case .starting: return "本地代理正在启动"
        case .stopping: return "本地代理正在停止"
        case .stopped, .running, .failed:
            return model.state.isProxyRunning ? "应用节点并重新连接" : "应用所选节点"
        }
    }

    var reconnectConfirmationPresented: Binding<Bool> {
        Binding {
            reconnectConfirmationIP != nil
        } set: { isPresented in
            if !isPresented {
                reconnectConfirmationIP = nil
            }
        }
    }

    var fieldColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 220), spacing: 14)]
    }

    // MARK: - Bindings and Actions

    func startSpeedTest() {
        guard canStartSpeedTest else { return }
        showsParameters = false
        model.startSpeedTest()
    }

    func expansionBinding(for group: ParameterGroup) -> Binding<Bool> {
        Binding {
            expandedParameterGroups.contains(group)
        } set: { isExpanded in
            withAnimation(.easeInOut(duration: 0.18)) {
                var groups = expandedParameterGroups
                if isExpanded {
                    groups.insert(group)
                } else {
                    groups.remove(group)
                }
                expandedParameterGroupIDs = ParameterGroup.allCases
                    .filter(groups.contains)
                    .map(\.rawValue)
                    .joined(separator: ",")
            }
        }
    }

    private var expandedParameterGroups: Set<ParameterGroup> {
        Set(
            expandedParameterGroupIDs
                .split(separator: ",")
                .compactMap { ParameterGroup(rawValue: String($0)) }
        )
    }

    func parameterBinding<Value>(
        _ keyPath: WritableKeyPath<SpeedTestParameters, Value>
    ) -> Binding<Value> {
        Binding {
            model.parameters[keyPath: keyPath]
        } set: { newValue in
            updateParameter(keyPath, to: newValue)
        }
    }

    func updateParameter<Value>(
        _ keyPath: WritableKeyPath<SpeedTestParameters, Value>,
        to newValue: Value
    ) {
        var parameters = model.parameters
        parameters[keyPath: keyPath] = newValue
        model.parameters = parameters
    }

    func chooseSource(_ mode: IPSourceMode) {
        if mode == .file {
            chooseIPFile()
        } else {
            model.selectIPSource(mode)
        }
    }

    func chooseIPFile() {
        let panel = NSOpenPanel()
        panel.title = "选择 IP 地址列表"
        panel.message = "选择包含 IP 地址的纯文本或 CSV 文件"
        panel.prompt = "选择"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .commaSeparatedText]

        if panel.runModal() == .OK, let url = panel.url {
            model.selectIPFile(url)
        }
    }

    func requestCandidateApplication() {
        guard let candidateSelection, !applySelectionDisabled else { return }
        if model.state.isProxyRunning {
            reconnectConfirmationIP = candidateSelection
        } else {
            model.selectIP(candidateSelection)
        }
    }

    func copyCandidateIP() {
        guard let candidateSelection else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(candidateSelection, forType: .string)
        copiedCandidateIP = candidateSelection

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if copiedCandidateIP == candidateSelection {
                copiedCandidateIP = nil
            }
        }
    }

    func syncCandidateSelection() {
        guard !model.state.results.isEmpty else {
            candidateSelection = nil
            return
        }

        if let candidateSelection,
            model.state.results.contains(where: { $0.id == candidateSelection })
        {
            return
        }

        let appliedIP = model.state.preferences.selectedIP
        candidateSelection =
            model.state.results.contains(where: { $0.id == appliedIP })
            ? appliedIP
            : model.state.results.first?.id
    }

    func metric(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : value
    }
}
