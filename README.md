# Owed

**BLUF:** A thin iOS client for a curated, human-reviewed feed of open class-action settlements. The product is editorial correctness and privacy — not networking cleverness. A wrong deadline or administrator URL is user harm.

Native SwiftUI · StoreKit 2 · signed static feed · on-device matching · attestation before claim start.

| Doc | Purpose |
|-----|---------|
| **[docs/BUILD.md](docs/BUILD.md)** | Build, test, smoke, App Store packet — engineering definition of done |
| **[docs/FEED_OPERATIONS.md](docs/FEED_OPERATIONS.md)** | Sign, publish, incident response for the settlement feed |
| **[PIPELINE.md](PIPELINE.md)** | Ingest → normalize → **human review** → publish (server-side intent) |

---

## Quick start

```bash
git clone https://github.com/AvaJ845/Owed.git
cd Owed
open Owed.xcodeproj
# Xcode 16+: select Development Team, scheme Owed → ⌘R
# Optional fonts: ./Scripts/fetch-fonts.sh
# Tests: ⌘U  (see docs/BUILD.md)
```

| | |
|--|--|
| Bundle ID | `AvaResearchLLC.Owed` |
| Lifetime IAP | `AvaResearchLLC.Owed.lifetime` ($5.99 non-consumable) |
| Min iOS | 17.0 |
| Feed (today) | Signed JSON on `main` via GitHub raw (`FeedStore.remoteURL`) |

CLI build/test and Cursor `/run-sim`: see [docs/BUILD.md](docs/BUILD.md).

---

## System shape

```
                    ┌─────────────────────────────────────┐
  Human review ──►  │ SettlementFeed.json + .sig (CDN/git) │
                    └─────────────────┬───────────────────┘
                                      │ public GET (no user data)
                                      ▼
┌──────────────┐   verify Ed25519    ┌──────────────────────┐
│ Bundled JSON │◄──disk last-good────│ FeedStore + Signing  │
│ (app binary) │                     └──────────┬───────────┘
└──────────────┘                                │
                                                ▼
                                     AppModel.reconcile
                          (snapshots · alerts · calendar · notices)
                                                │
                                                ▼
                                     Find / Claims / Alerts (SwiftUI)
```

**Client contracts (do not casually weaken):**

1. Remote feed must verify under `FeedPublicKey.b64` or it never replaces last-good.
2. Envelope `schemaVersion` is strict; individual bad records are dropped.
3. Tracked settlements are snapshotted locally — the feed cannot erase a user’s claim.
4. Match quiz stays on device; feed session is ephemeral and cookieless.
5. Claims require eligibility checks + perjury attestation; app never files.

---

## Repository map

```
Owed/                 app sources (filesystem-synced Xcode target)
OwedTests/            Swift Testing — decode, reconcile, signing
docs/                 BUILD + FEED_OPERATIONS (this engineering bar)
Scripts/sign-feed.sh  only supported signing entrypoint
Scripts/keys/         private key (gitignored — back up offline)
PIPELINE.md           upstream data pipeline spec
```

`.cursor/` holds agent skill `/run-sim` and local MCP config (`mcp.json` gitignored). Neither ships in the App Store binary.

---

## Feed publish (operators)

After human review of `Owed/Resources/SettlementFeed.json`:

```bash
./Scripts/sign-feed.sh
git add Owed/Resources/SettlementFeed.json Owed/Resources/SettlementFeed.json.sig
git commit -m "Publish settlement feed"
git push origin main
```

Full runbook, key rotation, and incident response: **[docs/FEED_OPERATIONS.md](docs/FEED_OPERATIONS.md)**.

---

## Architecture decisions (compressed)

| Decision | Why |
|----------|-----|
| Signed static JSON, not a personalized API | Settlements change slowly; review is the moat; no user data on the wire |
| StoreKit 2 in-process | One non-consumable — an SDK is unjustified cost and privacy surface |
| Write-only EventKit | Privacy copy (“never reads your calendar”) beats silent event mutation |
| Local T-7/T-1 (+ new-match) before push | Paid perk is real offline; push later is additive (PIPELINE §5) |
| `@MainActor` `AppModel` + refresh overlap guard | UI state is the product surface; concurrent reconciles are a correctness bug |
| Privacy manifest with zero collection | Matches the product; required-reason APIs declared (`CA92.1`) |

---

## Before you ship a binary

Work the checklist in [docs/BUILD.md §7](docs/BUILD.md) — signing team, icon, IAP, review notes, privacy manifest, production feed content (not example hosts), CDN cutover when you leave GitHub raw.
