import BackgroundTasks
import Foundation
import os

/// Opportunistic feed refresh when the app isn't open (PIPELINE.md §3).
/// Foreground refresh remains the primary path; this is the offline
/// backstop so tracked-claim deadline moves don't wait on the next
/// cold launch. The fetch is still the public signed file — no
/// identifiers ride along.
enum FeedBackgroundRefresh {
    static let taskIdentifier = "AvaResearchLLC.Owed.refreshFeed"

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Owed", category: "bgrefresh"
    )

    /// Register once at process launch, before the scene becomes active.
    /// The handler captures a refresh closure so AppModel stays the
    /// source of truth for reconciliation.
    static func register(handler: @escaping @Sendable () async -> Void) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            // Always re-arm first — if we crash mid-refresh we still
            // want another attempt later.
            schedule()

            let work = Task {
                await handler()
            }
            refresh.expirationHandler = { work.cancel() }

            Task {
                await work.value
                refresh.setTaskCompleted(success: !work.isCancelled)
            }
        }
    }

    /// Ask the system for another refresh window. Earliest begin is on
    /// the order of hours — settlements change on days, not minutes.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            log.info("BGAppRefresh schedule skipped: \(String(describing: error))")
        }
    }
}
