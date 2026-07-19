import SwiftUI
import ViaSixCore

@MainActor
struct NodesView: View {
    @Environment(AppModel.self) var model

    @SceneStorage("nodes.expandedParameterGroups") var expandedParameterGroupIDs = ParameterGroup.source.rawValue
    @SceneStorage("nodes.showsParameters") var showsParameters = true
    @SceneStorage("nodes.candidateSelection") var candidateSelection: SpeedTestResult.ID?
    @State var copiedCandidateIP: String?
    @State var reconnectConfirmationIP: String?
    @State var showsResetConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                pageHeader
                speedTestCard
                resultsCard
                parametersCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)
        }
        .scrollbarSafeContent()
        .onAppear {
            syncCandidateSelection()
        }
        .onChange(of: model.state.results) {
            syncCandidateSelection()
        }
        .onChange(of: model.state.preferences.selectedIP) {
            syncCandidateSelection()
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
        .confirmationDialog(
            "恢复默认测速设置？",
            isPresented: $showsResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("恢复默认设置", role: .destructive) {
                model.resetParameters()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("地址来源、测速模式、筛选条件和性能选项都会恢复默认值。")
        }
    }
}
