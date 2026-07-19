import Foundation

/// FTC redress programs (PIPELINE.md §1, kept as the anchor source):
/// government-authoritative, low perjury-risk, and the FTC is effectively
/// the administrator for its own programs — the shortest possible path
/// from discovery to the verification target.
///
/// Two deliberate mapping decisions:
/// 1. **Claimable only.** Many FTC redress programs mail checks
///    automatically — there is nothing for the user to file, so they are
///    not app inventory. We keep only programs with a claim URL and a
///    claim deadline.
/// 2. **`.inReview`, never auto-published.** High trust still passes
///    through a human, who confirms the claim URL is the official redress
///    site before it is signed into the feed (PIPELINE.md §4).
///
/// The wire shape lives behind `FTCRefundRecord`; `endpoint` is where the
/// operator points the live fetch (the FTC publishes redress data via
/// ftc.gov/exploredata — finalize the exact export URL there). Tests and
/// `feedctl discover --fixture` drive the same mapping over a committed
/// sample, so the mapping is verified independently of the live selector.
public struct FTCRefundsAdapter: SourceAdapter {
    public let sourceName = "FTC"
    public let endpoint: URL
    private let fetch: Fetcher

    public init(
        endpoint: URL = URL(string: "https://www.ftc.gov/exploredata/refunds.json")!,
        fetcher: @escaping Fetcher
    ) {
        self.endpoint = endpoint
        self.fetch = fetcher
    }

    public func discover() async throws -> [Lead] {
        let data = try await fetch(endpoint)
        return try Self.map(data, endpoint: endpoint)
    }

    /// Pure mapping — the part worth testing. Filters to claimable
    /// programs and projects each into a `Lead` with FTC provenance.
    static func map(_ data: Data, endpoint: URL) throws -> [Lead] {
        let payload: FTCPayload
        do {
            payload = try JSONDecoder().decode(FTCPayload.self, from: data)
        } catch {
            throw PipelineError.decode("FTC payload: \(error)")
        }
        let now = Date()
        return payload.cases.compactMap { rec -> Lead? in
            // Claimable only: needs a claim URL and a future-or-present deadline.
            guard let claimURL = rec.claimURL,
                  let deadlineStr = rec.claimDeadline,
                  let deadline = FeedDay.date(from: deadlineStr)
            else { return nil }

            let src = { (field: String) in
                Lead.Provenance(field: field, source: "FTC", url: rec.detailURL ?? endpoint, observedAt: now) }

            return Lead(
                id: rec.slug,
                caseNo: rec.docketNumber.map { "No. \($0)" } ?? "FTC \(rec.matterNumber ?? rec.slug)",
                court: rec.court,
                name: rec.name,
                category: rec.category ?? "FTC refund program",
                payoutLo: rec.refundLow,
                payoutHi: rec.refundHigh ?? rec.refundLow,
                payoutTerms: rec.payoutTerms ?? "FTC redress; amount depends on the program",
                deadline: deadline,
                receiptRequired: rec.requiresProof ?? false,
                eligibility: rec.eligibility.isEmpty
                    ? ["I was affected by the FTC action described on the official refund page"]
                    : rec.eligibility,
                adminURL: claimURL,
                matchKeys: rec.matchKeys,
                status: .inReview,
                sources: ["name", "deadline", "adminURL", "payoutTerms"].map(src),
                discoveredAt: now
            )
        }
    }
}

// MARK: - Wire shape

/// The FTC refund export shape the adapter consumes. Kept permissive
/// (most fields optional) so a schema tweak on the FTC side degrades a
/// single record to "not claimable / needs review" rather than failing
/// the whole run.
struct FTCPayload: Decodable { let cases: [FTCRefundRecord] }

struct FTCRefundRecord: Decodable {
    let slug: String
    let name: String
    let matterNumber: String?
    let docketNumber: String?
    let court: String?
    let category: String?
    let refundLow: Int?
    let refundHigh: Int?
    let payoutTerms: String?
    let claimDeadline: String?     // "yyyy-MM-dd"
    let claimURL: URL?
    let detailURL: URL?
    let requiresProof: Bool?
    let eligibility: [String]
    let matchKeys: [String]

    private enum CodingKeys: String, CodingKey {
        case slug, name, matterNumber, docketNumber, court, category
        case refundLow, refundHigh, payoutTerms, claimDeadline, claimURL
        case detailURL, requiresProof, eligibility, matchKeys
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = try c.decode(String.self, forKey: .slug)
        name = try c.decode(String.self, forKey: .name)
        matterNumber = try c.decodeIfPresent(String.self, forKey: .matterNumber)
        docketNumber = try c.decodeIfPresent(String.self, forKey: .docketNumber)
        court = try c.decodeIfPresent(String.self, forKey: .court)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        refundLow = try c.decodeIfPresent(Int.self, forKey: .refundLow)
        refundHigh = try c.decodeIfPresent(Int.self, forKey: .refundHigh)
        payoutTerms = try c.decodeIfPresent(String.self, forKey: .payoutTerms)
        claimDeadline = try c.decodeIfPresent(String.self, forKey: .claimDeadline)
        claimURL = try c.decodeIfPresent(URL.self, forKey: .claimURL)
        detailURL = try c.decodeIfPresent(URL.self, forKey: .detailURL)
        requiresProof = try c.decodeIfPresent(Bool.self, forKey: .requiresProof)
        eligibility = try c.decodeIfPresent([String].self, forKey: .eligibility) ?? []
        matchKeys = try c.decodeIfPresent([String].self, forKey: .matchKeys) ?? []
    }
}
