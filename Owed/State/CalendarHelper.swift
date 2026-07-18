import EventKit
import Foundation

/// Writes a claim deadline into the user's calendar as an all-day event
/// with a day-before alarm. Uses iOS 17 write-only access, so Owed never
/// reads the user's calendar — consistent with the nothing-leaves-your-
/// phone posture.
///
/// Event identifiers are stored so that *if* EventKit can resolve them
/// later (full calendar access, or a future OS change), deadline moves
/// update the existing event in place. Under write-only access today,
/// `event(withIdentifier:)` returns nil even for events we created —
/// reconciliation then clears the calendared flag and the Claims notice
/// offers a one-tap re-add. Trading the privacy promise for silent
/// updates is not worth it.
enum CalendarHelper {
    enum UpdateResult: Equatable {
        case updated
        case unavailable
        case failed
    }

    /// Creates the deadline event. Returns the EventKit identifier when
    /// the save succeeds so the model can persist it.
    static func addDeadline(for s: Settlement) async -> String? {
        let store = EKEventStore()
        guard (try? await store.requestWriteOnlyAccessToEvents()) == true else { return nil }

        let event = EKEvent(eventStore: store)
        apply(s, to: event)
        event.calendar = store.defaultCalendarForNewEvents
        event.addAlarm(EKAlarm(relativeOffset: -86_400))

        do {
            try store.save(event, span: .thisEvent)
            return event.eventIdentifier
        } catch {
            return nil
        }
    }

    /// Best-effort in-place update. Returns `.unavailable` under
    /// write-only access (the common case); callers fall back to the
    /// user-facing re-add flow.
    static func updateDeadline(for s: Settlement, eventIdentifier: String) async -> UpdateResult {
        let store = EKEventStore()
        // Prefer write-only; if the user previously granted full access
        // elsewhere, EventKit still honors the broader grant.
        guard (try? await store.requestWriteOnlyAccessToEvents()) == true else {
            return .failed
        }
        guard let event = store.event(withIdentifier: eventIdentifier) else {
            return .unavailable
        }
        apply(s, to: event)
        do {
            try store.save(event, span: .thisEvent)
            return .updated
        } catch {
            return .failed
        }
    }

    private static func apply(_ s: Settlement, to event: EKEvent) {
        event.title = "\(s.name) — claim deadline"
        event.notes = "File your claim before today ends: \(s.adminURL.absoluteString)\n\nTracked with Owed."
        event.startDate = s.deadline
        event.endDate = s.deadline
        event.isAllDay = true
    }
}
