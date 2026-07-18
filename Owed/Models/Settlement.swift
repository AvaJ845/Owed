import Foundation

/// One published, human-reviewed settlement.
/// Field shape mirrors the production API contract in PIPELINE.md §3 —
/// swapping the mock feed for `GET /v1/settlements?status=open` is a
/// decoder change, not a model change.
struct Settlement: Identifiable, Codable, Hashable {
    let id: String
    let caseNo: String
    let name: String
    let category: String
    let payoutLo: Int
    let payoutHi: Int
    let payoutTerms: String
    /// The claim-filing deadline. Stored as a date, never a day count —
    /// a count is stale the day after the feed is fetched.
    let deadline: Date
    let receiptRequired: Bool
    let adminURL: URL
    let eligibility: [String]
    /// Life-facts this settlement keys on for on-device matching.
    let matchKeys: [MatchKey]
    /// When a human reviewer last confirmed deadline, payout terms, and
    /// the administrator link against the source (PIPELINE.md §4).
    let verifiedAt: Date

    /// Whole days from today until the deadline, floored at 0.
    var daysLeft: Int {
        let cal = Calendar.current
        let days = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: .now),
            to: cal.startOfDay(for: deadline)
        ).day ?? 0
        return max(0, days)
    }

    var payoutRange: String {
        payoutLo == payoutHi
            ? payoutLo.usd
            : "\(payoutLo.usd)–\(payoutHi.usd)"
    }

    var closingSoon: Bool { daysLeft <= 21 }

    /// True once the filing window has passed.
    var closed: Bool { deadline < Calendar.current.startOfDay(for: .now) }
}

private let usdFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "en_US")
    return f
}()

extension Int {
    /// "$5,000" — whole-dollar amounts, US grouping, matching money() in lib/data.js.
    var usd: String {
        "$" + (usdFormatter.string(from: NSNumber(value: self)) ?? String(self))
    }
}

// MARK: - Mock feed (production shape; see PIPELINE.md)

extension Settlement {
    /// Mock deadlines are relative to install day so the demo always shows
    /// a live-looking feed; the production API sends absolute dates.
    private static func inDays(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: n, to: Calendar.current.startOfDay(for: .now))!
    }

    private static func daysAgo(_ n: Int) -> Date { inDays(-n) }

    static let mockFeed: [Settlement] = [
        Settlement(
            id: "s1", caseNo: "No. 3:24-cv-01881",
            name: "StreamBox Privacy Settlement",
            category: "Data privacy — viewing history shared with advertisers",
            payoutLo: 38, payoutHi: 120, payoutTerms: "per class member",
            deadline: inDays(11), receiptRequired: false,
            adminURL: URL(string: "https://example-administrator.com/streambox")!,
            eligibility: [
                "I had a StreamBox account between Jan 2019 and Mar 2024",
                "I resided in the U.S. during that period",
            ],
            matchKeys: [.streaming], verifiedAt: daysAgo(2)
        ),
        Settlement(
            id: "s2", caseNo: "No. 1:23-cv-04412",
            name: "MegaMart Overcharge Settlement",
            category: "False advertising — unit pricing on weighed goods",
            payoutLo: 25, payoutHi: 500, payoutTerms: "depends on purchase history",
            deadline: inDays(36), receiptRequired: false,
            adminURL: URL(string: "https://example-administrator.com/megamart")!,
            eligibility: [
                "I bought weighed grocery items at MegaMart 2020–2023",
                "I don't have receipts but purchased at least once",
            ],
            matchKeys: [.groceries], verifiedAt: daysAgo(1)
        ),
        Settlement(
            id: "s3", caseNo: "No. 5:22-cv-09174",
            name: "Handset Battery Throttling",
            category: "Consumer electronics — undisclosed performance limits",
            payoutLo: 65, payoutHi: 65, payoutTerms: "per eligible device",
            deadline: inDays(58), receiptRequired: true,
            adminURL: URL(string: "https://example-administrator.com/handset")!,
            eligibility: [
                "I owned an affected handset model (serial check at filing)",
                "Device was purchased new, not refurbished",
            ],
            matchKeys: [.smartphone], verifiedAt: daysAgo(4)
        ),
        Settlement(
            id: "s4", caseNo: "No. 2:24-cv-00317",
            name: "FastFashion Text Spam (TCPA)",
            category: "Telemarketing — texts after opt-out",
            payoutLo: 150, payoutHi: 900, payoutTerms: "per claimant",
            deadline: inDays(23), receiptRequired: false,
            adminURL: URL(string: "https://example-administrator.com/fastfashion")!,
            eligibility: [
                "I received marketing texts after replying STOP",
                "My number can be matched in defendant's records",
            ],
            matchKeys: [.spamTexts], verifiedAt: daysAgo(2)
        ),
        Settlement(
            id: "s5", caseNo: "No. 4:23-cv-06650",
            name: "CreditWatch Data Breach",
            category: "Data breach — SSNs and DOBs exposed",
            payoutLo: 50, payoutHi: 5000, payoutTerms: "up to, with documented losses",
            deadline: inDays(120), receiptRequired: true,
            adminURL: URL(string: "https://example-administrator.com/creditwatch")!,
            eligibility: [
                "I received a breach notice or can verify exposure",
                "I can document time or out-of-pocket losses for higher tiers",
            ],
            matchKeys: [.breachNotice], verifiedAt: daysAgo(5)
        ),
    ]
}
