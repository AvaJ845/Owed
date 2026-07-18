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
    @State private var model = AppModel()
    @State private var store = StoreManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
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
                .tint(T.green)
                .onChange(of: store.owned, initial: true) { _, owned in
                    model.lifetime = owned
                }
                .task {
                    SpotlightIndexer.index(model.settlements)
                    FeedRefreshBridge.refresh = { [model] in
                        await model.refreshFeed()
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
        }
    }
}

struct RootView: View {
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
        TabView {
            FindView()
                .tabItem { Label("Find", systemImage: "building.columns") }
            ClaimsView()
                .tabItem { Label("My claims", systemImage: "tray.full") }
            AlertsView()
                .tabItem { Label("Alerts", systemImage: "bell") }
        }
    }
}
