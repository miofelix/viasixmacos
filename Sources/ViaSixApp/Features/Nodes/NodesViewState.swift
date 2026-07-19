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
            "线程 \(model.parameters.threads)"
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
        switch model.state.speedTest.phase {
        case .running, .stopping: true
        case .idle, .failed: false
        }
    }

    var isStopping: Bool {
        if case .stopping = model.state.speedTest.phase { return true }
        return false
    }

    var speedTestStatusText: String {
        switch model.state.speedTest.phase {
        case .idle:
            "准备就绪"
        case .running:
            model.state.speedTest.total > 0 ? "正在扫描并测试候选 IP" : "正在等待测速进度"
        case .stopping:
            "正在安全停止测速进程"
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

    var selectedResultBinding: Binding<SpeedTestResult.ID?> {
        Binding {
            let selectedIP = model.state.preferences.selectedIP
            guard model.state.results.contains(where: { $0.ip == selectedIP }) else { return nil }
            return selectedIP
        } set: { ip in
            guard let ip else { return }
            selectIP(ip)
        }
    }

    var nodeSelectionDisabled: Bool {
        if switchingIP != nil { return true }
        switch model.state.xrayPhase {
        case .validating, .starting, .stopping:
            return true
        case .stopped, .running, .failed:
            return false
        }
    }

    var sourceColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 145), spacing: 10)]
    }

    var fieldColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 220), spacing: 14)]
    }

    var resultColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 205), spacing: 12)]
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
        panel.message = "选择 CFST 可读取的纯文本或 CSV 文件"
        panel.prompt = "选择"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .commaSeparatedText]

        if panel.runModal() == .OK, let url = panel.url {
            model.selectIPFile(url)
        }
    }

    func selectIP(_ ip: String) {
        guard !nodeSelectionDisabled else { return }
        switchingIP = ip
        Task {
            await model.selectIP(ip)
            if switchingIP == ip {
                switchingIP = nil
            }
        }
    }

    func metric(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : value
    }
}
