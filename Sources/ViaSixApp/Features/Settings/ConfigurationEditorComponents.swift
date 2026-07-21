import SwiftUI

/// A consistent, native macOS section used by the guided server and local
/// proxy editors. The section owns presentation only; each editor retains its
/// own draft, validation, and persistence behavior.
struct ConfigurationSection<Content: View>: View {
    let title: String
    let systemImage: String
    let tone: AppTone
    private let content: Content

    init(
        _ title: String,
        systemImage: String,
        tone: AppTone = .accent,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tone = tone
        self.content = content()
    }

    var body: some View {
        SurfaceCard {
            CardHeader(title, systemImage: systemImage, tone: tone)
            Divider()
            VStack(alignment: .leading, spacing: VisualStyle.spacing12) {
                content
            }
            .padding(VisualStyle.spacing16)
        }
    }
}
