import AppKit
import SwiftUI

enum VisualStyle {
    static let accent = Color(red: 0.34, green: 0.43, blue: 0.96)
    static let secondaryAccent = Color(red: 0.62, green: 0.35, blue: 0.91)
    static let subtleSurface = Color(nsColor: .controlBackgroundColor).opacity(0.58)
    static let surfaceBorder = Color.primary.opacity(0.10)

    static var pageBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [
                    accent.opacity(0.10),
                    secondaryAccent.opacity(0.06),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    static let banner = LinearGradient(
        colors: [accent, secondaryAccent, Color(red: 0.91, green: 0.30, blue: 0.58)],
        startPoint: .leading,
        endPoint: .trailing
    )
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(VisualStyle.surfaceBorder, lineWidth: 1)
            }
            .shadow(color: VisualStyle.accent.opacity(0.10), radius: 18, y: 8)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardModifier())
    }
}
