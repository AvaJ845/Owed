import AppIntents
import Foundation

/// Siri / Shortcuts surface for Owed — glanceable actions without
/// uploading quiz answers or claim status.
///
/// Intent handlers hop to MainActor and mutate `AppNavigation` /
/// `AppModel` via the process-lifetime bridge set from `OwedApp`.

@MainActor
enum IntentBridge {
    static var model: AppModel?
    static var navigation: AppNavigation?

    static func requireModel() throws -> AppModel {
        guard let model else {
            throw IntentError.unavailable
        }
        return model
    }

    static func requireNavigation() throws -> AppNavigation {
        guard let navigation else {
            throw IntentError.unavailable
        }
        return navigation
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case unavailable
    case unknownSettlement

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .unavailable: "Owed isn’t ready yet. Open the app once, then try again."
        case .unknownSettlement: "That settlement isn’t in your feed."
        }
    }
}

// MARK: - Intents

struct ShowClosingSoonIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Settlements Closing Soon"
    static var description = IntentDescription(
        "Opens Owed’s Find tab filtered to settlements with a claim deadline in the next 30 days."
    )
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let nav = try IntentBridge.requireNavigation()
        nav.showClosingSoon()
        let model = try IntentBridge.requireModel()
        let count = model.settlements.filter { $0.daysLeft <= 30 && !$0.closed }.count
        return .result(
            dialog: IntentDialog(
                count == 0
                    ? "No settlements are closing in the next 30 days."
                    : "Showing \(count) settlement\(count == 1 ? "" : "s") closing soon."
            )
        )
    }
}

struct ShowMyClaimsIntent: AppIntent {
    static var title: LocalizedStringResource = "Show My Claims"
    static var description = IntentDescription("Opens the My claims tab in Owed.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try IntentBridge.requireNavigation().showClaims()
        let model = try IntentBridge.requireModel()
        let n = model.trackedSettlements.count
        return .result(
            dialog: IntentDialog(
                n == 0
                    ? "You aren’t tracking any claims yet."
                    : "You have \(n) tracked claim\(n == 1 ? "" : "s")."
            )
        )
    }
}

struct RefreshSettlementFeedIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Settlement Feed"
    static var description = IntentDescription(
        "Downloads the latest signed settlement feed and reconciles your tracked claims."
    )
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = try IntentBridge.requireModel()
        await model.refreshFeed()
        let n = model.settlements.filter { !$0.closed }.count
        return .result(
            dialog: IntentDialog("Feed updated. \(n) open settlement\(n == 1 ? "" : "s").")
        )
    }
}

struct OpenSettlementIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Settlement"
    static var description = IntentDescription("Opens a settlement’s detail sheet in Owed.")
    static var openAppWhenRun = true

    @Parameter(title: "Settlement")
    var settlement: SettlementEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let nav = try IntentBridge.requireNavigation()
        nav.openSettlement(id: settlement.id)
        return .result(dialog: IntentDialog("Opening \(settlement.name)."))
    }
}

// MARK: - Entity

struct SettlementEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Settlement")
    static var defaultQuery = SettlementEntityQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct SettlementEntityQuery: EntityQuery {
    func entities(for identifiers: [SettlementEntity.ID]) async throws -> [SettlementEntity] {
        let model = await MainActor.run { IntentBridge.model }
        guard let model else { return [] }
        return await MainActor.run {
            identifiers.compactMap { id in
                guard let s = model.settlements.first(where: { $0.id == id })
                        ?? model.trackedSettlements.first(where: { $0.id == id })
                else { return nil }
                return SettlementEntity(id: s.id, name: s.name)
            }
        }
    }

    func suggestedEntities() async throws -> [SettlementEntity] {
        let model = await MainActor.run { IntentBridge.model }
        guard let model else { return [] }
        return await MainActor.run {
            model.settlements
                .filter { !$0.closed }
                .sorted { $0.deadline < $1.deadline }
                .prefix(12)
                .map { SettlementEntity(id: $0.id, name: $0.name) }
        }
    }
}

extension SettlementEntityQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [SettlementEntity] {
        let needle = string.lowercased()
        let model = await MainActor.run { IntentBridge.model }
        guard let model else { return [] }
        return await MainActor.run {
            model.settlements
                .filter {
                    !$0.closed && (
                        $0.name.lowercased().contains(needle)
                        || $0.caseNo.lowercased().contains(needle)
                        || $0.id.lowercased().contains(needle)
                    )
                }
                .prefix(10)
                .map { SettlementEntity(id: $0.id, name: $0.name) }
        }
    }
}

// MARK: - App Shortcuts

struct OwedShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowClosingSoonIntent(),
            phrases: [
                "Show settlements closing soon in \(.applicationName)",
                "What’s closing soon in \(.applicationName)",
            ],
            shortTitle: "Closing Soon",
            systemImageName: "clock.badge.exclamationmark"
        )
        AppShortcut(
            intent: ShowMyClaimsIntent(),
            phrases: [
                "Show my claims in \(.applicationName)",
                "Open my claims in \(.applicationName)",
            ],
            shortTitle: "My Claims",
            systemImageName: "tray.full"
        )
        AppShortcut(
            intent: RefreshSettlementFeedIntent(),
            phrases: [
                "Refresh the settlement feed in \(.applicationName)",
                "Update settlements in \(.applicationName)",
            ],
            shortTitle: "Refresh Feed",
            systemImageName: "arrow.clockwise"
        )
    }
}
