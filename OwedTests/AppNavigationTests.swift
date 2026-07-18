import Testing
@testable import Owed

@MainActor
struct AppNavigationTests {
    @Test func openSettlementSelectsFindAndStashesID() {
        let nav = AppNavigation()
        nav.selectedTab = .claims
        nav.openSettlement(id: "google-assistant-privacy")
        #expect(nav.selectedTab == .find)
        #expect(nav.pendingSettlementID == "google-assistant-privacy")
    }

    @Test func showClosingSoonAppliesSoonFilter() {
        let nav = AppNavigation()
        nav.showClosingSoon()
        #expect(nav.selectedTab == .find)
        #expect(nav.pendingFindFilter == .soon)
    }

    @Test func showClaimsSelectsClaimsTab() {
        let nav = AppNavigation()
        nav.showClaims()
        #expect(nav.selectedTab == .claims)
    }
}
