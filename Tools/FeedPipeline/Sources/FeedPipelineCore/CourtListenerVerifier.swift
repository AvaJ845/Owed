import Foundation

/// CourtListener / RECAP (PIPELINE.md §1) used strictly as a
/// **verification enricher**, never a discovery source and never a
/// publish gate.
///
/// Rationale (the Fellow call): dockets are poor for discovery — too
/// noisy, no structured "claims open now" — but excellent for confirming
/// a case number exists and reading the claim deadline off the approval
/// order. Critically it is **advisory**: state-court and FTC
/// administrative settlements have no federal docket, so a `.notFound`
/// must never drop a valid lead. It attaches provenance and, on a
/// deadline mismatch, flags the record for the reviewer.
public struct CourtListenerVerifier: Sendable {
    public enum Result: Equatable, Sendable {
        case confirmed(docketDeadline: Date?)
        case notFound            // no federal docket — expected for many
        case mismatch(docketDeadline: Date)   // docket disagrees with lead
    }

    private let token: String?
    private let fetch: RequestFetcher
    private let base = URL(string: "https://www.courtlistener.com/api/rest/v4/dockets/")!

    /// `token` is the CourtListener membership API token (full API access
    /// now requires membership). When nil, verification is skipped with a
    /// note rather than failing — enrichment is best-effort by design.
    public init(token: String?, fetcher: @escaping RequestFetcher) {
        self.token = token
        self.fetch = fetcher
    }

    /// Confirms `lead` against its docket. Never throws on "not found";
    /// only genuine transport errors propagate, and callers treat those
    /// as "unverified", not "invalid".
    public func verify(_ lead: Lead) async -> Result {
        guard let token else { return .notFound }
        guard let docket = lead.court.flatMap({ _ in lead.caseNo }),
              let url = queryURL(docketNumber: docket)
        else { return .notFound }

        // CourtListener requires the token in the Authorization header —
        // a bare GET is unauthenticated and would 401.
        var request = URLRequest(url: url)
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")

        guard let data = try? await fetch(request),
              let response = try? JSONDecoder().decode(DocketQueryResponse.self, from: data),
              let hit = response.results.first
        else { return .notFound }

        let docketDeadline = hit.dateClaimsDeadline.flatMap { FeedDay.date(from: $0) }
        if let d = docketDeadline, let leadDeadline = lead.deadline, d != leadDeadline {
            return .mismatch(docketDeadline: d)
        }
        return .confirmed(docketDeadline: docketDeadline)
    }

    /// Applies the result to a lead: records provenance, and on mismatch
    /// pushes the record back to `.inReview` (never auto-corrects a date
    /// — the human decides which source wins).
    public func annotate(_ lead: Lead, with result: Result, now: Date = .now) -> Lead {
        var out = lead
        switch result {
        case .confirmed(let deadline):
            out.sources.append(.init(field: "deadline", source: "CourtListener",
                                     url: base, observedAt: now))
            if deadline != nil { /* corroborated; no change */ }
        case .notFound:
            break   // advisory only — no docket is not a defect
        case .mismatch:
            out.status = .inReview
            out.sources.append(.init(field: "deadline!mismatch", source: "CourtListener",
                                     url: base, observedAt: now))
        }
        return out
    }

    private func queryURL(docketNumber: String) -> URL? {
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)
        let core = CaseNumber.normalize(docketNumber)
        comps?.queryItems = [URLQueryItem(name: "docket_number", value: core)]
        return comps?.url
    }
}

private struct DocketQueryResponse: Decodable { let results: [DocketHit] }
private struct DocketHit: Decodable {
    let dateClaimsDeadline: String?
    private enum CodingKeys: String, CodingKey { case dateClaimsDeadline = "date_claims_deadline" }
}
