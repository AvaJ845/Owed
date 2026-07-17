import Foundation
import Observation
import UserNotifications

/// App state. Tracked claim ids persist across launches; the lifetime
/// entitlement itself is owned by StoreManager (StoreKit is the source
/// of truth), mirrored here for cheap view access.
@Observable
final class AppModel {
    private static let trackedKey = "owed.tracked"

    /// Settlement ids the user has started claims for.
    private(set) var tracked: Set<String> {
        didSet { UserDefaults.standard.set(Array(tracked), forKey: Self.trackedKey) }
    }

    /// Mirrored from StoreManager on launch and after purchase/restore.
    var lifetime = false

    /// The published feed. Mock today; production swaps this for the
    /// Owed API response (same shape — see PIPELINE.md §3).
    let settlements: [Settlement] = Settlement.mockFeed

    init() {
        tracked = Set(UserDefaults.standard.stringArray(forKey: Self.trackedKey) ?? [])
    }

    func isTracked(_ s: Settlement) -> Bool { tracked.contains(s.id) }

    func track(_ s: Settlement) {
        tracked.insert(s.id)
        if lifetime {
            Task { await DeadlineAlerts.schedule(for: s) }
        }
    }

    var trackedSettlements: [Settlement] {
        settlements.filter { tracked.contains($0.id) }.sorted { $0.daysLeft < $1.daysLeft }
    }

    /// Sum of best-case payouts across tracked claims — the hero number.
    var potentialTotal: Int {
        trackedSettlements.reduce(0) { $0 + $1.payoutHi }
    }
}

// MARK: - Local deadline alerts (lifetime perk)

/// T-7 / T-1 reminders for tracked claims, scheduled locally so the perk
/// works before the push pipeline (PIPELINE.md §5) exists. Server push
/// replaces this for "new settlement" alerts; these local ones remain a
/// good offline backstop.
enum DeadlineAlerts {
    static func schedule(for s: Settlement) async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return }

        for daysBefore in [7, 1] where s.daysLeft > daysBefore {
            let fireIn = TimeInterval((s.daysLeft - daysBefore) * 86_400)
            let content = UNMutableNotificationContent()
            content.title = daysBefore == 1 ? "Last day tomorrow" : "One week left"
            content.body = "\(s.name) closes in \(daysBefore) day\(daysBefore == 1 ? "" : "s"). "
                + "Your claim isn't filed until the administrator confirms it."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fireIn, repeats: false)
            let request = UNNotificationRequest(
                identifier: "owed.deadline.\(s.id).t\(daysBefore)",
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }
}
