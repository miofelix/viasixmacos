import SwiftUI
import ViaSixCore

@MainActor
struct NodesView: View {
    @Environment(AppModel.self) var model

    @State var expandedGroups: Set<ParameterGroup> = [.source]
    @State var switchingIP: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summaryBanner
                parametersCard
                speedTestCard

                if !model.state.results.isEmpty {
                    topResultsSection
                }

                resultsCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)
        }
    }
}
