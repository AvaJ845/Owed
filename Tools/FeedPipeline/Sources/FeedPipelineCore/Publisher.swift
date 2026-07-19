import Foundation

/// Projects approved leads into the signed feed's `SettlementFeed.json`
/// (PIPELINE.md §3 → the shipped artifact).
///
/// The anti-drift guarantee: the publisher builds the feed JSON and then
/// **decodes it back through the app's own `SettlementFeed.decode`** —
/// the exact strict validator the client runs (https-only adminURL, sane
/// payout range, non-empty eligibility, yyyy-MM-dd dates, unknown match
/// keys dropped). If a projected record wouldn't survive on-device, the
/// publish fails here, at the desk, instead of shipping a record the app
/// silently discards. Signing stays in `Scripts/sign-feed.sh` — this
/// tool never touches the private key.
public enum Publisher {
    public struct Output {
        public let json: Data
        public let settlementCount: Int
        public let carriedForward: Int
        public let newlyPublished: Int
    }

    /// Build the next feed from the currently published feed plus approved
    /// leads. Closed settlements are dropped (the app excludes them from
    /// browse anyway, and the feed shouldn't grow unbounded). Approved
    /// leads win over a same-id carried-forward record.
    public static func build(
        currentFeedJSON: Data?,
        approved: [Lead],
        minAppVersion: String?,
        generatedAt: Date = .now,
        calendar: Calendar = .current
    ) throws -> Output {
        var byID: [String: [String: Any]] = [:]
        var order: [String] = []
        let startOfToday = calendar.startOfDay(for: generatedAt)

        // Carry forward still-open settlements from the current feed.
        var carried = 0
        if let currentFeedJSON,
           let root = try JSONSerialization.jsonObject(with: currentFeedJSON) as? [String: Any],
           let settlements = root["settlements"] as? [[String: Any]] {
            for s in settlements {
                guard let id = s["id"] as? String,
                      let deadlineStr = s["deadline"] as? String,
                      let deadline = FeedDay.date(from: deadlineStr),
                      deadline >= startOfToday          // drop closed
                else { continue }
                if byID[id] == nil { order.append(id) }
                byID[id] = s
                carried += 1
            }
        }

        // Overlay approved leads (may update a carried record or add new).
        var added = 0
        for lead in approved {
            guard lead.verifiedAt != nil else {
                throw PipelineError.validation("approved lead \(lead.id) has no verifiedAt")
            }
            let obj = try feedObject(from: lead)
            if byID[lead.id] == nil { order.append(lead.id) }
            else { carried -= 1 }        // replacing a carried record
            byID[lead.id] = obj
            added += 1
        }

        let settlementObjects = order.compactMap { byID[$0] }
        var envelope: [String: Any] = [
            "schemaVersion": 1,
            "generatedAt": ISO8601DateFormatter().string(from: generatedAt),
            "settlements": settlementObjects,
        ]
        if let minAppVersion { envelope["minAppVersion"] = minAppVersion }

        let json = try JSONSerialization.data(
            withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])

        // The gate: must decode through the app's strict validator.
        let feed: SettlementFeed
        do {
            feed = try SettlementFeed.decode(json)
        } catch {
            throw PipelineError.validation(
                "projected feed rejected by the app decoder: \(error)")
        }
        // Lossy decode drops bad records silently — insist none were lost.
        guard feed.settlements.count == settlementObjects.count else {
            throw PipelineError.validation(
                "app decoder kept \(feed.settlements.count) of \(settlementObjects.count) records — "
                + "one or more projected settlements are invalid")
        }

        return Output(json: json, settlementCount: feed.settlements.count,
                      carriedForward: max(0, carried), newlyPublished: added)
    }

    /// A lead → the feed's per-settlement JSON object. Day-precision dates
    /// are formatted with the same `FeedDay` the app parses with, so they
    /// round-trip exactly.
    static func feedObject(from lead: Lead) throws -> [String: Any] {
        func required<T>(_ value: T?, _ field: String) throws -> T {
            guard let value else {
                throw PipelineError.validation("lead \(lead.id) missing \(field)")
            }
            return value
        }
        return [
            "id": lead.id,
            "caseNo": lead.caseNo,
            "name": lead.name,
            "category": lead.category,
            "payoutLo": try required(lead.payoutLo, "payoutLo"),
            "payoutHi": try required(lead.payoutHi, "payoutHi"),
            "payoutTerms": try required(lead.payoutTerms, "payoutTerms"),
            "deadline": FeedDay.string(from: try required(lead.deadline, "deadline")),
            "receiptRequired": try required(lead.receiptRequired, "receiptRequired"),
            "adminURL": try required(lead.adminURL, "adminURL").absoluteString,
            "eligibility": lead.eligibility,
            "matchKeys": lead.matchKeys,
            "verifiedAt": FeedDay.string(from: try required(lead.verifiedAt, "verifiedAt")),
        ]
    }
}
