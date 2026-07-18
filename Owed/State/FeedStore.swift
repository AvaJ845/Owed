import Foundation
import os

/// Step 2 of the live-data plan (PIPELINE.md §3): remote fetch layered on
/// the same decode path as the bundled snapshot, with two fallbacks under
/// it. Resolution order:
///
///   1. last-good downloaded feed cached on disk
///   2. the reviewed snapshot bundled with this build
///
/// The Find tab must never be empty because of airplane mode, a CDN
/// outage, or a bad publish — a stale-but-verified list always wins over
/// no list. Freshness is best-effort; correctness of what's shown is not.
///
/// Privacy contract: the fetch is a plain GET of a public file. No
/// identifiers, no cookies, no query parameters — "your answers never
/// leave this phone" is printed in the UI and this request must keep it
/// true.
enum FeedStore {
    /// The published feed. Currently the repo's own snapshot served raw
    /// from GitHub; swap for the CDN URL when the publish pipeline
    /// (PIPELINE.md §2–4) exists. Same JSON contract either way.
    static let remoteURL = URL(string: "https://raw.githubusercontent.com/AvaJ845/Owed/main/Owed/Resources/SettlementFeed.json")!

    private static let etagKey = "owed.feed.etag"
    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Owed", category: "feedstore"
    )

    /// Best locally available feed, newest first. Synchronous and cheap —
    /// safe to call during app init.
    static func bestAvailable() -> SettlementFeed? {
        if let cached = cachedFeed() { return cached }
        return SettlementFeed.bundled()
    }

    /// Fetches the remote feed if it changed (ETag-validated). Returns
    /// the new feed, or nil when unchanged or unavailable — callers keep
    /// whatever they're showing in either case.
    static func refresh() async -> SettlementFeed? {
        var request = URLRequest(url: remoteURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let etag = UserDefaults.standard.string(forKey: etagKey) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            log.info("Feed refresh skipped (offline or unreachable): \(String(describing: error))")
            return nil
        }

        guard let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 304 { return nil }
        guard http.statusCode == 200 else {
            log.error("Feed refresh got HTTP \(http.statusCode)")
            return nil
        }

        // Decode before persisting: a feed that fails the envelope's
        // strict decode never replaces the last-good cache.
        let feed: SettlementFeed
        do {
            feed = try SettlementFeed.decode(data)
        } catch {
            log.error("Remote feed failed to decode; keeping last-good: \(String(describing: error))")
            return nil
        }

        // A publish rewind (older generatedAt than what we have) is
        // suspicious — keep the newer local copy.
        if let current = bestAvailable(), feed.generatedAt < current.generatedAt {
            log.error("Remote feed older than local (\(feed.generatedAt) < \(current.generatedAt)); ignoring")
            return nil
        }

        persist(data: data, etag: http.value(forHTTPHeaderField: "ETag"))
        logMinAppVersionIfBehind(feed)
        return feed
    }

    // MARK: - Disk cache

    private static var cacheURL: URL? {
        guard let dir = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return nil }
        return dir.appendingPathComponent("SettlementFeed.json")
    }

    private static func cachedFeed() -> SettlementFeed? {
        guard let url = cacheURL, let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try SettlementFeed.decode(data)
        } catch {
            // A cache this build can't read (e.g. schema bumped by a
            // newer publish) is dead weight — drop it and fall back to
            // the bundled snapshot.
            log.error("Cached feed failed to decode; discarding: \(String(describing: error))")
            try? FileManager.default.removeItem(at: url)
            UserDefaults.standard.removeObject(forKey: etagKey)
            return nil
        }
    }

    private static func persist(data: Data, etag: String?) {
        guard let url = cacheURL else { return }
        do {
            try data.write(to: url, options: .atomic)
            UserDefaults.standard.set(etag, forKey: etagKey)
        } catch {
            log.error("Failed to cache feed: \(String(describing: error))")
        }
    }

    // MARK: - Version signal

    private static func logMinAppVersionIfBehind(_ feed: SettlementFeed) {
        guard let min = feed.minAppVersion,
              let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              current.compare(min, options: .numeric) == .orderedAscending
        else { return }
        log.error("Feed recommends app version \(min); running \(current)")
    }
}
