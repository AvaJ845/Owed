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
    let daysLeft: Int
    let receiptRequired: Bool
    let adminURL: URL
    let eligibility: [String]

    var payoutRange: String {
        payoutLo == payoutHi
            ? payoutLo.usd
            : "\(payoutLo.usd)–\(payoutHi.usd)"
    }

    var closingSoon: Bool { daysLeft <= 21 }
}

extension Int {
    /// "$5,000" — whole-dollar amounts, US grouping, matching money() in lib/data.js.
    var usd: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        return "$" + (f.string(from: NSNumber(value: self)) ?? String(self))
    }
}

// MARK: - Mock feed (production shape; see PIPELINE.md)

extension Settlement {
    static let mockFeed: [Settlement] = [
        Settlement(
            id: "s1", caseNo: "No. 3:24-cv-01881",
            name: "StreamBox Privacy Settlement",
            category: "Data privacy — viewing history shared with advertisers",
            payoutLo: 38, payoutHi: 120, payoutTerms: "per class member",
            daysLeft: 11, receiptRequired: false,
            adminURL: URL(string: "https://example-administrator.com/streambox")!,
            eligibility: [
                "I had a StreamBox account between Jan 2019 and Mar 2024",
                "I resided in the U.S. during that period",
            ]
        ),
        Settlement(
            id: "s2", caseNo: "No. 1:23-cv-04412",
            name: "MegaMart Overcharge Settlement",
            category: "False advertising — unit pricing on weighed goods",
            payoutLo: 25, payoutHi: 500, payoutTerms: "depends on purchase history",
            daysLeft: 36, receiptRequired: false,
            adminURL: URL(string: "https://example-administrator.com/megamart")!,
            eligibility: [
                "I bought weighed grocery items at MegaMart 2020–2023",
                "I don't have receipts but purchased at least once",
            ]
        ),
        Settlement(
            id: "s3", caseNo: "No. 5:22-cv-09174",
            name: "Handset Battery Throttling",
            category: "Consumer electronics — undisclosed performance limits",
            payoutLo: 65, payoutHi: 65, payoutTerms: "per eligible device",
            daysLeft: 58, receiptRequired: true,
            adminURL: URL(string: "https://example-administrator.com/handset")!,
            eligibility: [
                "I owned an affected handset model (serial check at filing)",
                "Device was purchased new, not refurbished",
            ]
        ),
        Settlement(
            id: "s4", caseNo: "No. 2:24-cv-00317",
            name: "FastFashion Text Spam (TCPA)",
            category: "Telemarketing — texts after opt-out",
            payoutLo: 150, payoutHi: 900, payoutTerms: "per claimant",
            daysLeft: 23, receiptRequired: false,
            adminURL: URL(string: "https://example-administrator.com/fastfashion")!,
            eligibility: [
                "I received marketing texts after replying STOP",
                "My number can be matched in defendant's records",
            ]
        ),
        Settlement(
            id: "s5", caseNo: "No. 4:23-cv-06650",
            name: "CreditWatch Data Breach",
            category: "Data breach — SSNs and DOBs exposed",
            payoutLo: 50, payoutHi: 5000, payoutTerms: "up to, with documented losses",
            daysLeft: 120, receiptRequired: true,
            adminURL: URL(string: "https://example-administrator.com/creditwatch")!,
            eligibility: [
                "I received a breach notice or can verify exposure",
                "I can document time or out-of-pocket losses for higher tiers",
            ]
        ),
    ]
}
