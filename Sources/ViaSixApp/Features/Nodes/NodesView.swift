import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ViaSixCore

@MainActor
struct NodesView: View {
    @Environment(AppModel.self) private var model

    @State private var expandedGroups: Set<ParameterGroup> = [.source]
    @State private var switchingIP: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summaryBanner
                parametersCard
                speedTestCard

                if !model.state.results.isEmpty {
                    topResultsSection
                }

                resultsCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Header

    private var summaryBanner: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(.white.opacity(0.09))
                .frame(width: 210, height: 210)
                .blur(radius: 2)
                .offset(x: 58, y: -88)
                .accessibilityHidden(true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) {
                    bannerCopy
                    Spacer(minLength: 16)
                    bannerMetrics
                }

                VStack(alignment: .leading, spacing: 20) {
                    bannerCopy
                    bannerMetrics
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(26)
        }
        .foregroundStyle(.white)
        .background(VisualStyle.banner, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: VisualStyle.secondaryAccent.opacity(0.20), radius: 20, y: 9)
    }

    private var bannerCopy: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("节点优选", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))

            Text("从 Cloudflare 边缘网络挑出最快 IP")
                .font(.system(size: 25, weight: .bold, design: .rounded))

            Text("支持 IPv6、IPv4、自定义列表与 CIDR，结果可一键切换。")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.76))
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var bannerMetrics: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 18) {
                BannerMetric(value: "\(model.state.results.count)", label: "候选节点")

                Divider()
                    .overlay(.white.opacity(0.22))
                    .frame(height: 32)

                BannerMetric(
                    value: model.parameters.httping ? "HTTPing" : "TCPing",
                    label: "测速模式"
                )
            }

            Divider()
                .overlay(.white.opacity(0.20))

            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .foregroundStyle(.white.opacity(0.72))

                Text("当前节点")
                    .foregroundStyle(.white.opacity(0.68))

                Text(currentIPLabel)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.caption)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(minWidth: 280, alignment: .leading)
        .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
    }

    // MARK: - Parameters

    private var parametersCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.headline)
                    .foregroundStyle(VisualStyle.accent)
                    .frame(width: 38, height: 38)
                    .background(VisualStyle.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 3) {
                    Text("测速参数")
                        .font(.headline)

                    Text(parameterSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text("17 项")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VisualStyle.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(VisualStyle.accent.opacity(0.09), in: Capsule())

                Button {
                    model.resetParameters()
                } label: {
                    Label("重置", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .padding(18)

            Divider()

            VStack(spacing: 10) {
                ParameterDisclosure(
                    title: "数据源",
                    subtitle: sourceSummary,
                    systemImage: "doc.text.magnifyingglass",
                    isExpanded: expansionBinding(for: .source)
                ) {
                    sourceSettings
                }

                ParameterDisclosure(
                    title: "测速模式",
                    subtitle: "\(model.parameters.httping ? "HTTPing" : "TCPing") · 端口 \(model.parameters.port)",
                    systemImage: "waveform.path.ecg",
                    isExpanded: expansionBinding(for: .mode)
                ) {
                    modeSettings
                }

                ParameterDisclosure(
                    title: "筛选条件",
                    subtitle: "延迟 \(model.parameters.latencyLowerBound)–\(model.parameters.latencyUpperBound) ms · 丢包 ≤ \(model.parameters.lossRateUpperBound.formatted(.number.precision(.fractionLength(0...2))))",
                    systemImage: "line.3.horizontal.decrease.circle",
                    isExpanded: expansionBinding(for: .filter)
                ) {
                    filterSettings
                }

                ParameterDisclosure(
                    title: "性能调优",
                    subtitle: "\(model.parameters.threads) 线程 · Ping \(model.parameters.pingCount) 次 · 下载 \(model.parameters.downloadCount) 个",
                    systemImage: "cpu",
                    isExpanded: expansionBinding(for: .performance)
                ) {
                    performanceSettings
                }
            }
            .padding(14)
        }
        .cardStyle()
    }

    private var sourceSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: sourceColumns, spacing: 10) {
                ForEach(IPSourceMode.allCases, id: \.rawValue) { mode in
                    SourceChoiceButton(
                        mode: mode,
                        isSelected: model.ipSourceMode == mode
                    ) {
                        chooseSource(mode)
                    }
                }
            }

            switch model.ipSourceMode {
            case .range:
                ParameterField(
                    label: "自定义 CIDR / IP (-ip)",
                    hint: "多个地址用英文逗号分隔，例如 2606:4700::/32, 104.16.0.0/12"
                ) {
                    TextField("输入 IP、CIDR 或逗号分隔的组合", text: parameterBinding(\.ipRange))
                        .textFieldStyle(.roundedBorder)
                }

            case .file:
                ParameterField(
                    label: "自定义 IP 文件 (-f)",
                    hint: "支持 CFST 可读取的纯文本或 CSV 地址列表"
                ) {
                    HStack(spacing: 10) {
                        Text(model.parameters.ipFile.isEmpty ? "尚未选择文件" : model.parameters.ipFile)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(model.parameters.ipFile.isEmpty ? .tertiary : .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 9)
                            .frame(height: 27)
                            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))

                        Button("选择文件…") {
                            chooseIPFile()
                        }
                    }
                }

            case .ipv6, .ipv4:
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)

                    Text("使用内置列表")
                        .font(.caption.weight(.medium))

                    Text(model.parameters.ipFile)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            }

            ToggleSetting(
                title: "测速 IPv4 网段中的全部 IP (-allip)",
                hint: "默认每个 /24 网段随机选择一个 IP；开启后测速时间会显著增加。",
                isOn: parameterBinding(\.allIP)
            )
        }
    }

    private var modeSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                TestModeButton(
                    title: "TCPing",
                    subtitle: "快速、资源占用低",
                    isSelected: !model.parameters.httping
                ) {
                    updateParameter(\.httping, to: false)
                }

                TestModeButton(
                    title: "HTTPing",
                    subtitle: "可识别地区并过滤区域",
                    isSelected: model.parameters.httping
                ) {
                    updateParameter(\.httping, to: true)
                }
            }

            LazyVGrid(columns: fieldColumns, alignment: .leading, spacing: 14) {
                ParameterField(label: "测速端口 (-tp)", hint: "1–65535，默认 443") {
                    TextField("443", value: parameterBinding(\.port), format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                }

                ParameterField(
                    label: "HTTP 状态码 (-httping-code)",
                    hint: "0 使用默认的 200 / 301 / 302"
                ) {
                    TextField("0", value: parameterBinding(\.httpingCode), format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .disabled(!model.parameters.httping)
                }

                ParameterField(
                    label: "测速 URL (-url)",
                    hint: "留空使用 CFST 默认地址"
                ) {
                    TextField("https://your-domain.com/url", text: parameterBinding(\.url))
                        .textFieldStyle(.roundedBorder)
                }

                ParameterField(
                    label: "区域过滤 (-cfcolo)",
                    hint: "IATA 代码，逗号分隔，如 HKG,NRT,SJC"
                ) {
                    TextField("留空表示全部区域", text: parameterBinding(\.colo))
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var filterSettings: some View {
        LazyVGrid(columns: fieldColumns, alignment: .leading, spacing: 14) {
            ParameterField(label: "延迟上限 (-tl)", hint: "仅保留低于该值的 IP，单位 ms") {
                TextField(
                    "9999",
                    value: parameterBinding(\.latencyUpperBound),
                    format: .number.grouping(.never)
                )
                .textFieldStyle(.roundedBorder)
            }

            ParameterField(label: "延迟下限 (-tll)", hint: "过滤异常低延迟，单位 ms") {
                TextField(
                    "0",
                    value: parameterBinding(\.latencyLowerBound),
                    format: .number.grouping(.never)
                )
                .textFieldStyle(.roundedBorder)
            }

            ParameterField(label: "丢包率上限 (-tlr)", hint: "0.00–1.00，0 表示不允许丢包") {
                TextField(
                    "1.00",
                    value: parameterBinding(\.lossRateUpperBound),
                    format: .number.precision(.fractionLength(0...2))
                )
                .textFieldStyle(.roundedBorder)
            }

            ParameterField(label: "下载速度下限 (-sl)", hint: "单位 MB/s，0 表示不限制") {
                TextField(
                    "0",
                    value: parameterBinding(\.speedLowerBound),
                    format: .number.precision(.fractionLength(0...2))
                )
                .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var performanceSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: fieldColumns, alignment: .leading, spacing: 14) {
                ParameterField(label: "延迟测速线程 (-n)", hint: "1–1000，过高可能触发限制") {
                    TextField("200", value: parameterBinding(\.threads), format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                }

                ParameterField(label: "单 IP Ping 次数 (-t)", hint: "1–100，默认 4") {
                    TextField("4", value: parameterBinding(\.pingCount), format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                }

                ParameterField(label: "下载测速数量 (-dn)", hint: "从延迟最低的候选节点开始") {
                    TextField(
                        "10",
                        value: parameterBinding(\.downloadCount),
                        format: .number.grouping(.never)
                    )
                    .textFieldStyle(.roundedBorder)
                }

                ParameterField(label: "单 IP 下载时长 (-dt)", hint: "单位秒，范围 1–3600") {
                    TextField(
                        "10",
                        value: parameterBinding(\.downloadTime),
                        format: .number.grouping(.never)
                    )
                    .textFieldStyle(.roundedBorder)
                }
            }

            LazyVGrid(columns: fieldColumns, alignment: .leading, spacing: 12) {
                ToggleSetting(
                    title: "禁用下载测速 (-dd)",
                    hint: "仅测试延迟，并按延迟排序。",
                    isOn: parameterBinding(\.disableDownload)
                )

                ToggleSetting(
                    title: "调试模式 (-debug)",
                    hint: "将更多诊断信息写入运行日志。",
                    isOn: parameterBinding(\.debug)
                )
            }
        }
    }

    // MARK: - Test and Results

    private var speedTestCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.title3)
                    .foregroundStyle(VisualStyle.secondaryAccent)
                    .frame(width: 40, height: 40)
                    .background(
                        VisualStyle.secondaryAccent.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 12)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("IP 测速")
                        .font(.headline)

                    Text(speedTestStatusText)
                        .font(.caption)
                        .foregroundStyle(speedTestStatusColor)
                }

                Spacer()

                if isTesting {
                    Button(role: .destructive) {
                        model.stopSpeedTest()
                    } label: {
                        Label(isStopping ? "正在停止" : "停止", systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isStopping)
                } else {
                    Button {
                        model.startSpeedTest()
                    } label: {
                        Label("开始测速", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(VisualStyle.accent)
                    .disabled(
                        model.state.launchPhase != .ready
                            || model.state.runtimePhase == .installing
                    )
                }
            }

            Group {
                if isTesting && model.state.speedTest.total == 0 {
                    ProgressView()
                        .progressViewStyle(.linear)
                } else {
                    ProgressView(value: model.state.speedTest.fractionCompleted)
                        .progressViewStyle(.linear)
                        .tint(VisualStyle.accent)
                }
            }
            .accessibilityLabel("测速进度")
            .accessibilityValue(progressAccessibilityValue)

            HStack(spacing: 16) {
                Label(progressLabel, systemImage: "number")
                Label(progressPercentage, systemImage: "percent")
                Spacer()
                Label(receivedOutputLabel, systemImage: "arrow.down.circle")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .cardStyle()
    }

    private var topResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("最快节点")
                        .font(.headline)
                    Text("按结果顺序展示前三名，点击即可切换")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            LazyVGrid(columns: resultColumns, alignment: .leading, spacing: 12) {
                ForEach(Array(model.state.results.prefix(3).enumerated()), id: \.element.id) { index, result in
                    TopResultCard(
                        rank: index + 1,
                        result: result,
                        isSelected: result.ip == model.state.preferences.selectedIP,
                        isSwitching: switchingIP == result.ip
                    ) {
                        selectIP(result.ip)
                    }
                }
            }
            .disabled(nodeSelectionDisabled)
        }
    }

    private var resultsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("候选节点")
                        .font(.headline)
                    Text("点击任意一行切换节点，完整测速数据可滚动查看")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(model.state.results.count) 条")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)

                if switchingIP != nil {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在切换节点")
                }
            }

            ZStack {
                Table(model.state.results, selection: selectedResultBinding) {
                    TableColumn("IP") { result in
                        HStack(spacing: 7) {
                            if result.ip == model.state.preferences.selectedIP {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(VisualStyle.accent)
                            }

                            Text(result.ip)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .width(min: 150, ideal: 220)

                    TableColumn("已发") { result in
                        Text(metric(result.sent))
                            .monospacedDigit()
                    }
                    .width(min: 42, ideal: 52)

                    TableColumn("已收") { result in
                        Text(metric(result.received))
                            .monospacedDigit()
                    }
                    .width(min: 42, ideal: 52)

                    TableColumn("丢包") { result in
                        Text(metric(result.loss))
                            .monospacedDigit()
                    }
                    .width(min: 54, ideal: 66)

                    TableColumn("延迟 (ms)") { result in
                        Text(metric(result.latency))
                            .monospacedDigit()
                    }
                    .width(min: 68, ideal: 82)

                    TableColumn("速度 (MB/s)") { result in
                        Text(metric(result.speed))
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                    .width(min: 78, ideal: 94)

                    TableColumn("区域") { result in
                        Text(metric(result.region))
                    }
                    .width(min: 54, ideal: 72)
                }
                .frame(height: resultsTableHeight)
                .disabled(nodeSelectionDisabled)
                .accessibilityLabel("候选节点")

                if model.state.results.isEmpty {
                    ContentUnavailableView(
                        "暂无测速结果",
                        systemImage: "network.slash",
                        description: Text("配置参数后点击“开始测速”生成候选节点。")
                    )
                    .allowsHitTesting(false)
                }
            }
        }
        .padding(18)
        .cardStyle()
    }

    // MARK: - Derived State

    private var currentIPLabel: String {
        let selectedIP = model.state.preferences.selectedIP
        return selectedIP.isEmpty ? "尚未选择" : selectedIP
    }

    private var parameterSummary: String {
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

    private var sourceSummary: String {
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

    private var isTesting: Bool {
        switch model.state.speedTest.phase {
        case .running, .stopping: true
        case .idle, .failed: false
        }
    }

    private var isStopping: Bool {
        if case .stopping = model.state.speedTest.phase { return true }
        return false
    }

    private var speedTestStatusText: String {
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

    private var speedTestStatusColor: Color {
        switch model.state.speedTest.phase {
        case .failed: .red
        case .running, .stopping: VisualStyle.accent
        case .idle: .secondary
        }
    }

    private var progressLabel: String {
        let progress = model.state.speedTest
        guard progress.total > 0 else { return "— / —" }
        return "\(progress.current) / \(progress.total)"
    }

    private var progressPercentage: String {
        guard model.state.speedTest.total > 0 else { return "—" }
        return model.state.speedTest.fractionCompleted.formatted(
            .percent.precision(.fractionLength(0))
        )
    }

    private var receivedOutputLabel: String {
        let bytes = model.state.speedTest.outputBytes
        guard bytes > 0 else { return "等待输出" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var progressAccessibilityValue: String {
        guard model.state.speedTest.total > 0 else {
            return isTesting ? "正在等待进度" : "尚未开始"
        }
        return "已完成 \(model.state.speedTest.current) 项，共 \(model.state.speedTest.total) 项，\(progressPercentage)"
    }

    private var selectedResultBinding: Binding<SpeedTestResult.ID?> {
        Binding {
            let selectedIP = model.state.preferences.selectedIP
            guard model.state.results.contains(where: { $0.ip == selectedIP }) else { return nil }
            return selectedIP
        } set: { ip in
            guard let ip else { return }
            selectIP(ip)
        }
    }

    private var nodeSelectionDisabled: Bool {
        if switchingIP != nil { return true }
        switch model.state.xrayPhase {
        case .validating, .starting, .stopping:
            return true
        case .stopped, .running, .failed:
            return false
        }
    }

    private var sourceColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 145), spacing: 10)]
    }

    private var fieldColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 220), spacing: 14)]
    }

    private var resultColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 205), spacing: 12)]
    }

    private var resultsTableHeight: CGFloat {
        min(440, max(260, CGFloat(model.state.results.count * 30 + 48)))
    }

    // MARK: - Bindings and Actions

    private func expansionBinding(for group: ParameterGroup) -> Binding<Bool> {
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

    private func parameterBinding<Value>(
        _ keyPath: WritableKeyPath<SpeedTestParameters, Value>
    ) -> Binding<Value> {
        Binding {
            model.parameters[keyPath: keyPath]
        } set: { newValue in
            updateParameter(keyPath, to: newValue)
        }
    }

    private func updateParameter<Value>(
        _ keyPath: WritableKeyPath<SpeedTestParameters, Value>,
        to newValue: Value
    ) {
        var parameters = model.parameters
        parameters[keyPath: keyPath] = newValue
        model.parameters = parameters
    }

    private func chooseSource(_ mode: IPSourceMode) {
        if mode == .file {
            chooseIPFile()
        } else {
            model.selectIPSource(mode)
        }
    }

    private func chooseIPFile() {
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

    private func selectIP(_ ip: String) {
        guard !nodeSelectionDisabled else { return }
        switchingIP = ip
        Task {
            await model.selectIP(ip)
            if switchingIP == ip {
                switchingIP = nil
            }
        }
    }

    private func metric(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : value
    }
}

// MARK: - Supporting Views

private enum ParameterGroup: Hashable {
    case source
    case mode
    case filter
    case performance
}

private struct BannerMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.66))
        }
    }
}

private struct ParameterDisclosure<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var isExpanded: Bool
    private let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        _isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
                .padding(.top, 16)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: systemImage)
                    .foregroundStyle(VisualStyle.accent)
                    .frame(width: 28, height: 28)
                    .background(VisualStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .tint(VisualStyle.accent)
        .padding(14)
        .background(VisualStyle.subtleSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(VisualStyle.surfaceBorder, lineWidth: 1)
        }
    }
}

private struct SourceChoiceButton: View {
    let mode: IPSourceMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: mode.systemImage)
                        .font(.headline)
                        .foregroundStyle(isSelected ? .white : VisualStyle.accent)

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white)
                    }
                }

                Text(mode.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : .primary)

                Text(mode.subtitle)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white.opacity(0.76) : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 102, alignment: .leading)
            .background {
                if isSelected {
                    VisualStyle.banner
                } else {
                    VisualStyle.subtleSurface
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(
                        isSelected ? Color.white.opacity(0.25) : Color.primary.opacity(0.06),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct TestModeButton: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(
                        isSelected ? VisualStyle.accent : Color.secondary.opacity(0.45)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? VisualStyle.accent.opacity(0.10) : VisualStyle.subtleSurface,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? VisualStyle.accent.opacity(0.38) : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ParameterField<Content: View>: View {
    let label: String
    let hint: String
    private let content: Content

    init(label: String, hint: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.hint = hint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)

            content

            Text(hint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ToggleSetting: View {
    let title: String
    let hint: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .padding(12)
        .background(VisualStyle.subtleSurface, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct TopResultCard: View {
    let rank: Int
    let result: SpeedTestResult
    let isSelected: Bool
    let isSwitching: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Label("TOP \(rank)", systemImage: rank == 1 ? "trophy.fill" : "medal.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(rankColor)

                    Spacer()

                    if isSwitching {
                        ProgressView()
                            .controlSize(.small)
                    } else if isSelected {
                        Label("当前", systemImage: "checkmark.circle.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(VisualStyle.accent)
                    } else {
                        Text(result.region.isEmpty ? "—" : result.region)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.quaternary.opacity(0.65), in: Capsule())
                    }
                }

                Text(result.ip)
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(alignment: .bottom) {
                    ResultMetric(value: result.speed, unit: "MB/s", title: "下载速度", prominent: true)
                    Spacer()
                    ResultMetric(value: result.latency, unit: "ms", title: "延迟", prominent: false)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(
                        isSelected ? VisualStyle.accent.opacity(0.58) : VisualStyle.surfaceBorder,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .shadow(color: VisualStyle.accent.opacity(isSelected ? 0.14 : 0.07), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .disabled(isSwitching)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var rankColor: Color {
        switch rank {
        case 1: .orange
        case 2: .secondary
        default: .brown
        }
    }
}

private struct ResultMetric: View {
    let value: String
    let unit: String
    let title: String
    let prominent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value.isEmpty ? "—" : value)
                    .font(prominent ? .title3.weight(.bold) : .headline.weight(.semibold))
                    .monospacedDigit()
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private extension IPSourceMode {
    var title: String {
        switch self {
        case .ipv6: "IPv6"
        case .ipv4: "IPv4"
        case .file: "自定义文件"
        case .range: "自定义 CIDR"
        }
    }

    var subtitle: String {
        switch self {
        case .ipv6: "使用应用内置 IPv6 网段"
        case .ipv4: "使用应用内置 IPv4 网段"
        case .file: "从本地导入地址列表"
        case .range: "直接输入 IP 或网段"
        }
    }

    var systemImage: String {
        switch self {
        case .ipv6: "network"
        case .ipv4: "globe.asia.australia"
        case .file: "doc.text"
        case .range: "point.3.connected.trianglepath.dotted"
        }
    }
}
