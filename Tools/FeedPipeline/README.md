# Owed feed pipeline (`feedctl`)

Ingestion tooling for the settlement feed — implements the **discover →
normalize/dedupe → human review → publish** path in
[`../../PIPELINE.md`](../../PIPELINE.md) §1–4. A build/ops tool; it is
**not** part of the app binary.

## Why it's built this way

- **One schema, no drift.** `Sources/FeedPipelineCore/Vendored/` symlinks
  the app's canonical `Settlement` / `SettlementFeed` / `MatchProfile`
  sources. On `publish`, the projected feed is decoded back through the
  app's own `SettlementFeed.decode` — the exact strict validator the
  client runs (https-only `adminURL`, sane payout range, non-empty
  eligibility, `yyyy-MM-dd` dates). **The pipeline cannot emit a feed the
  app would reject.**
- **Human review is a hard gate.** Adapters only ever produce *leads*
  (`.lead` / `.inReview`). A record gets `verifiedAt` and enters the feed
  only via `approve` — a person confirming it against the administrator
  (PIPELINE.md §4).
- **Signing stays put.** `publish` writes `SettlementFeed.json`; the
  private key never touches this tool. You still run
  [`../../Scripts/sign-feed.sh`](../../Scripts/sign-feed.sh).

## Sources (the Fellow-recommended selection)

| Source | Role | Status |
|---|---|---|
| **FTC redress** (`FTCRefundsAdapter`) | Anchor discovery — government-authoritative, claimable programs only | Built |
| **CourtListener** (`CourtListenerVerifier`) | Deadline/case cross-check — advisory, never a gate | Built (needs membership token) |
| **Admin firms** (Epiq/Angeion/JND/Kroll) | Discovery — same `SourceAdapter` protocol slot | Adapter slot ready |
| Aggregators, state AGs, PACER-direct | **Omitted** by design — noise/ToS/cost for zero unique signal | — |

## Operator runbook

```sh
cd Tools/FeedPipeline
swift build
BIN=$(swift build --show-bin-path)/feedctl

# 1. Discover leads (fixture today; point --endpoint at the live FTC export once finalized)
$BIN discover --fixture Fixtures/ftc-refunds-sample.json

# 2. Review what's pending — open each adminURL, confirm it's the court-appointed administrator
$BIN queue

# 3. Confirm or discard (stamps verifiedAt = today on approve)
$BIN approve ftc-vonage-refunds
$BIN reject  some-lead-id

# 4. Project approved leads into the feed (validated by the app decoder)
$BIN publish

# 5. Sign + commit together (existing tooling)
cd ../.. && ./Scripts/sign-feed.sh
git add Owed/Resources/SettlementFeed.json Owed/Resources/SettlementFeed.json.sig && git commit
```

State lives in `Pipeline/review-queue.json` at the repo root (leads +
reviewer decisions; discovery never overwrites a human decision).

## Tests

`swift test` — case-number normalization, dedupe (provenance union +
reviewer-decision preservation), the FTC claimable-only filter, and the
two load-bearing publish gates: an approved lead round-trips through the
app decoder, and an `http://` `adminURL` is rejected at publish.

## Finishing the live wiring

- **FTC:** `FTCRefundsAdapter.endpoint` is a placeholder. Finalize the
  real export URL/selector at `ftc.gov/exploredata`; the field mapping is
  already tested against `Fixtures/ftc-refunds-sample.json`.
- **CourtListener:** pass a membership API token to
  `CourtListenerVerifier`; wire it into `discover` as an enrichment pass
  once you have one. It stays advisory — a `.notFound` never drops a
  lead (state-court and FTC administrative settlements have no federal
  docket).
- **Admin-firm adapters:** implement `SourceAdapter` per firm; their
  output flows through the same dedupe + review gate.
