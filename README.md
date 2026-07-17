# Owed — native iOS (SwiftUI)

Native SwiftUI port of the Owed Expo scaffold. Same design language
(engraved banknote, docket stamps, mono case numbers), same compliance
posture (eligibility + perjury attestation gate, official-administrator-only
links), but idiomatic iOS: StoreKit 2, `@Observable` state, local deadline
notifications, haptics, Dynamic Type-friendly layout.

## Run it

1. Open `Owed.xcodeproj` in Xcode 16+.
2. Select your team under Signing & Capabilities (bundle id is
   `com.example.owed` — change it to yours).
3. Optional but recommended: `./Scripts/fetch-fonts.sh` to pull the brand
   fonts (Fraunces / Public Sans / IBM Plex Mono, all SIL OFL). Without them
   the app falls back to New York serif / SF / SF Mono automatically.
4. Run on a simulator or device. The shared scheme already points at
   `Owed.storekit`, so the $5.99 lifetime purchase works end-to-end in the
   StoreKit test environment — no App Store Connect setup needed to demo.

## Architecture

    Owed/
      OwedApp.swift          app entry + tab root
      Theme.swift            palette + font fallback + shared card chrome
      Models/Settlement.swift  model + mock feed (production API shape, PIPELINE.md §3)
      State/AppModel.swift   tracked claims (persisted), local T-7/T-1 deadline alerts
      State/StoreManager.swift StoreKit 2: purchase, restore, Transaction.updates
      Views/                 Find, Claims, Alerts, Detail (attestation gate), Paywall, DocketCard

Deliberate calls:

- **StoreKit 2, not RevenueCat.** One non-consumable doesn't justify an SDK.
  `Transaction.currentEntitlements` is the source of truth; the UI mirrors it.
  Restore Purchases is on the paywall (review requirement for non-consumables).
- **Mock feed = production shape.** Swapping `Settlement.mockFeed` for
  `GET /v1/settlements?status=open` is one decoder, zero view changes.
- **Local notifications now, push later.** T-7/T-1 deadline reminders are
  scheduled on-device when a lifetime user tracks a claim, so the paid perk
  is real before the server pipeline (PIPELINE.md §5) ships. Server push
  adds "new settlement" alerts later; needs the aps-environment entitlement.
- **The attestation gate is product, not UI.** The CTA is `disabled` until
  every eligibility box and the perjury attestation are checked, and the
  disclosure names the court-appointed administrator. Keep this intact —
  it's the App Store review story and the liability posture.

## Before submission

- Set a real bundle id + team; update `StoreManager.lifetimeID` and the
  product id in `Owed.storekit` / App Store Connect to match.
- Add a 1024pt app icon to `Assets.xcassets/AppIcon`.
- Create the $5.99 non-consumable in App Store Connect.
- Category: Finance. In review notes, state plainly: browsing is free, the
  app never files claims, all claim links go to court-appointed
  administrators, and starting a claim requires the eligibility attestation.
