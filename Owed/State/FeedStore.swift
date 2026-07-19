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
///
/// Integrity: remote bytes must verify under the embedded Ed25519 public
/// key (`FeedSigning`) before they replace last-good. A CDN compromise
/// cannot inject a fake administrator URL.
enum FeedStore {
    /// The published feed. Currently the repo's own snapshot served raw
    /// from GitHub; swap for the CDN URL when the publish pipeline
    /// (PIPELINE.md §2–4) exists. Same JSON contract either way.
    static let remoteURL = URL(string: "https://raw.githubusercontent.com/AvaJ845/Owed/main/Owed/Resources/SettlementFeed.json")!

    private static let etagKey = "owed.feed.etag"
    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Owed", category: "feedstore"
    )

    /// Hard cap on downloaded bytes. A signed feed of hundreds of
    /// settlements is tens of KB; the cap exists because signature
    /// verification happens *after* download, so without it a network
    /// attacker or broken CDN could stream an unbounded body into memory
    /// before we ever reject it. The signature is ~88 bytes.
    private static let maxFeedBytes = 5 * 1024 * 1024   // 5 MB
    private static let maxSignatureBytes = 8 * 1024      // 8 KB

    private enum FeedError: Error { case tooLarge }

    /// Ephemeral on purpose: no cookie store, no credential cache, no
    /// persistent URL cache — the shared session would quietly accumulate
    /// state around a request whose whole point is carrying none. Tight
    /// timeout because this runs on foreground; a slow CDN must never
    /// hold up anything (the last-good feed is already showing).
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    /// Raw bytes of the last-good downloaded feed on disk (nil if none).
    /// Just I/O — decode on the caller's side so the disk read can run
    /// off the main actor without moving a non-Sendable feed across it.
    static func cachedData() -> Data? {
        guard let url = cacheURL else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Drop an unreadable cache (and its ETag) so the next launch falls
    /// back to the bundled snapshot instead of retrying dead bytes.
    static func discardCache() {
        if let url = cacheURL { try? FileManager.default.removeItem(at: url) }
        UserDefaults.standard.removeObject(forKey: etagKey)
    }

    /// Fetches the remote feed if it changed (ETag-validated). Returns
    /// the new feed, or nil when unchanged or unavailable — callers keep
    /// whatever they're showing in either case. `floor` is the
    /// generatedAt already on screen; a feed older than it is rejected
    /// (publish-rewind guard) without re-reading the disk cache.
    static func refresh(notOlderThan floor: Date?) async -> SettlementFeed? {
        var request = URLRequest(url: remoteURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let etag = UserDefaults.standard.string(forKey: etagKey) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let http: HTTPURLResponse
        let body: Data?
        do {
            (http, body) = try await fetchCapped(request, maxBytes: maxFeedBytes)
        } catch FeedError.tooLarge {
            log.error("Remote feed exceeded \(maxFeedBytes) bytes; refusing")
            return nil
        } catch {
            log.info("Feed refresh skipped (offline or unreachable): \(String(describing: error))")
            return nil
        }

        if http.statusCode == 304 { return nil }
        guard http.statusCode == 200, let data = body else {
            log.error("Feed refresh got HTTP \(http.statusCode)")
            return nil
        }

        // Signature before decode: a CDN that serves a well-formed but
        // malicious feed must not enter the decode path at all.
        //
        // The feed and its detached signature are two GETs, so a publish
        // that lands between them can pair new bytes with the old
        // signature (or vice versa) and fail verification. That is by
        // design: verification fails closed — we keep last-good and never
        // persist the mismatched bytes or their ETag — and the next
        // refresh re-fetches a now-consistent pair, so the state
        // self-heals. Fetching the signature only after a 200 (not on the
        // common 304) keeps the unchanged-feed poll a single request.
        guard let signature = await fetchSignature() else {
            log.error("Remote feed signature missing; keeping last-good")
            return nil
        }
        guard FeedSigning.verify(payload: data, signature: signature) else {
            log.error("Remote feed signature invalid; keeping last-good")
            return nil
        }

        let feed: SettlementFeed
        do {
            feed = try SettlementFeed.decode(data)
        } catch {
            log.error("Remote feed failed to decode; keeping last-good: \(String(describing: error))")
            return nil
        }

        // A publish rewind (older than what's on screen) is suspicious —
        // keep the newer copy. Compared against the in-memory floor, so
        // no redundant disk read/decode.
        if let floor, feed.generatedAt < floor {
            log.error("Remote feed older than current (\(feed.generatedAt) < \(floor)); ignoring")
            return nil
        }

        persist(data: data, etag: http.value(forHTTPHeaderField: "ETag"))
        logMinAppVersionIfBehind(feed)
        return feed
    }

    /// Streams a response body, aborting the moment it exceeds `maxBytes`,
    /// so an oversized (or Content-Length-lying) response can't exhaust
    /// memory before verification. Body is nil for a 304.
    private static func fetchCapped(
        _ request: URLRequest, maxBytes: Int
    ) async throws -> (http: HTTPURLResponse, body: Data?) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 304 { return (http, nil) }
        // Reject early when the server honestly declares an oversized body.
        if http.expectedContentLength > Int64(maxBytes) { throw FeedError.tooLarge }

        var data = Data()
        if http.expectedContentLength > 0 {
            data.reserveCapacity(min(maxBytes, Int(http.expectedContentLength)))
        }
        for try await byte in bytes {
            data.append(byte)
            if data.count > maxBytes { throw FeedError.tooLarge }
        }
        return (http, data)
    }

    // MARK: - Signature

    private static var signatureURL: URL {
        remoteURL
            .deletingLastPathComponent()
            .appendingPathComponent("SettlementFeed.json.sig")
    }

    private static func fetchSignature() async -> Data? {
        var request = URLRequest(url: signatureURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (http, body) = try await fetchCapped(request, maxBytes: maxSignatureBytes)
            guard http.statusCode == 200 else { return nil }
            return body
        } catch {
            return nil
        }
    }

    // MARK: - Disk cache

    private static var cacheURL: URL? {
        guard let dir = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return nil }
        return dir.appendingPathComponent("SettlementFeed.json")
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
