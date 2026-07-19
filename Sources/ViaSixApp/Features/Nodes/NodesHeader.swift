import SwiftUI

extension NodesView {
    // MARK: - Header

    var summaryBanner: some View {
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

    var bannerCopy: some View {
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

    var bannerMetrics: some View {
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
}
