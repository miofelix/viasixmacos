import AppKit
import SwiftUI
import ViaSixCore

enum VisualStyle {
    static let accent = Color(nsColor: .systemBlue)
    static let surfaceBorder = Color(nsColor: .separatorColor).opacity(0.72)
    static let controlHeight: CGFloat = 34
    static let iconButtonSize: CGFloat = 34
    static let disclosureHitTarget: CGFloat = 44
    static let scrollbarClearance: CGFloat = 14

    static var pageBackground: some View {
        Color(nsColor: .windowBackgroundColor)
    }
}

// MARK: - Proxy routing controls

/// Presentation metadata for the three routing modes exposed by the local
/// mixed proxy.  Keeping the wording here (rather than in the configuration
/// model) lets the persisted model remain a small, platform-neutral value
/// while the app can use friendly copy and SF Symbols.
extension ProxyRoutingMode {
    var appSystemImage: String {
        switch self {
        case .rule: "line.3.horizontal.decrease.circle"
        case .global: "globe"
        case .direct: "arrow.up.right"
        }
    }

    var appDescription: String {
        switch self {
        case .rule:
            "私有地址直连，其余流量通过代理。"
        case .global:
            "所有经过本地代理的流量都通过代理节点。"
        case .direct:
            "所有经过本地代理的流量都直接连接。"
        }
    }
}

/// A compact, equal-width mode selector inspired by Clash's mode card.  The
/// caller owns persistence through the binding; this view only presents and
/// changes the selected value, so it is also safe to use in a draft editor.
struct ProxyRoutingModePicker: View {
    @Binding var selection: ProxyRoutingMode
    var isDisabled = false
    var showsDescription = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(ProxyRoutingMode.allCases, id: \.rawValue) { mode in
                    Button {
                        selection = mode
                    } label: {
                        Label(mode.displayName, systemImage: mode.appSystemImage)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .buttonStyle(
                        ProxyRoutingModeButtonStyle(isSelected: selection == mode)
                    )
                    .disabled(isDisabled)
                    .accessibilityLabel("代理模式：\(mode.displayName)")
                    .accessibilityValue(selection == mode ? "当前" : "")
                }
            }
            .frame(maxWidth: .infinity)

            if showsDescription {
                Text(selection.appDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 7))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(VisualStyle.accent.opacity(0.38), lineWidth: 1)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("代理模式说明")
            }
        }
    }
}

private struct ProxyRoutingModeButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 38)
            .padding(.horizontal, 8)
            .background(
                isSelected ? VisualStyle.accent : Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isSelected ? VisualStyle.accent : VisualStyle.surfaceBorder,
                        lineWidth: 1
                    )
            }
            .shadow(
                color: isSelected ? VisualStyle.accent.opacity(0.22) : .clear,
                radius: 3,
                y: 1
            )
            .opacity(configuration.isPressed ? 0.76 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(VisualStyle.surfaceBorder, lineWidth: 1)
            }
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardModifier())
    }

    /// Shared baseline for the main app surfaces. Typography intentionally follows
    /// the system Dynamic Type setting instead of forcing a single application size.
    func comfortableInterface() -> some View {
        controlSize(.large)
    }

    func iconButtonHitTarget() -> some View {
        self
            .frame(width: VisualStyle.iconButtonSize, height: VisualStyle.iconButtonSize)
            .contentShape(Rectangle())
    }

    func scrollbarSafeContent() -> some View {
        contentMargins(.trailing, VisualStyle.scrollbarClearance, for: .scrollContent)
    }

    func horizontalScrollbarSafeContent() -> some View {
        contentMargins(.bottom, VisualStyle.scrollbarClearance, for: .scrollContent)
    }
}

/// A full-width disclosure control with a predictable hit target and explicit state semantics.
/// SwiftUI's compact disclosure indicator is visually appropriate for macOS, but is easy to
/// miss when it is the only clickable area. This control keeps the familiar indicator while
/// making the entire header interactive.
struct DisclosureControl<Label: View>: View {
    let title: String
    let summary: String?
    @Binding var isExpanded: Bool
    private let label: Label

    init(
        title: String,
        summary: String? = nil,
        isExpanded: Binding<Bool>,
        @ViewBuilder label: () -> Label
    ) {
        self.title = title
        self.summary = summary
        _isExpanded = isExpanded
        self.label = label()
    }

    var body: some View {
        let presentation = DisclosurePresentation(
            title: title,
            summary: summary,
            isExpanded: isExpanded
        )

        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                label

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 26, height: 26)
                    .background(.quaternary.opacity(0.72), in: Circle())
                    .accessibilityHidden(true)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: VisualStyle.disclosureHitTarget,
                alignment: .leading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(presentation.helpText)
        .accessibilityLabel(title)
        .accessibilityValue(presentation.accessibilityValue)
        .accessibilityHint(presentation.accessibilityHint)
    }
}

struct DisclosurePresentation: Equatable {
    let title: String
    let summary: String?
    let isExpanded: Bool

    var helpText: String {
        isExpanded ? "收起\(title)" : "展开\(title)"
    }

    var accessibilityValue: String {
        let state = isExpanded ? "已展开" : "已收起"
        guard let summary, !summary.isEmpty else { return state }
        return "\(state)，\(summary)"
    }

    var accessibilityHint: String {
        isExpanded ? "按下可收起" : "按下可展开"
    }
}
