import Foundation
import Observation

/// Cross-surface destinations for Spotlight, App Intents, and tab chrome.
/// Keeps deep links out of individual views while remaining process-local
/// (no CloudKit — claim ledger and quiz answers never leave the device).
@Observable @MainActor
final class AppNavigation {
    enum Tab: Hashable {
        case find, claims, alerts
    }

    var selectedTab: Tab = .find
    /// Settlement to present in a detail sheet after a deep link lands.
    var pendingSettlementID: String?
    /// Optional Find filter to apply after an Intent (e.g. Closing soon).
    var pendingFindFilter: FeedFilter?

    func openSettlement(id: String) {
        pendingSettlementID = id
        selectedTab = .find
    }

    func showClosingSoon() {
        pendingFindFilter = .soon
        selectedTab = .find
    }

    func showClaims() {
        selectedTab = .claims
    }
}
