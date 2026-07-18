import Foundation
import Testing
@testable import Owed

/// The feed decode is the trust boundary: strict about structure,
/// tolerant about vocabulary. These tests pin that contract.
struct FeedDecodingTests {

    // MARK: Fixtures

    /// A fully valid settlement record, overridable per test.
    private func record(
        id: String = "t1",
        deadline: String = "2027-01-15",
        adminURL: String = "https://example-administrator.com/case",
        matchKeys: String = #"["streaming"]"#,
        payoutLo: Int = 10,
        payoutHi: Int = 100,
        eligibility: String = #"["I qualify"]"#
    ) -> String {
        """
        {
          "id": "\(id)",
          "caseNo": "No. 1:26-cv-0001",
          "name": "Test Settlement \(id)",
          "category": "Test",
          "payoutLo": \(payoutLo),
          "payoutHi": \(payoutHi),
          "payoutTerms": "per claimant",
          "deadline": "\(deadline)",
          "receiptRequired": false,
          "adminURL": "\(adminURL)",
          "eligibility": \(eligibility),
          "matchKeys": \(matchKeys),
          "verifiedAt": "2026-07-01"
        }
        """
    }

    private func feedData(schemaVersion: Int = 1, records: [String]) -> Data {
        Data("""
        {
          "schemaVersion": \(schemaVersion),
          "generatedAt": "2026-07-18T00:00:00Z",
          "settlements": [\(records.joined(separator: ","))]
        }
        """.utf8)
    }

    // MARK: Envelope

    @Test func validFeedDecodes() throws {
        let feed = try SettlementFeed.decode(feedData(records: [record()]))
        #expect(feed.schemaVersion == 1)
        #expect(feed.settlements.count == 1)
        #expect(feed.minAppVersion == nil)
    }

    @Test func unsupportedSchemaVersionFailsWholeDecode() {
        #expect(throws: DecodingError.self) {
            try SettlementFeed.decode(feedData(schemaVersion: 99, records: [record()]))
        }
    }

    @Test func minAppVersionDecodesWhenPresent() throws {
        let data = Data("""
        {
          "schemaVersion": 1,
          "generatedAt": "2026-07-18T00:00:00Z",
          "minAppVersion": "1.2",
          "settlements": [\(record())]
        }
        """.utf8)
        #expect(try SettlementFeed.decode(data).minAppVersion == "1.2")
    }

    // MARK: Lossy record decode

    @Test func malformedRecordIsDroppedNotFatal() throws {
        let bad = #"{"id": "broken", "name": "missing everything"}"#
        let feed = try SettlementFeed.decode(feedData(records: [record(id: "a"), bad, record(id: "b")]))
        #expect(feed.settlements.map(\.id) == ["a", "b"])
    }

    @Test func duplicateIDsKeepFirstOccurrence() throws {
        let feed = try SettlementFeed.decode(feedData(records: [
            record(id: "dup", payoutLo: 1, payoutHi: 1),
            record(id: "dup", payoutLo: 2, payoutHi: 2),
        ]))
        #expect(feed.settlements.count == 1)
        #expect(feed.settlements[0].payoutLo == 1)
    }

    @Test func unknownMatchKeyIsIgnoredButRecordSurvives() throws {
        let feed = try SettlementFeed.decode(feedData(records: [
            record(matchKeys: #"["streaming", "hoverboard2031"]"#)
        ]))
        #expect(feed.settlements.count == 1)
        #expect(feed.settlements[0].matchKeys == [.streaming])
    }

    // MARK: Field validation

    @Test func httpAdminURLIsRejected() throws {
        let feed = try SettlementFeed.decode(feedData(records: [
            record(id: "http", adminURL: "http://evil.example.com/form"),
            record(id: "ok"),
        ]))
        #expect(feed.settlements.map(\.id) == ["ok"])
    }

    @Test func invertedPayoutRangeIsRejected() throws {
        let feed = try SettlementFeed.decode(feedData(records: [
            record(id: "bad", payoutLo: 500, payoutHi: 5)
        ]))
        #expect(feed.settlements.isEmpty)
    }

    @Test func emptyEligibilityIsRejected() throws {
        let feed = try SettlementFeed.decode(feedData(records: [
            record(id: "bad", eligibility: "[]")
        ]))
        #expect(feed.settlements.isEmpty)
    }

    @Test func malformedDeadlineIsRejected() throws {
        let feed = try SettlementFeed.decode(feedData(records: [
            record(id: "bad", deadline: "January 15, 2027")
        ]))
        #expect(feed.settlements.isEmpty)
    }

    // MARK: Snapshot round-trip

    /// Tracked snapshots are encoded with Settlement's encoder and read
    /// back through the same strict decoder as the feed — a snapshot
    /// that can't round-trip would silently drop a tracked claim.
    @Test func settlementRoundTripsThroughCodable() throws {
        let original = try SettlementFeed.decode(feedData(records: [record()])).settlements[0]
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(Settlement.self, from: data)
        #expect(restored == original)
    }
}
