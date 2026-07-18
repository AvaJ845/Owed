# Owed — Settlement Data Pipeline Spec

BLUF: The app is a thin client. The product is a curated, human-reviewed feed of
open class-action settlements with accurate deadlines, eligibility rules, and
official administrator links. Get one deadline or eligibility rule wrong and you
burn trust (or invite liability); this spec builds review into the pipeline.

## Architecture

    [Sources] -> [Ingest workers] -> [Normalize + dedupe] -> [Review queue (human)]
        -> [Publish artifact] -> [CDN / static host] -> [App]
                                         |
                                         +-> [Push alerts (later, §5)]

**Client distribution (shipped today):** the iOS app does **not** query an
authenticated API. After human review, publish a versioned JSON snapshot plus
detached Ed25519 signature; the app verifies, caches, and reconciles. See
`docs/FEED_OPERATIONS.md`. Postgres/FastAPI remain the recommended *publisher*
stack; they emit the signed file — they are not on the interactive read path.

Recommended stack given your existing IP: FastAPI + Postgres + APScheduler/Celery
(same shape as Kestrel's ingestion layer — reuse patterns, not code).

## 1. Sources (in priority order)

| Source | What it gives you | Method |
|---|---|---|
| Claim administrator sites (Epiq, JND, Kroll, Angeion, Simpluris, AB Data) | Ground truth: official form URL, deadline, eligibility, payout terms | Scrape their "active cases" indexes; each admin hosts per-case sites |
| CourtListener / RECAP API (free) | Docket events: preliminary/final approval orders, claim deadlines | REST API, keyword + nature-of-suit filters |
| ClassAction.org, Top Class Actions | Discovery of new settlements early | Scrape/RSS; treat as leads, never as ground truth |
| FTC redress programs (ftc.gov/refunds) | Government refund programs (no perjury-risk profile, great content) | Scrape; low volume, high trust |
| State AG settlement pages | Regional settlements | Scrape top 10 states by population |

Rule: a settlement is never published from an aggregator alone. It must be
confirmed against the administrator site or a court document.

## 2. Ingestion

- One worker per source class; run every 6h (admin sites) / 24h (aggregators).
- Emit raw records to a `leads` table with source, url, scraped_at, raw_html hash.
- Change detection by content hash — re-review triggers only when the page changes.

## 3. Normalization schema (the API contract the app already consumes)

    settlement {
      id, case_no, court, name, category,
      payout_lo, payout_hi, payout_terms,
      deadline_date, receipt_required (bool),
      eligibility[] (plain-language criteria),
      admin_url (official claim form ONLY),
      status: lead | in_review | published | closed | rejected,
      sources[] (provenance for every field)
    }

Every field carries provenance. If deadline came from an aggregator but not yet
confirmed on the admin site, status stays `in_review`.

## 4. Human review (non-negotiable)

- A settlement enters the app only after a reviewer confirms: deadline, payout
  terms, eligibility language, and that admin_url is the court-appointed
  administrator (not an affiliate or law-firm lead-gen page).
- Review UI can be a simple internal Retool/Streamlit table. 10–20 new
  settlements/month nationally at meaningful size — this is an hour a week,
  not a team.
- Closing-soon re-verification: any settlement entering the 14-day window gets
  re-checked automatically (page hash) and flagged if changed.

## 5. Alerts

- Push via Expo Notifications (already in the scaffold).
- Triggers: new settlement published (lifetime users), tracked claim T-7 and
  T-1 days, payout distribution announced.
- Server-side scheduled job scans deadlines nightly; no client-side polling.

## 6. Compliance guardrails (product decisions, already in the app)

1. Never file on the user's behalf in v1 — deep-link to the official form.
   ("File it for me" as a later paid feature needs real legal review first.)
2. Eligibility attestation gate before any claim starts (built).
3. "No receipt needed" language, never "no proof" — describes the settlement's
   documentation tier, doesn't invite ineligible filing.
4. Only link court-appointed administrators. Never lead-gen intermediaries.
5. Disclose plainly: Owed is not a law firm and doesn't provide legal advice.

## 7. Cost to run (solo-operator scale)

- Hosting: single small VPS or Azure Container App — <$25/mo.
- CourtListener API: free tier is sufficient at this volume.
- Push: Expo free tier.
- The moat is the review discipline and freshness, not infra spend.

## 8. Monetization ladder

1. v1: $5.99 lifetime (alerts + tracking). Anti-subscription is the marketing.
2. v1.5: anonymized "claims filled" momentum stats as social proof.
3. v2 (post-legal-review): "file it for me" convenience fee per claim, or
   percentage-free flat $2–3 — keeps the not-predatory brand intact.
