import AppKit
import SwiftUI
import ViaSixCore

enum VisualStyle {
    static let accent = Color(red: 0.29, green: 0.55, blue: 0.96)
    static let positive = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)
    static let negative = Color(nsColor: .systemRed)
    static let pageBackgroundColor = Color(
        nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            if match == .darkAqua {
                return NSColor(srgbRed: 0.075, green: 0.082, blue: 0.105, alpha: 1)
            }
            return NSColor(srgbRed: 0.952, green: 0.958, blue: 0.97, alpha: 1)
        }
    )
    static let sidebarBackgroundColor = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.15, green: 0.16, blue: 0.205, alpha: 1)
                : NSColor(srgbRed: 0.975, green: 0.978, blue: 0.985, alpha: 1)
        }
    )
    static let surfaceColor = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.14, green: 0.15, blue: 0.19, alpha: 1)
                : NSColor.white
        }
    )
    static let elevatedSurfaceColor = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.18, green: 0.19, blue: 0.24, alpha: 1)
                : NSColor(srgbRed: 0.985, green: 0.988, blue: 0.995, alpha: 1)
        }
    )
    static let selectedSurfaceColor = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    static let subtleFill = Color(nsColor: .quaternaryLabelColor).opacity(0.12)
    static let surfaceBorder = Color(nsColor: .separatorColor).opacity(0.58)

    static let spacing4: CGFloat = 4
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing20: CGFloat = 20
    static let spacing24: CGFloat = 24

    static let radiusSmall: CGFloat = 7
    static let radiusMedium: CGFloat = 9
    static let radiusLarge: CGFloat = 12
    static let navigationRowHeight: CGFloat = 42
    static let settingsRowHeight: CGFloat = 52
    static let pageHeaderHeight: CGFloat = 60
    static let sidebarWidth: CGFloat = 224
    static let pageHorizontalPadding: CGFloat = 22
    static let pageVerticalPadding: CGFloat = 20
    static let controlHeight: CGFloat = 34
    static let iconButtonSize: CGFloat = 34
    static let disclosureHitTarget: CGFloat = 44
    static let scrollbarClearance: CGFloat = 14

    static let fastAnimation = Animation.easeOut(duration: 0.12)
    static let standardAnimation = Animation.easeInOut(duration: 0.18)
    static let deliberateAnimation = Animation.easeInOut(duration: 0.24)

    static var pageBackground: some View {
        pageBackgroundColor
    }
}

enum AppTone: Equatable, Sendable {
    case accent
    case positive
    case warning
    case negative
    case neutral

    var color: Color {
        switch self {
        case .accent: VisualStyle.accent
        case .positive: VisualStyle.positive
        case .warning: VisualStyle.warning
        case .negative: VisualStyle.negative
        case .neutral: .secondary
        }
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
                VisualStyle.surfaceColor,
                in: RoundedRectangle(
                    cornerRadius: VisualStyle.radiusMedium,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: VisualStyle.radiusMedium,
                    style: .continuous
                )
                .stroke(VisualStyle.surfaceBorder, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.045), radius: 3, y: 1)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardModifier())
    }

    /// Shared baseline for the main app surfaces. Typography intentionally follows
    /// the system Dynamic Type setting instead of forcing a single application size.
    func comfortableInterface() -> some View {
        controlSize(.regular)
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

// MARK: - Shared page components

struct AppPageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    private let trailing: Trailing

    init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: VisualStyle.spacing16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 21, weight: .bold))
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: VisualStyle.spacing16)
            trailing
        }
        .frame(minHeight: VisualStyle.pageHeaderHeight)
    }
}

extension AppPageHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) {
            EmptyView()
        }
    }
}

struct CardHeader<Trailing: View>: View {
    let title: String
    let systemImage: String
    let tone: AppTone
    private let trailing: Trailing

    init(
        _ title: String,
        systemImage: String,
        tone: AppTone = .accent,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tone = tone
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: VisualStyle.spacing12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tone.color)
                .frame(width: 34, height: 34)
                .background(
                    tone.color.opacity(0.11),
                    in: RoundedRectangle(
                        cornerRadius: VisualStyle.radiusSmall,
                        style: .continuous
                    )
                )

            Text(title)
                .font(.headline)
                .lineLimit(1)

            Spacer(minLength: VisualStyle.spacing12)
            trailing
        }
        .padding(.horizontal, VisualStyle.spacing16)
        .padding(.vertical, 11)
    }
}

extension CardHeader where Trailing == EmptyView {
    init(
        _ title: String,
        systemImage: String,
        tone: AppTone = .accent
    ) {
        self.init(title, systemImage: systemImage, tone: tone) {
            EmptyView()
        }
    }
}

struct SurfaceCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

struct StatusBadge: View {
    let title: String
    let tone: AppTone
    var systemImage: String?

    init(_ title: String, tone: AppTone = .neutral, systemImage: String? = nil) {
        self.title = title
        self.tone = tone
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            } else {
                Circle()
                    .fill(tone.color)
                    .frame(width: 6, height: 6)
            }

            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(tone.color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            tone.color.opacity(0.09),
            in: Capsule(style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

struct SettingRow<Trailing: View>: View {
    let title: String
    let detail: String?
    let systemImage: String?
    private let trailing: Trailing

    init(
        _ title: String,
        detail: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: VisualStyle.spacing12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.medium))

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: VisualStyle.spacing12)
            trailing
        }
        .frame(minHeight: VisualStyle.settingsRowHeight)
        .contentShape(Rectangle())
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
