import Foundation

/// One published, human-reviewed settlement, decoded from the settlement
/// feed (SettlementFeed). Field shape mirrors the production API contract
/// in PIPELINE.md §3.
struct Settlement: Identifiable, Decodable, Hashable {
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

// MARK: - Feed decoding

extension Settlement {
    private enum CodingKeys: String, CodingKey {
        case id, caseNo, name, category, payoutLo, payoutHi, payoutTerms
        case deadline, receiptRequired, adminURL, eligibility
        case matchKeys, verifiedAt
    }

    /// Strict about structure, tolerant about vocabulary: every field is
    /// required and validated (a record we can't trust is dropped by the
    /// envelope's lossy decode), but match keys this build doesn't know
    /// are ignored so older apps survive newer feeds.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decode(String.self, forKey: .id)
        guard !id.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .id, in: c, debugDescription: "Empty settlement id"
            )
        }

        caseNo = try c.decode(String.self, forKey: .caseNo)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decode(String.self, forKey: .category)

        payoutLo = try c.decode(Int.self, forKey: .payoutLo)
        payoutHi = try c.decode(Int.self, forKey: .payoutHi)
        guard payoutLo >= 0, payoutLo <= payoutHi else {
            throw DecodingError.dataCorruptedError(
                forKey: .payoutLo, in: c,
                debugDescription: "Invalid payout range \(payoutLo)–\(payoutHi)"
            )
        }

        payoutTerms = try c.decode(String.self, forKey: .payoutTerms)
        deadline = try c.decodeFeedDay(forKey: .deadline)
        receiptRequired = try c.decode(Bool.self, forKey: .receiptRequired)

        // The app sends users to this URL to enter personal information;
        // require https so a bad feed record can't downgrade that.
        adminURL = try c.decode(URL.self, forKey: .adminURL)
        guard adminURL.scheme?.lowercased() == "https" else {
            throw DecodingError.dataCorruptedError(
                forKey: .adminURL, in: c,
                debugDescription: "Administrator URL must be https"
            )
        }

        eligibility = try c.decode([String].self, forKey: .eligibility)
        guard !eligibility.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .eligibility, in: c,
                debugDescription: "Settlement has no eligibility criteria"
            )
        }

        matchKeys = try c.decode([String].self, forKey: .matchKeys)
            .compactMap(MatchKey.init)
        verifiedAt = try c.decodeFeedDay(forKey: .verifiedAt)
    }
}

// MARK: - Formatting

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
