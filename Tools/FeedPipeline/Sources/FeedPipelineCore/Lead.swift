import Foundation

/// The ingestion record (PIPELINE.md §3) — a settlement as it moves
/// through discovery and review, before it becomes a published
/// `Settlement`. Strictly richer than the app model: it carries a
/// lifecycle `status`, per-record `sources` provenance, and *optional*
/// fields, because a freshly discovered lead is allowed to be
/// incomplete. Only a reviewer-approved lead with every required field
/// and a `verifiedAt` stamp projects into the signed feed.
public struct Lead: Codable, Identifiable, Equatable {
    /// Lifecycle. A lead is only ever published by a human decision.
    public enum Status: String, Codable, Sendable {
        case lead          // discovered, unconfirmed
        case inReview      // has enough to review; awaiting human confirm
        case published     // reviewer confirmed; projects into the feed
        case closed        // filing window passed
        case rejected      // reviewer discarded (bad adminURL, duplicate, etc.)
    }

    /// One field's origin. Every material field should be traceable to a
    /// source the reviewer can re-open — that is the whole audit trail
    /// behind `verifiedAt`.
    public struct Provenance: Codable, Equatable, Sendable {
        public let field: String
        public let source: String       // e.g. "FTC", "CourtListener", "Epiq"
        public let url: URL?
        public let observedAt: Date
        public init(field: String, source: String, url: URL?, observedAt: Date) {
            self.field = field; self.source = source
            self.url = url; self.observedAt = observedAt
        }
    }

    public var id: String               // stable slug, also the feed id
    public var caseNo: String
    public var court: String?
    public var name: String
    public var category: String
    public var payoutLo: Int?
    public var payoutHi: Int?
    public var payoutTerms: String?
    public var deadline: Date?
    public var receiptRequired: Bool?
    public var eligibility: [String]
    public var adminURL: URL?
    /// Raw match-key strings (the app's decoder maps them to its own enum
    /// and drops any it doesn't know — the pipeline stays vocabulary-
    /// tolerant and never depends on the app's internal `MatchKey`).
    public var matchKeys: [String]
    public var status: Status
    public var sources: [Provenance]
    public var discoveredAt: Date
    /// Set only when a reviewer confirms the record against the
    /// administrator (PIPELINE.md §4). Its presence is the publish gate.
    public var verifiedAt: Date?

    public init(
        id: String, caseNo: String, court: String? = nil, name: String,
        category: String, payoutLo: Int? = nil, payoutHi: Int? = nil,
        payoutTerms: String? = nil, deadline: Date? = nil,
        receiptRequired: Bool? = nil, eligibility: [String] = [],
        adminURL: URL? = nil, matchKeys: [String] = [],
        status: Status = .lead, sources: [Provenance] = [],
        discoveredAt: Date = .now, verifiedAt: Date? = nil
    ) {
        self.id = id; self.caseNo = caseNo; self.court = court
        self.name = name; self.category = category
        self.payoutLo = payoutLo; self.payoutHi = payoutHi
        self.payoutTerms = payoutTerms; self.deadline = deadline
        self.receiptRequired = receiptRequired; self.eligibility = eligibility
        self.adminURL = adminURL; self.matchKeys = matchKeys
        self.status = status; self.sources = sources
        self.discoveredAt = discoveredAt; self.verifiedAt = verifiedAt
    }

    /// Day-precision deadline as the feed formats it ("yyyy-MM-dd"), or
    /// "—". Lets the CLI print deadlines without reaching for the app's
    /// internal `FeedDay`.
    public var deadlineDisplay: String {
        deadline.map { FeedDay.string(from: $0) } ?? "—"
    }

    /// The concrete fields the feed requires that this lead is still
    /// missing — surfaced to the reviewer so they know what to confirm.
    public var missingForPublish: [String] {
        var missing: [String] = []
        if payoutLo == nil { missing.append("payoutLo") }
        if payoutHi == nil { missing.append("payoutHi") }
        if payoutTerms?.isEmpty ?? true { missing.append("payoutTerms") }
        if deadline == nil { missing.append("deadline") }
        if receiptRequired == nil { missing.append("receiptRequired") }
        if adminURL == nil { missing.append("adminURL") }
        if eligibility.isEmpty { missing.append("eligibility") }
        return missing
    }
}
