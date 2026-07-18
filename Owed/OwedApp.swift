import CoreSpotlight
import SwiftUI

/// Bridges BGTaskScheduler (off-main, process-lifetime) to the live
/// AppModel instance created by the SwiftUI `App` entry point.
@MainActor
enum FeedRefreshBridge {
    static var refresh: (() async -> Void)?

    nonisolated static func perform() async {
        let work = await MainActor.run { refresh }
        await work?()
    }
}

@main
struct OwedApp: App {
    /// Same instances Intents bind to in `init` — `@State` keeps Observation alive.
    @State private var model = AppRuntime.model
    @State private var store = AppRuntime.store
    @State private var navigation = AppRuntime.navigation
    @State private var claimsPrivacy = AppRuntime.claimsPrivacy
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Wire before first frame so cold-start Siri / Shortcuts don't race `.task`.
        AppRuntime.wireIntentBridge()
        // Must register before the app finishes launching.
        FeedBackgroundRefresh.register {
            await FeedRefreshBridge.perform()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(store)
                .environment(navigation)
                .environment(claimsPrivacy)
                .tint(T.green)
                .onChange(of: store.owned, initial: true) { _, owned in
                    model.lifetime = owned
                }
                .task {
                    AppRuntime.wireIntentBridge()
                    SpotlightIndexer.index(model.settlements)
                    FeedRefreshBridge.refresh = {
                        await AppRuntime.model.refreshFeed()
                    }
                    FeedBackgroundRefresh.schedule()
                }
                // Refresh on launch and on every return to foreground —
                // deadlines move on the order of days; background refresh
                // is the opportunistic backstop when the app stays closed.
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    await model.refreshFeed()
                    FeedBackgroundRefresh.schedule()
                }
                .onChange(of: scenePhase) { _, phase in
                    // Lock only on background — `.inactive` also covers the
                    // Face ID sheet itself and would re-lock mid-unlock.
                    if phase == .background {
                        claimsPrivacy.lock()
                    }
                }
                .onContinueUserActivity(CSSearchableItemActionType, perform: handleSpotlight)
        }
    }

    private func handleSpotlight(_ activity: NSUserActivity) {
        guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String
        else { return }
        // uniqueIdentifier is "owed.settlement.<id>"
        let prefix = "owed.settlement."
        guard id.hasPrefix(prefix) else { return }
        navigation.openSettlement(id: String(id.dropFirst(prefix.count)))
    }
}

struct RootView: View {
    @Environment(AppNavigation.self) private var navigation

    init() {
        // Opaque tab bar in the card color with a hairline top border,
        // matching the Expo tab bar.
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(T.card)
        appearance.shadowColor = UIColor(T.line)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        @Bindable var navigation = navigation
        TabView(selection: $navigation.selectedTab) {
            FindView()
                .tabItem { Label("Find", systemImage: "building.columns") }
                .tag(AppNavigation.Tab.find)
            ClaimsView()
                .tabItem { Label("My claims", systemImage: "tray.full") }
                .tag(AppNavigation.Tab.claims)
            AlertsView()
                .tabItem { Label("Alerts", systemImage: "bell") }
                .tag(AppNavigation.Tab.alerts)
        }
    }
}
