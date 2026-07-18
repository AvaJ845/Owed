import Foundation
import Testing
@testable import Owed

/// Step 3 behavior: what happens to tracked claims when the feed moves
/// underneath them. These are the tests that gate shipping live data.
@MainActor
struct ReconciliationTests {

    /// Isolated suite so parallel Swift Testing cases can't share state
    /// through `UserDefaults.standard`.
    private func makeModel() -> AppModel {
        AppModel(defaults: UserDefaults(suiteName: "owed.tests.\(UUID().uuidString)")!)
    }

    private func makeFeed(_ records: [(id: String, deadline: String)]) throws -> SettlementFeed {
        let body = records.map { r in
            """
            {
              "id": "\(r.id)",
              "caseNo": "No. 1:26-cv-0001",
              "name": "Settlement \(r.id)",
              "category": "Test",
              "payoutLo": 10,
              "payoutHi": 100,
              "payoutTerms": "per claimant",
              "deadline": "\(r.deadline)",
              "receiptRequired": false,
              "adminURL": "https://example-administrator.com/\(r.id)",
              "eligibility": ["I qualify"],
              "matchKeys": ["streaming"],
              "verifiedAt": "2026-07-01"
            }
            """
        }.joined(separator: ",")
        return try SettlementFeed.decode(Data("""
        {
          "schemaVersion": 1,
          "generatedAt": "2026-07-18T00:00:00Z",
          "settlements": [\(body)]
        }
        """.utf8))
    }

    @Test func removedSettlementSurvivesForTrackedClaim() throws {
        let model = makeModel()
        let first = try makeFeed([(id: "keep", deadline: "2027-03-01"), (id: "gone", deadline: "2027-04-01")])
        model.reconcile(with: first)

        let gone = model.settlements.first { $0.id == "gone" }!
        model.track(gone)
        model.recordPayment(gone, amount: 32)

        let second = try makeFeed([(id: "keep", deadline: "2027-03-01")])
        model.reconcile(with: second)

        #expect(model.settlements.map(\.id) == ["keep"])
        #expect(model.trackedSettlements.map(\.id) == ["gone"])
        #expect(model.status(for: gone) == .paid(32))
    }

    @Test func deadlineChangeUpdatesSnapshotAndRaisesNotice() throws {
        let model = makeModel()
        let first = try makeFeed([(id: "s", deadline: "2027-03-01")])
        model.reconcile(with: first)

        let s = model.settlements[0]
        model.track(s)

        model.reconcile(with: try makeFeed([(id: "s", deadline: "2027-05-01")]))

        #expect(model.trackedSettlements[0].deadline == FeedDay.date(from: "2027-05-01"))
        #expect(model.deadlineNotices.count == 1)
        let notice = model.deadlineNotices[0]
        #expect(notice.settlementID == "s")
        #expect(notice.oldDeadline == FeedDay.date(from: "2027-03-01"))
        #expect(notice.newDeadline == FeedDay.date(from: "2027-05-01"))
    }

    @Test func deadlineChangeClearsLegacyCalendaredWithoutEventID() throws {
        let suiteName = "owed.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.set(["s"], forKey: "owed.calendared")

        let model = AppModel(defaults: suite)
        model.reconcile(with: try makeFeed([(id: "s", deadline: "2027-03-01")]))
        model.track(model.settlements[0])
        #expect(model.calendared.contains("s"))
        #expect(model.calendarEventIDs["s"] == nil)

        model.reconcile(with: try makeFeed([(id: "s", deadline: "2027-05-01")]))
        #expect(!model.calendared.contains("s"))
    }

    @Test func markCalendaredPersistsEventIdentifier() throws {
        let suiteName = "owed.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        let model = AppModel(defaults: suite)
        model.reconcile(with: try makeFeed([(id: "s", deadline: "2027-03-01")]))
        let s = model.settlements[0]
        model.track(s)
        model.markCalendared(s, eventIdentifier: "ek-abc")

        let relaunched = AppModel(defaults: suite)
        #expect(relaunched.calendared.contains("s"))
        #expect(relaunched.calendarEventIDs["s"] == "ek-abc")
    }

    @Test func unchangedDeadlineRaisesNoNotice() throws {
        let model = makeModel()
        let feed = try makeFeed([(id: "s", deadline: "2027-03-01")])
        model.reconcile(with: feed)
        model.track(model.settlements[0])

        model.reconcile(with: try makeFeed([(id: "s", deadline: "2027-03-01")]))
        #expect(model.deadlineNotices.isEmpty)
    }

    @Test func repeatDeadlineChangeReplacesOlderNotice() throws {
        let model = makeModel()
        model.reconcile(with: try makeFeed([(id: "s", deadline: "2027-03-01")]))
        model.track(model.settlements[0])

        model.reconcile(with: try makeFeed([(id: "s", deadline: "2027-04-01")]))
        model.reconcile(with: try makeFeed([(id: "s", deadline: "2027-05-01")]))

        #expect(model.deadlineNotices.count == 1)
        #expect(model.deadlineNotices[0].newDeadline == FeedDay.date(from: "2027-05-01"))
    }

    @Test func untrackDropsSnapshotPayoutAndNotices() throws {
        let model = makeModel()
        model.reconcile(with: try makeFeed([(id: "s", deadline: "2027-03-01")]))
        let s = model.settlements[0]
        model.track(s)
        model.recordPayment(s, amount: 50)
        model.reconcile(with: try makeFeed([(id: "s", deadline: "2027-06-01")]))
        #expect(model.deadlineNotices.count == 1)

        model.untrack(s)

        #expect(model.trackedSettlements.isEmpty)
        #expect(model.totalRecovered == 0)
        #expect(model.deadlineNotices.isEmpty)
    }

    @Test func trackedStatePersistsAcrossModelRelaunch() throws {
        let suiteName = "owed.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        let first = AppModel(defaults: suite)
        first.reconcile(with: try makeFeed([(id: "s", deadline: "2027-03-01")]))
        first.track(first.settlements[0])
        first.recordPayment(first.settlements[0], amount: 75)

        let second = AppModel(defaults: suite)
        #expect(second.trackedSettlements.map(\.id) == ["s"])
        #expect(second.totalRecovered == 75)
    }
}
