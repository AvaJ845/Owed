import Foundation

/// Collapses leads that describe the same settlement (PIPELINE.md §2).
/// Dedup key is the normalized case number; provenance from every source
/// is unioned so the reviewer sees all corroboration on one record.
public enum Deduplicator {
    /// Merge `incoming` into `existing`, keyed by normalized case number.
    /// Human decisions are never overwritten: a lead already `.published`
    /// or `.rejected` keeps its status and its confirmed fields; new
    /// discovery only appends provenance to it. For not-yet-reviewed
    /// leads, a non-nil incoming field fills a nil existing one (better
    /// corroboration, never silent replacement of a set value).
    public static func merge(existing: [Lead], incoming: [Lead]) -> [Lead] {
        var byKey: [String: Lead] = [:]
        var order: [String] = []

        func key(_ l: Lead) -> String { CaseNumber.normalize(l.caseNo) }

        for lead in existing {
            let k = key(lead)
            if byKey[k] == nil { order.append(k) }
            byKey[k] = lead
        }

        for lead in incoming {
            let k = key(lead)
            guard var current = byKey[k] else {
                byKey[k] = lead; order.append(k); continue
            }

            // Always union provenance — even a settled record benefits
            // from knowing another source corroborated it.
            current.sources = mergedSources(current.sources + lead.sources)

            // Reviewer-owned records are immutable except for provenance.
            if current.status == .published || current.status == .rejected {
                byKey[k] = current; continue
            }

            // Fill gaps only; don't clobber a value already discovered.
            current.court = current.court ?? lead.court
            current.payoutLo = current.payoutLo ?? lead.payoutLo
            current.payoutHi = current.payoutHi ?? lead.payoutHi
            current.payoutTerms = current.payoutTerms ?? lead.payoutTerms
            current.deadline = current.deadline ?? lead.deadline
            current.receiptRequired = current.receiptRequired ?? lead.receiptRequired
            current.adminURL = current.adminURL ?? lead.adminURL
            if current.eligibility.isEmpty { current.eligibility = lead.eligibility }
            if current.matchKeys.isEmpty { current.matchKeys = lead.matchKeys }
            // A lead that now has an admin URL + deadline is reviewable.
            if current.status == .lead, current.adminURL != nil, current.deadline != nil {
                current.status = .inReview
            }
            byKey[k] = current
        }

        return order.compactMap { byKey[$0] }
    }

    private static func mergedSources(_ sources: [Lead.Provenance]) -> [Lead.Provenance] {
        var seen = Set<String>()
        return sources.filter { p in
            seen.insert("\(p.field)|\(p.source)|\(p.url?.absoluteString ?? "")").inserted
        }
    }
}
