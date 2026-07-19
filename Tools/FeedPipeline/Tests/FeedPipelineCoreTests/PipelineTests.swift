import CryptoKit
import Foundation
import Testing
@testable import FeedPipelineCore

/// Gates for the ingestion pipeline. The load-bearing test is
/// `approvedLeadProjectsThroughAppDecoder` / `httpAdminURLIsRejectedAtPublish`:
/// they prove the pipeline can only emit a feed the app would accept.
struct PipelineTests {

    private var fixtureURL: URL {
        // …/Tests/FeedPipelineCoreTests/PipelineTests.swift → package root → Fixtures
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ftc-refunds-sample.json")
    }

    // MARK: Case-number normalization

    @Test func normalizeCollapsesCosmeticDifferences() {
        #expect(CaseNumber.normalize("No. 4:19-cv-04286") == "4:19-cv-04286")
        #expect(CaseNumber.normalize("4:19\u{2011}cv\u{2011}04286-JST") == "4:19-cv-04286")
        #expect(CaseNumber.normalize("No. 4:19-cv-04286") == CaseNumber.normalize("4:19-cv-04286-EMC"))
    }

    // MARK: FTC adapter

    @Test func ftcAdapterKeepsOnlyClaimablePrograms() throws {
        let data = try Data(contentsOf: fixtureURL)
        let leads = try FTCRefundsAdapter.map(data, endpoint: URL(string: "https://ftc.gov")!)
        // Two claimable; the automatic (no claimURL) program is dropped.
        #expect(leads.map(\.id).sorted() == ["ftc-benefytt-refunds", "ftc-vonage-refunds"])
        let vonage = try #require(leads.first { $0.id == "ftc-vonage-refunds" })
        #expect(vonage.status == .inReview)               // never auto-published
        #expect(vonage.verifiedAt == nil)                 // not yet human-confirmed
        #expect(vonage.adminURL?.scheme == "https")
        #expect(vonage.sources.allSatisfy { $0.source == "FTC" })
        #expect(vonage.matchKeys == ["spamTexts"])
    }

    // MARK: Dedup

    @Test func dedupMergesProvenanceAndPreservesReviewerDecisions() {
        let published = Lead(
            id: "a", caseNo: "No. 1:23-cv-0001", name: "A", category: "c",
            payoutLo: 1, payoutHi: 2, payoutTerms: "t",
            deadline: FeedDay.date(from: "2027-01-01"), receiptRequired: false,
            eligibility: ["e"], adminURL: URL(string: "https://a.example/claim"),
            status: .published, sources: [.init(field: "name", source: "Epiq", url: nil, observedAt: .now)],
            verifiedAt: FeedDay.date(from: "2026-07-01"))
        // Same case resurfaces from another source with a *different* deadline.
        let rediscovered = Lead(
            id: "a-dup", caseNo: "1:23-cv-0001-JST", name: "A", category: "c",
            deadline: FeedDay.date(from: "2099-01-01"),
            status: .inReview, sources: [.init(field: "deadline", source: "CourtListener", url: nil, observedAt: .now)])

        let merged = Deduplicator.merge(existing: [published], incoming: [rediscovered])
        #expect(merged.count == 1)                                 // collapsed
        #expect(merged[0].status == .published)                    // reviewer decision kept
        #expect(merged[0].deadline == FeedDay.date(from: "2027-01-01")) // confirmed value untouched
        #expect(merged[0].sources.contains { $0.source == "CourtListener" }) // provenance unioned
    }

    // MARK: Publish gate (anti-drift)

    private func approvedLead(adminURL: String) -> Lead {
        Lead(id: "x", caseNo: "No. 9:26-cv-1", name: "X Settlement", category: "cat",
             payoutLo: 10, payoutHi: 50, payoutTerms: "per claimant",
             deadline: FeedDay.date(from: "2027-05-01"), receiptRequired: false,
             eligibility: ["I qualify"], adminURL: URL(string: adminURL),
             matchKeys: ["streaming"], status: .published,
             verifiedAt: FeedDay.date(from: "2026-07-19"))
    }

    @Test func approvedLeadProjectsThroughAppDecoder() throws {
        let out = try Publisher.build(
            currentFeedJSON: nil,
            approved: [approvedLead(adminURL: "https://x.example/claim")],
            minAppVersion: "1.0")
        #expect(out.settlementCount == 1)
        #expect(out.newlyPublished == 1)
        // The bytes decode through the same envelope the app uses.
        let feed = try SettlementFeed.decode(out.json)
        #expect(feed.settlements.first?.id == "x")
        #expect(feed.settlements.first?.deadline == FeedDay.date(from: "2027-05-01"))
    }

    @Test func httpAdminURLIsRejectedAtPublish() {
        #expect(throws: PipelineError.self) {
            _ = try Publisher.build(
                currentFeedJSON: nil,
                approved: [approvedLead(adminURL: "http://x.example/claim")], // not https
                minAppVersion: "1.0")
        }
    }

    @Test func closedSettlementsAreDroppedOnPublish() throws {
        let current = """
        {"schemaVersion":1,"generatedAt":"2026-07-18T00:00:00Z","settlements":[
          {"id":"old-closed","caseNo":"No. 1","name":"Old","category":"c","payoutLo":1,"payoutHi":1,
           "payoutTerms":"t","deadline":"2020-01-01","receiptRequired":false,
           "adminURL":"https://o.example/claim","eligibility":["e"],"matchKeys":[],"verifiedAt":"2019-12-01"}
        ]}
        """.data(using: .utf8)!
        let out = try Publisher.build(
            currentFeedJSON: current,
            approved: [approvedLead(adminURL: "https://x.example/claim")],
            minAppVersion: "1.0")
        let feed = try SettlementFeed.decode(out.json)
        #expect(feed.settlements.map(\.id) == ["x"])   // closed one carried forward → dropped
        #expect(out.carriedForward == 0)
    }

    // MARK: Review queue

    // MARK: Base-feed signature gate (S3)

    @Test func feedIntegrityVerifiesGenuineSignatureAndRejectsTamper() {
        let key = Curve25519.Signing.PrivateKey()
        let pub = key.publicKey.rawRepresentation.base64EncodedString()
        let feed = Data(#"{"schemaVersion":1,"generatedAt":"2026-07-18T00:00:00Z","settlements":[]}"#.utf8)
        let sig = try! key.signature(for: feed).base64EncodedString()

        #expect(FeedIntegrity.verify(feed: feed, signatureB64: sig, publicKeyB64: pub) == .verified)

        var tampered = feed
        tampered.append(contentsOf: [0x20])   // one extra byte
        #expect(FeedIntegrity.verify(feed: tampered, signatureB64: sig, publicKeyB64: pub) == .invalid)

        let otherKeySig = try! Curve25519.Signing.PrivateKey().signature(for: feed).base64EncodedString()
        #expect(FeedIntegrity.verify(feed: feed, signatureB64: otherKeySig, publicKeyB64: pub) == .invalid)
    }

    @Test func approveRefusesIncompleteLead() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("owed-queue-\(UUID()).json")
        var queue = try ReviewQueue(url: tmp)
        queue.ingest([Lead(id: "incomplete", caseNo: "No. 2", name: "N", category: "c",
                           status: .inReview)])
        #expect(queue.approve(id: "incomplete") != nil)  // refused, returns a reason
        #expect(queue.approved.isEmpty)
    }
}
