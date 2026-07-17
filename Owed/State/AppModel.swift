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
    /// Turning true backfills deadline alerts for claims tracked before
    /// the purchase — the buyer's existing claims are exactly the ones
    /// they paid to be reminded about.
    var lifetime = false {
        didSet {
            guard lifetime, !oldValue else { return }
            let toSchedule = trackedSettlements
            Task {
                for s in toSchedule { await DeadlineAlerts.schedule(for: s) }
            }
        }
    }

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

    func untrack(_ s: Settlement) {
        tracked.remove(s.id)
        DeadlineAlerts.cancel(for: s.id)
    }

    var trackedSettlements: [Settlement] {
        settlements.filter { tracked.contains($0.id) }.sorted { $0.deadline < $1.deadline }
    }

    /// Hero number as an honest range — anchoring on best-case totals
    /// over-promises and earns 1-star reviews when checks arrive.
    var potentialRange: String {
        let lo = trackedSettlements.reduce(0) { $0 + $1.payoutLo }
        let hi = trackedSettlements.reduce(0) { $0 + $1.payoutHi }
        return lo == hi ? lo.usd : "\(lo.usd)–\(hi.usd)"
    }
}

// MARK: - Local deadline alerts (lifetime perk)

/// T-7 / T-1 reminders for tracked claims, scheduled locally so the perk
/// works before the push pipeline (PIPELINE.md §5) exists. Server push
/// replaces this for "new settlement" alerts; these local ones remain a
/// good offline backstop.
enum DeadlineAlerts {
    /// Requests permission only while undetermined. Callers reach this
    /// right after a purchase or a tracked claim, so the system prompt
    /// lands with context instead of appearing out of nowhere.
    static func ensureAuthorized() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    static func schedule(for s: Settlement) async {
        guard await ensureAuthorized() else { return }
        let center = UNUserNotificationCenter.current()
        let cal = Calendar.current

        for daysBefore in [7, 1] where s.daysLeft > daysBefore {
            // Anchor to the deadline date at 9am local — a relative
            // interval computed at track time drifts as the feed ages.
            guard let fireDay = cal.date(byAdding: .day, value: -daysBefore, to: s.deadline) else { continue }
            var comps = cal.dateComponents([.year, .month, .day], from: fireDay)
            comps.hour = 9

            let content = UNMutableNotificationContent()
            content.title = daysBefore == 1 ? "Last day tomorrow" : "One week left"
            content.body = "\(s.name) closes in \(daysBefore) day\(daysBefore == 1 ? "" : "s"). "
                + "Your claim isn't filed until the administrator confirms it."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "owed.deadline.\(s.id).t\(daysBefore)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            )
            try? await center.add(request)
        }
    }

    static func cancel(for settlementID: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [7, 1].map { "owed.deadline.\(settlementID).t\($0)" }
        )
    }
}
