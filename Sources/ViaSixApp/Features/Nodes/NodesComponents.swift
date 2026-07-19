import SwiftUI
import ViaSixCore

// MARK: - Supporting Views

enum ParameterGroup: Hashable {
    case source
    case mode
    case filter
    case performance
}

struct BannerMetric: View {
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

struct ParameterDisclosure<Content: View>: View {
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

struct SourceChoiceButton: View {
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

struct TestModeButton: View {
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

struct ParameterField<Content: View>: View {
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

struct ToggleSetting: View {
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

struct TopResultCard: View {
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

struct ResultMetric: View {
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

extension IPSourceMode {
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
