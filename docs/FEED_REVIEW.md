# Settlement feed review log

**Publish date:** 2026-07-18  
**Reviewer role:** editorial verification against official administrator sites / court notices (not legal advice).  
**Rule:** every `adminURL` is the court-linked settlement site, not an aggregator.

| id | Official site | Claim deadline | Sources checked | Status |
|----|---------------|----------------|-----------------|--------|
| `disney-online-tv-biddle` | https://www.onlinetvsettlement.com/ (Epiq) | 2026-09-08 | Official site summary; ClassAction.org notice PDF (Biddle v. Disney, N.D. Cal. 5:22-cv-07317); payout left as honest pro-rata range (final TBD) | Open |
| `google-assistant-privacy` | https://www.googleassistantprivacylitigation.com/ (A.B. Data) | 2026-08-27 | Official FAQ + long-form notice PDF (N.D. Cal. 4:19-cv-04286); Plan of Allocation; counsel estimates for lo/hi | Open (HTTPS 200) |
| `circle-k-gas-express-2024` | https://www.gasexpressdatasettlement.com/ | 2026-09-03 | Official home + FAQ; ClassAction.org notice/agreement PDFs; Fulton County GA 25EV012357 | Open (HTTPS 200) |
| `fastwyre-tcpa` | https://www.fastwyretcpasettlement.com/ | 2026-08-03 | Official settlement home (Hasenberg v. SP Data Digital / Fastwyre, Cuyahoga County Ohio CV-25-127556) | Open (HTTPS 200) |
| `fanatics-handling-fee` | https://handlingfeesettlement.com/ | 2026-08-27 | Official settlement home (Cavanaugh v. Fanatics, Miami-Dade 2026-001293-CA-01); voucher terms $5×2 | Open (HTTPS 200) |

## Deliberate product choices

- **Payout ranges** for pro-rata funds (Disney, Google) use published counsel/estimate bands, not invented fixed checks. Copy in `payoutTerms` says amounts are not fixed.
- **`receiptRequired`:** true only where the primary high-value path needs documentation (Google Purchaser Class). Circle K’s $50 alternate path is no-proof; documented losses are optional.
- **Fanatics** has empty `matchKeys` (no quiz life-fact fits sports merch) — still listed under **All**.
- **Demo ids `s1`–`s5` retired** — never reuse for different cases.
- **Closed windows excluded** (e.g. LastPass claim deadline 2026-07-02 already passed as of this review).

## Re-verify before the next publish

Re-open each official URL, confirm the claim deadline has not moved, bump `verifiedAt` / `generatedAt`, run `./Scripts/sign-feed.sh`, commit JSON + `.sig` together.
