import SwiftUI

extension NodesView {
    // MARK: - Header

    var pageHeader: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("节点优选")
                    .font(.title2.weight(.semibold))
                Text("测试候选 IP，按延迟与速度选择节点")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 4) {
                Text("当前节点")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(currentIPLabel)
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 2)
    }
}
