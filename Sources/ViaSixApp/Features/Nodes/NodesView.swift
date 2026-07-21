import SwiftUI
import ViaSixCore

@MainActor
struct NodesView: View {
    @Environment(AppModel.self) var model

    @SceneStorage("nodes.expandedParameterGroups") var expandedParameterGroupIDs = ParameterGroup.source.rawValue
    @SceneStorage("nodes.candidateSelection") var candidateSelection: SpeedTestResult.ID?
    @State var showsParameters = false
    @State var copiedCandidateIP: String?
    @State var reconnectConfirmationIP: String?
    @State var showsResetConfirmation = false
    @State var resultSortOrder: [NodeResultSortComparator] = []

    var body: some View {
        VStack(spacing: 0) {
            pageHeader

            VStack(alignment: .leading, spacing: VisualStyle.spacing12) {
                speedTestCard
                resultsCard
            }
            .padding(.horizontal, VisualStyle.pageHorizontalPadding)
            .padding(.vertical, VisualStyle.pageVerticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            syncCandidateSelection()
        }
        .onChange(of: model.state.results) {
            syncCandidateSelection()
        }
        .onChange(of: model.state.preferences.selectedIP) {
            syncCandidateSelection()
        }
        .sheet(isPresented: $showsParameters) {
            parametersSheet
        }
        .confirmationDialog(
            "应用节点并重新连接？",
            isPresented: reconnectConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("应用并重新连接") {
                guard let ip = reconnectConfirmationIP else { return }
                reconnectConfirmationIP = nil
                model.selectIP(ip)
            }
            Button("取消", role: .cancel) {
                reconnectConfirmationIP = nil
            }
        } message: {
            Text("本地代理会短暂中断，并使用所选节点重新连接。")
        }
    }
}
