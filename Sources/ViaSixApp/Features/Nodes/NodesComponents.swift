import SwiftUI
import ViaSixCore

enum ParameterGroup: Hashable {
    case source
    case mode
    case filter
    case performance
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
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: systemImage)
                        .foregroundStyle(VisualStyle.accent)
                        .frame(width: 20)

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

                    Spacer(minLength: 12)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, minHeight: VisualStyle.controlHeight, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityLabel(title)
            .accessibilityValue(isExpanded ? "已展开，\(subtitle)" : "已收起，\(subtitle)")

            if isExpanded {
                content
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .tint(VisualStyle.accent)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider()
        }
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
                .frame(minHeight: VisualStyle.controlHeight)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(label)
                .accessibilityHint(hint)

            Text(hint)
                .font(.caption)
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .padding(.vertical, 10)
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
}
