import Foundation

/// Process-lifetime ownership for models Intents / BG refresh can reach
/// before the first SwiftUI frame. `@State` in `OwedApp` holds the same
/// instances so views and Siri share one ledger — never a second AppModel.
@MainActor
enum AppRuntime {
    static let model = AppModel()
    static let store = StoreManager()
    static let navigation = AppNavigation()
    static let claimsPrivacy = ClaimsPrivacyGate()

    static func wireIntentBridge() {
        IntentBridge.model = model
        IntentBridge.navigation = navigation
    }
}
