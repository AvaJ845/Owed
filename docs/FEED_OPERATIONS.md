# Owed — Feed Operations (Publish, Sign, Incident Response)

**BLUF:** The client is a thin, paranoid consumer of a **human-reviewed, Ed25519-signed JSON artifact**. Settlements change on the order of days. Correctness beats freshness. A CDN or GitHub compromise that injects a fake `adminURL` is a personal-data incident — signing exists so that never becomes a silent client update.

Ingest and review process: [`../PIPELINE.md`](../PIPELINE.md).  
Build/test gates: [`BUILD.md`](BUILD.md).

---

## 1. Trust model

```
[Human review] → sign(private) → publish JSON + .sig
                                      ↓
[App] GET JSON + GET .sig → verify(public) → decode → reconcile
         ↓ fail any step
    keep last-good disk cache, else bundled snapshot
```

| Layer | Trust |
|-------|--------|
| Bundled `SettlementFeed.json` | Trusted as part of the **code-signed app** binary |
| Remote JSON | Trusted **only** if signature verifies under bundled `FeedPublicKey.b64` |
| Disk cache | Last remote bytes that already verified + decoded |
| Private key | Publisher-only; never in the app; never in git |

**Privacy:** the GET carries no user id, no quiz answers, no cookies (`URLSessionConfiguration.ephemeral`). Do not “improve” analytics by attaching query params to the feed URL.

---

## 2. Artifact contract

Published together (same directory / same release):

| File | Format |
|------|--------|
| `SettlementFeed.json` | UTF-8 JSON envelope |
| `SettlementFeed.json.sig` | Base64 encoding of raw 64-byte Ed25519 signature over **exact file bytes** of the JSON |
| `FeedPublicKey.b64` | Base64 of 32-byte Ed25519 public key (shipped **inside the app**) |

### Envelope (schemaVersion 1)

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-07-18T00:00:00Z",
  "minAppVersion": "1.0",
  "settlements": [ /* Settlement */ ]
}
```

| Field | Rule |
|-------|------|
| `schemaVersion` | Integer. Client accepts **only** `1` today. Unknown → reject entire remote feed |
| `generatedAt` | ISO-8601. Client rejects remote if older than current best-available (anti-rewind) |
| `minAppVersion` | Optional. Soft signal (logged); does not blank the UI |
| `settlements[]` | Lossy decode: bad records drop; good records keep. Duplicate `id` → first wins |

### Settlement record (client-enforced)

- `id` — non-empty; **stable forever** once published (keys tracked/received/calendared/snapshots)
- `deadline`, `verifiedAt` — `yyyy-MM-dd` (local midnight semantics via `FeedDay`)
- `adminURL` — must be `https`
- `payoutLo` ≤ `payoutHi`, both ≥ 0
- `eligibility` — non-empty
- `matchKeys` — unknown keys ignored (forward compatible)

Never reuse an `id` for a different case. Prefer marking closed / removing from feed over renumbering; tracked users keep local snapshots.

---

## 3. Canonical signing toolchain

**One path only:**

```bash
./Scripts/sign-feed.sh
```

- Private key: `Scripts/keys/feed_ed25519_private.b64` (**gitignored**)
- Writes/updates: `Owed/Resources/SettlementFeed.json.sig`
- Syncs public key to: `Owed/Resources/FeedPublicKey.b64`

First run creates a keypair if missing. **Back up the private key offline immediately.** Losing it requires a new keypair, an **app update** shipping the new `FeedPublicKey.b64`, and only then publishing feeds signed with the new key — otherwise fielded clients will reject all remotes and stay on last-good/bundled.

Remote URLs (current):

- JSON: `FeedStore.remoteURL` →  
  `https://raw.githubusercontent.com/AvaJ845/Owed/main/Owed/Resources/SettlementFeed.json`
- Signature: sibling `SettlementFeed.json.sig` on the same path prefix

When moving to CloudFront/Cloudflare: change `remoteURL`, publish **both** objects atomically (or signature-after-JSON with short TTL awareness), and keep ETag behavior.

---

## 4. Publish runbook (happy path)

1. Edit `Owed/Resources/SettlementFeed.json` after human review (PIPELINE §4).
2. Set `generatedAt` to now (UTC ISO-8601).
3. Confirm every new/changed row: deadline, payout range honesty, eligibility language, **administrator URL** (court-appointed only).
4. Sign:

   ```bash
   ./Scripts/sign-feed.sh
   ```

5. Verify locally (optional but recommended):

   ```bash
   xcodebuild test -project Owed.xcodeproj -scheme Owed \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
     -only-testing:OwedTests/FeedSigningTests
   ```

6. Commit **JSON + `.sig`** together (and `FeedPublicKey.b64` only if the key was rotated/created).
7. Push `main` (or your publish branch that `remoteURL` tracks).
8. On a device/sim with the app: background → foreground; confirm Alerts freshness stamp and expected content. Tracked users with deadline moves should see Claims notices.

**Do not** push JSON without `.sig`. Clients will refuse the remote and log signature failure — you will think “refresh is broken.”

---

## 5. Client refresh & reconcile (what operators should expect)

Order of operations in `AppModel.refreshFeed` / `FeedStore.refresh`:

1. Conditional GET (ETag / If-None-Match).
2. Fetch detached signature; **verify before decode**.
3. Decode envelope (strict schema) + lossy records.
4. Reject `generatedAt` rewind.
5. Persist cache; reconcile:
   - Update tracked snapshots for ids still in feed
   - Deadline change → local alert reschedule (lifetime), calendar best-effort update or clear for re-add, user-visible notice
   - New ids vs previous list → local “new match” notification for lifetime + profile match
6. Foreground + `BGAppRefreshTask` both call this path; BG is best-effort and **not** a correctness SLA.

---

## 6. Incident response

### 6.1 Bad feed published (wrong deadline / wrong admin URL)

1. Fix JSON from source of truth (administrator site / court order).
2. Bump `generatedAt`, resign, push immediately.
3. Do **not** yank the file to 404 — clients keep last-good; a 404 only blocks recovery for users who never cached the fix.
4. If harm was material: note in release / support copy; consider App Store expedited if the bad URL was in a **bundled** build (binary update required).

### 6.2 Signature failure in the wild (clients not updating)

Check in order: `.sig` missing on CDN; JSON and `.sig` from different publishes; public key rotated in repo but app not updated; proxy altering bytes.

### 6.3 Private key compromise

1. Generate new keypair (`sign-feed.sh` after moving aside old `Scripts/keys/`).
2. Ship app update with new `FeedPublicKey.b64`.
3. Only after sufficient upgrade: publish feeds under the new key.
4. Treat old key as burned; do not resign production with it.

### 6.4 Schema break

Bump `schemaVersion` only with a client that understands it. Old clients will reject the remote envelope and remain on last-good — plan dual-publish or forced upgrade via `minAppVersion` messaging before breaking.

---

## 7. What not to build (explicitly)

- Personalized feed APIs that accept quiz answers or device ids
- Soft-fail “verify if present” for remote signatures in production
- Reusing settlement `id`s
- Publishing aggregator-only URLs as `adminURL`
- Adding analytics SDKs that exfiltrate match profile data without rewriting every privacy surface in the app

---

## 8. Operator checklist (print / pin)

- [ ] Human review done (deadline, terms, eligibility, admin URL)
- [ ] `generatedAt` bumped
- [ ] `./Scripts/sign-feed.sh`
- [ ] `FeedSigningTests` green
- [ ] JSON + `.sig` committed and pushed together
- [ ] Spot-check on simulator after foreground refresh
- [ ] Private key backup still valid
