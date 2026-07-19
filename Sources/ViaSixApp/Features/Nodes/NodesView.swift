import SwiftUI
import ViaSixCore

@MainActor
struct NodesView: View {
    @Environment(AppModel.self) var model

    @State var expandedGroups: Set<ParameterGroup> = [.source]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                pageHeader
                parametersCard
                speedTestCard
                resultsCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)
        }
    }
}
