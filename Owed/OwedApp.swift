import SwiftUI

@main
struct OwedApp: App {
    @State private var model = AppModel()
    @State private var store = StoreManager()

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
