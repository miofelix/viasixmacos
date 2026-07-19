import AppKit
import SwiftUI

enum VisualStyle {
    static let accent = Color(nsColor: .systemBlue)
    static let surfaceBorder = Color(nsColor: .separatorColor).opacity(0.72)

    static var pageBackground: some View {
        Color(nsColor: .windowBackgroundColor)
    }
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(VisualStyle.surfaceBorder, lineWidth: 1)
            }
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardModifier())
    }
}
