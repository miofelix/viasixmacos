import Observation
import ViaSixCore

@MainActor
@Observable
final class AppRouter {
    private(set) var selectedSection: AppSection

    init(selectedSection: AppSection = .overview) {
        self.selectedSection = selectedSection
    }

    func select(_ section: AppSection) {
        selectedSection = section
    }
}
