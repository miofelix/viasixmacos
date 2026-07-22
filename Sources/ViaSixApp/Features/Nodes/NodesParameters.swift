import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ViaSixCore

extension NodesView {
    // MARK: - Parameters

    var parametersSheet: some View {
        VStack(spacing: 0) {
            parametersSheetHeader
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if isTesting {
                        Label(
                            "测速进行中，当前参数可以查看，但暂时不能修改。",
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, VisualStyle.spacing20)
                        .padding(.top, VisualStyle.spacing16)
                    } else if let parameterValidationMessage {
                        Label(
                            parameterValidationMessage,
                            systemImage: "exclamationmark.circle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(VisualStyle.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, VisualStyle.spacing20)
                        .padding(.top, VisualStyle.spacing16)
                    }

                    ParameterDisclosure(
                        title: "数据源",
                        subtitle: sourceSummary,
                        systemImage: "doc.text.magnifyingglass",
                        isExpanded: expansionBinding(for: .source)
                    ) {
                        sourceSettings
                            .disabled(isTesting)
                    }

                    ParameterDisclosure(
                        title: "测速模式",
                        subtitle: "\(model.parameters.httping ? "HTTPing" : "TCPing") · 端口 \(model.parameters.port)",
                        systemImage: "waveform.path.ecg",
                        isExpanded: expansionBinding(for: .mode)
                    ) {
                        modeSettings
                            .disabled(isTesting)
                    }

                    ParameterDisclosure(
                        title: "筛选条件",
                        subtitle:
                            "延迟 \(model.parameters.latencyLowerBound)–\(model.parameters.latencyUpperBound) ms · 丢包 ≤ \(model.parameters.lossRateUpperBound.formatted(.number.precision(.fractionLength(0...2))))",
                        systemImage: "line.3.horizontal.decrease.circle",
                        isExpanded: expansionBinding(for: .filter)
                    ) {
                        filterSettings
                            .disabled(isTesting)
                    }

                    ParameterDisclosure(
                        title: "性能调优",
                        subtitle:
                            "\(model.parameters.threads) 线程 · Ping \(model.parameters.pingCount) 次 · 下载 \(model.parameters.downloadCount) 个",
                        systemImage: "cpu",
                        isExpanded: expansionBinding(for: .performance)
                    ) {
                        performanceSettings
                            .disabled(isTesting)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollbarSafeContent()

            Divider()
            parametersSheetFooter
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 560, idealHeight: 680)
        .background(VisualStyle.pageBackground)
        .confirmationDialog(
            "恢复默认测速设置？",
            isPresented: $showsResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("恢复默认设置", role: .destructive) {
                model.resetParameters()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("地址来源、测速模式、筛选条件和性能选项都会恢复默认值。")
        }
    }

    private var parametersSheetHeader: some View {
        HStack(alignment: .top, spacing: VisualStyle.spacing16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("测速设置")
                    .font(.title3.weight(.semibold))
                Text("配置地址来源、测试方式、筛选条件和性能选项。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: VisualStyle.spacing16)

            Button {
                showsParameters = false
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .iconButtonHitTarget()
            .foregroundStyle(.secondary)
            .help("关闭测速设置")
            .accessibilityLabel("关闭测速设置")
        }
        .padding(VisualStyle.spacing20)
    }

    private var parametersSheetFooter: some View {
        HStack(spacing: VisualStyle.spacing12) {
            Button("恢复默认设置…", systemImage: "arrow.counterclockwise") {
                showsResetConfirmation = true
            }
            .disabled(isTesting)

            Spacer(minLength: VisualStyle.spacing16)

            Button("完成") {
                showsParameters = false
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, VisualStyle.spacing20)
        .padding(.vertical, VisualStyle.spacing16)
    }

    var sourceSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker(
                "地址来源",
                selection: Binding(
                    get: { model.ipSourceMode.rawValue },
                    set: { rawValue in
                        guard let mode = IPSourceMode(rawValue: rawValue) else { return }
                        chooseSource(mode)
                    }
                )
            ) {
                ForEach(availableSourceModes, id: \.rawValue) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch model.ipSourceMode {
            case .range:
                ParameterField(
                    label: "自定义 CIDR / IP",
                    hint: "多个 IPv6 地址或 CIDR 用英文逗号分隔，例如 2606:4700::/32"
                ) {
                    TextField("输入 IP、CIDR 或逗号分隔的组合", text: parameterBinding(\.ipRange))
                        .textFieldStyle(.roundedBorder)
                }

            case .file:
                ParameterField(
                    label: "自定义 IP 文件",
                    hint: "支持包含 IP 地址的纯文本或 CSV 列表"
                ) {
                    HStack(spacing: 10) {
                        Text(model.parameters.ipFile.isEmpty ? "尚未选择文件" : model.parameters.ipFile)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(model.parameters.ipFile.isEmpty ? .tertiary : .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 9)
                            .frame(minHeight: VisualStyle.controlHeight)
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

        }
    }

    private var availableSourceModes: [IPSourceMode] {
        IPSourceMode.allCases.filter { $0 != .ipv4 }
    }

    var modeSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker(
                "测速模式",
                selection: Binding(
                    get: { model.parameters.httping ? "http" : "tcp" },
                    set: { mode in
                        updateParameter(\.httping, to: mode == "http")
                    }
                )
            ) {
                Text("TCPing").tag("tcp")
                Text("HTTPing").tag("http")
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            LazyVGrid(columns: fieldColumns, alignment: .leading, spacing: 14) {
                ParameterField(label: "测速端口", hint: "1–65535，默认 443") {
                    TextField("443", value: parameterBinding(\.port), format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                }

                ParameterField(
                    label: "HTTP 状态码",
                    hint: "0 使用默认的 200 / 301 / 302"
                ) {
                    TextField("0", value: parameterBinding(\.httpingCode), format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .disabled(!model.parameters.httping)
                }

                ParameterField(
                    label: "测速 URL",
                    hint: "留空使用默认测速地址"
                ) {
                    TextField("https://your-domain.com/url", text: parameterBinding(\.url))
                        .textFieldStyle(.roundedBorder)
                }
                .disabled(model.parameters.disableDownload)
                .opacity(model.parameters.disableDownload ? 0.55 : 1)

                ParameterField(
                    label: "区域过滤",
                    hint: "IATA 代码，逗号分隔，如 HKG,NRT,SJC"
                ) {
                    TextField("留空表示全部区域", text: parameterBinding(\.colo))
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    var filterSettings: some View {
        LazyVGrid(columns: fieldColumns, alignment: .leading, spacing: 14) {
            ParameterField(label: "延迟上限", hint: "仅保留低于该值的 IP，单位 ms") {
                TextField(
                    "9999",
                    value: parameterBinding(\.latencyUpperBound),
                    format: .number.grouping(.never)
                )
                .textFieldStyle(.roundedBorder)
            }

            ParameterField(label: "延迟下限", hint: "过滤异常低延迟，单位 ms") {
                TextField(
                    "0",
                    value: parameterBinding(\.latencyLowerBound),
                    format: .number.grouping(.never)
                )
                .textFieldStyle(.roundedBorder)
            }

            ParameterField(label: "丢包率上限", hint: "0.00–1.00，0 表示不允许丢包") {
                TextField(
                    "1.00",
                    value: parameterBinding(\.lossRateUpperBound),
                    format: .number.precision(.fractionLength(0...2))
                )
                .textFieldStyle(.roundedBorder)
            }

            ParameterField(label: "下载速度下限", hint: "单位 MB/s，0 表示不限制") {
                TextField(
                    "0",
                    value: parameterBinding(\.speedLowerBound),
                    format: .number.precision(.fractionLength(0...2))
                )
                .textFieldStyle(.roundedBorder)
            }
            .disabled(model.parameters.disableDownload)
            .opacity(model.parameters.disableDownload ? 0.55 : 1)
        }
    }

    var performanceSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: fieldColumns, alignment: .leading, spacing: 14) {
                ParameterField(label: "延迟测速线程", hint: "1–1000，过高可能触发限制") {
                    TextField("200", value: parameterBinding(\.threads), format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                }

                ParameterField(label: "单 IP Ping 次数", hint: "1–100，默认 4") {
                    TextField("4", value: parameterBinding(\.pingCount), format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                }

                ParameterField(label: "下载测速数量", hint: "从延迟最低的候选节点开始") {
                    TextField(
                        "10",
                        value: parameterBinding(\.downloadCount),
                        format: .number.grouping(.never)
                    )
                    .textFieldStyle(.roundedBorder)
                }
                .disabled(model.parameters.disableDownload)
                .opacity(model.parameters.disableDownload ? 0.55 : 1)

                ParameterField(label: "单 IP 下载时长", hint: "单位秒，范围 1–3600") {
                    TextField(
                        "10",
                        value: parameterBinding(\.downloadTime),
                        format: .number.grouping(.never)
                    )
                    .textFieldStyle(.roundedBorder)
                }
                .disabled(model.parameters.disableDownload)
                .opacity(model.parameters.disableDownload ? 0.55 : 1)
            }

            LazyVGrid(columns: fieldColumns, alignment: .leading, spacing: 12) {
                ToggleSetting(
                    title: "禁用下载测速",
                    hint: "仅测试延迟，并按延迟排序。",
                    isOn: parameterBinding(\.disableDownload)
                )

                ToggleSetting(
                    title: "调试模式",
                    hint: "在“活动”中显示更多诊断信息。",
                    isOn: parameterBinding(\.debug)
                )
            }
        }
    }
}
