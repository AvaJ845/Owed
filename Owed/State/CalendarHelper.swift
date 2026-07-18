import EventKit
import Foundation

/// Writes a claim deadline into the user's calendar as an all-day event
/// with a day-before alarm. Uses iOS 17 write-only access, so Owed never
/// reads the user's calendar — consistent with the nothing-leaves-your-
/// phone posture.
enum CalendarHelper {
    static func addDeadline(for s: Settlement) async -> Bool {
        let store = EKEventStore()
        guard (try? await store.requestWriteOnlyAccessToEvents()) == true else { return false }

        let event = EKEvent(eventStore: store)
        event.title = "\(s.name) — claim deadline"
        event.notes = "File your claim before today ends: \(s.adminURL.absoluteString)\n\nTracked with Owed."
        event.startDate = s.deadline
        event.endDate = s.deadline
        event.isAllDay = true
        event.calendar = store.defaultCalendarForNewEvents
        event.addAlarm(EKAlarm(relativeOffset: -86_400))

        do {
            try store.save(event, span: .thisEvent)
            return true
        } catch {
            return false
        }
    }
}
