import Foundation

/// Durable list of leads across pipeline runs, stored as JSON next to the
/// repo (default `Pipeline/review-queue.json`). Discovery merges into it;
/// the reviewer acts on it; publishing reads approved records from it.
/// Human decisions live here and are never overwritten by discovery
/// (see `Deduplicator`).
public struct ReviewQueue {
    public let url: URL
    public private(set) var leads: [Lead]

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public init(url: URL) throws {
        self.url = url
        if let data = try? Data(contentsOf: url) {
            leads = try Self.decoder.decode([Lead].self, from: data)
        } else {
            leads = []
        }
    }

    public mutating func ingest(_ discovered: [Lead]) {
        leads = Deduplicator.merge(existing: leads, incoming: discovered)
    }

    /// Reviewer approval (PIPELINE.md §4): confirms the record and stamps
    /// `verifiedAt`. Refuses to approve a record still missing required
    /// fields — you cannot verify what isn't there. Returns nil on
    /// success, or a human-readable reason it was refused.
    public mutating func approve(id: String, on date: Date = .now) -> String? {
        guard let i = leads.firstIndex(where: { $0.id == id }) else {
            return "no lead with id \(id)"
        }
        let missing = leads[i].missingForPublish
        guard missing.isEmpty else {
            return "cannot approve \(id) — missing \(missing.joined(separator: ", "))"
        }
        leads[i].status = .published
        leads[i].verifiedAt = date
        return nil
    }

    public mutating func reject(id: String) {
        if let i = leads.firstIndex(where: { $0.id == id }) { leads[i].status = .rejected }
    }

    /// Records the reviewer must still act on.
    public var pending: [Lead] {
        leads.filter { $0.status == .lead || $0.status == .inReview }
    }

    /// Approved records that project into the feed.
    public var approved: [Lead] {
        leads.filter { $0.status == .published && $0.verifiedAt != nil }
    }

    public func save() throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(leads).write(to: url, options: .atomic)
    }
}
