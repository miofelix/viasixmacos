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

    var speedTestStatusColor: Color {
        switch model.state.speedTest.phase {
        case .failed: .red
        case .running, .stopping: VisualStyle.accent
        case .idle: .secondary
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
        do {
            _ = try model.parameters.validated()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var canStartSpeedTest: Bool {
        model.state.launchPhase == .ready
            && model.state.runtimePhase != .installing
            && model.hasCfstExecutable
            && !model.isCfstBusy
            && parameterValidationMessage == nil
    }

    var speedTestReadinessMessage: String? {
        guard model.state.launchPhase == .ready, !model.hasCfstExecutable else { return nil }
        return "尚未找到 CloudflareSpeedTest，请在设置中安装或指定路径。"
    }

    var resultsSubtitle: String {
        guard !model.state.results.isEmpty else {
            return "完成测速后，候选节点会显示在这里"
        }

        switch model.state.speedTest.phase {
        case .running, .stopping:
            return "测速进行中，当前显示上次成功结果"
        case .failed:
            return "本次测速未完成，当前显示上次成功结果"
        case .idle:
            return "选择候选节点后，再点击“应用节点”"
        }
    }

    var applySelectionDisabled: Bool {
        guard let candidateSelection else { return true }
        if candidateSelection == model.state.preferences.selectedIP { return true }
        if model.switchingIP != nil || model.isCfstBusy { return true }

        switch model.state.xrayPhase {
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
        return model.state.isXrayRunning ? "应用并重连" : "应用节点"
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

    var resultsTableHeight: CGFloat {
        min(440, max(260, CGFloat(model.state.results.count * 30 + 48)))
    }

    // MARK: - Bindings and Actions

    func expansionBinding(for group: ParameterGroup) -> Binding<Bool> {
        Binding {
            expandedGroups.contains(group)
        } set: { isExpanded in
            withAnimation(.easeInOut(duration: 0.18)) {
                if isExpanded {
                    expandedGroups.insert(group)
                } else {
                    expandedGroups.remove(group)
                }
            }
        }
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
        if model.state.isXrayRunning {
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
