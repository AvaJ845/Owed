import FeedPipelineCore
import Foundation

// feedctl — operator CLI for the Owed feed pipeline (PIPELINE.md §1–4).
//
//   feedctl discover [--fixture <path>] [--endpoint <url>]
//   feedctl queue
//   feedctl approve <id>
//   feedctl reject <id>
//   feedctl publish
//
// Discovery only ever produces leads for human review; nothing reaches
// the signed feed without `approve` + `publish`, and publish still hands
// signing to Scripts/sign-feed.sh.

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage(); exit(2) }

let root = repoRoot()
let queueURL = root.appendingPathComponent("Pipeline/review-queue.json")
let feedURL = root.appendingPathComponent("Owed/Resources/SettlementFeed.json")

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

do {
    switch command {
    case "discover":
        var queue = try ReviewQueue(url: queueURL)
        let fetcher: Fetcher
        let endpoint: URL
        if let fixture = option("--fixture") {
            let data = try Data(contentsOf: URL(fileURLWithPath: fixture))
            fetcher = { _ in data }
            endpoint = URL(fileURLWithPath: fixture)
            print("Discovering from fixture: \(fixture)")
        } else {
            fetcher = liveFetcher()
            endpoint = option("--endpoint").flatMap(URL.init(string:))
                ?? FTCRefundsAdapter(fetcher: { _ in Data() }).endpoint
            print("Discovering live from: \(endpoint)")
        }
        let adapter = FTCRefundsAdapter(endpoint: endpoint, fetcher: fetcher)
        let discovered = try await adapter.discover()
        let before = queue.leads.count
        queue.ingest(discovered)
        try queue.save()
        print("Discovered \(discovered.count) claimable record(s); "
            + "queue \(before) → \(queue.leads.count). "
            + "\(queue.pending.count) pending review.")

    case "queue":
        let queue = try ReviewQueue(url: queueURL)
        if queue.pending.isEmpty { print("Nothing pending review."); break }
        print("PENDING REVIEW (\(queue.pending.count)):\n")
        for l in queue.pending {
            let missing = l.missingForPublish
            print("  \(l.id)")
            print("    \(l.name)  ·  \(l.caseNo)")
            print("    deadline \(l.deadlineDisplay)  ·  adminURL \(l.adminURL?.absoluteString ?? "—")")
            print("    sources: \(l.sources.map(\.source).joined(separator: ", "))")
            print("    \(missing.isEmpty ? "ready to approve" : "missing: \(missing.joined(separator: ", "))")\n")
        }
        print("Verify each adminURL is the court-appointed administrator, then: feedctl approve <id>")

    case "approve":
        guard let id = args.dropFirst().first else { print("usage: feedctl approve <id>"); exit(2) }
        var queue = try ReviewQueue(url: queueURL)
        if let why = queue.approve(id: id) {
            print("Not approved: \(why)"); exit(1)
        }
        try queue.save()
        print("Approved \(id) — verifiedAt stamped today. Run: feedctl publish")

    case "reject":
        guard let id = args.dropFirst().first else { print("usage: feedctl reject <id>"); exit(2) }
        var queue = try ReviewQueue(url: queueURL)
        queue.reject(id: id); try queue.save()
        print("Rejected \(id).")

    case "publish":
        let queue = try ReviewQueue(url: queueURL)
        guard !queue.approved.isEmpty else { print("No approved leads to publish."); break }
        let current = try? Data(contentsOf: feedURL)

        // S3 gate: the base feed we carry forward must be the genuine
        // signed artifact. A tampered-but-well-formed adminURL would pass
        // structural validation, so verify intent via the signature
        // before trusting those records. Re-publishing before re-signing
        // is a legitimate exception — allow it explicitly.
        if current != nil, !args.contains("--allow-unverified-base") {
            let sigURL = URL(fileURLWithPath: feedURL.path + ".sig")
            let pubURL = feedURL.deletingLastPathComponent().appendingPathComponent("FeedPublicKey.b64")
            let check = FeedIntegrity.verifyFiles(feedURL: feedURL, signatureURL: sigURL, publicKeyURL: pubURL)
            if check != .verified {
                print("Refusing to carry forward an unverified base feed: \(check).")
                print("Re-sign the current feed (./Scripts/sign-feed.sh), or pass "
                    + "--allow-unverified-base to proceed knowingly.")
                exit(1)
            }
        }
        let out = try Publisher.build(
            currentFeedJSON: current,
            approved: queue.approved,
            minAppVersion: "1.0"
        )
        try out.json.write(to: feedURL, options: .atomic)
        print("Wrote \(feedURL.path)")
        print("  \(out.settlementCount) settlements "
            + "(\(out.carriedForward) carried, \(out.newlyPublished) newly published)")
        print("\nNext: ./Scripts/sign-feed.sh   then commit SettlementFeed.json + .sig together.")

    default:
        usage(); exit(2)
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}

// MARK: - helpers

func usage() {
    print("""
    feedctl — Owed feed pipeline
      discover [--fixture <path>] [--endpoint <url>]   run sources → review queue
      queue                                            list leads pending review
      approve <id>                                     confirm + stamp verifiedAt
      reject <id>                                      discard a lead
      publish                                          project approved → SettlementFeed.json
    """)
}

/// Walk up from CWD to the repo root (the directory containing PIPELINE.md).
func repoRoot() -> URL {
    var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    for _ in 0..<8 {
        if FileManager.default.fileExists(atPath: dir.appendingPathComponent("PIPELINE.md").path) {
            return dir
        }
        dir.deleteLastPathComponent()
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
}
