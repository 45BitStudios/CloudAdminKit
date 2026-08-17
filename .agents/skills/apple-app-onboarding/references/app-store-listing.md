# App Store listing prep — the last mile after TestFlight

Onboarding gets the app *building and uploading*; this reference covers getting it *submitted*.
Run through it once per app, after the first TestFlight build is live. Where the installed
`asc` version supports a step, prefer it (metadata as reviewable files in the repo beats
retyping into the ASC UI 15–20 times); verify subcommands with `asc --help` rather than
guessing flags.

## 1. Metadata

Draft in the repo (e.g. `docs/app-store/metadata.md`), then push via asc where supported:

- **Name** (30 chars) and **subtitle** (30 chars) — subtitle is indexed for search.
- **Keywords** (100 chars, comma-separated, no spaces wasted) — don't repeat words already in
  name/subtitle; they're indexed separately.
- **Description** (4000 chars) and **promotional text** (170 chars — updatable without a new
  build; use it for events/sales).
- **What's New** per version. **Support URL** and **privacy policy URL** (required) — these
  are the app's IkigaiServer marketing pages (`https://<domain>/support`, `/privacy`), stood
  up during the tenant phase (`ikigai-server.md` §4), so they exist before the listing does.
- Categories: primary + secondary. The `LSApplicationCategoryType` in the build and the ASC
  category should agree.

## 2. Privacy nutrition label (NOT the same as PrivacyInfo.xcprivacy)

The ASC privacy questionnaire ("Data Used to Track You / Linked to You / Not Linked to You")
is a separate declaration from the bundled privacy manifest. Derive answers from what the app
actually links:

- No analytics/ads SDK, no accounts, purchases via StoreKit/RevenueCat → typically "Purchases"
  (linked or not linked depending on account model) and possibly "Identifiers" if the store
  SDK uses an app user ID. Check the SDK vendor's published disclosure (RevenueCat documents
  theirs) instead of guessing.
- Game Center: Apple collects under its own privacy terms, but gameplay data your app stores
  still counts if you keep it server-side (local + iCloud KVS/private CloudKit generally
  doesn't have to be declared as collection — confirm against current App Review guidance).
- Answers must be re-reviewed whenever a new SDK lands — note that in the PR that adds one.

## 3. Screenshots — per platform, per size class

Requirements (slot list shows in ASC → the app → the platform tab; sizes shift with new
devices, so treat ASC as ground truth):

- **iOS**: 6.9" iPhone set required (6.5" legacy accepted); iPad 13" set required if the app
  runs on iPad. 3–10 images per set.
- **macOS**: 16:10 (e.g. 2880×1800). **tvOS**: 3840×2160 (or 1920×1080). **visionOS**:
  3840×2160. **watchOS**: current-device sizes if the watch app is featured standalone.
- Automate captures with `xcrun simctl io booted screenshot` per simulator, or an XCUITest
  that walks the key screens — worth scripting once for 15–20 apps (`Tools/screenshots.sh`
  is a good home; keep outputs in `docs/app-store/screenshots/<platform>/`).
- App Previews (video) are optional; skip for v1.

## 4. Age rating, pricing, availability

- Age rating questionnaire: answer per actual content (a card battler with "fantasy violence"
  usually lands 9+/12+ — answer honestly, mismatches get flagged in review).
- Pricing (free/paid) + in-app purchases: IAP/subscription products need their own ASC
  records, screenshots, and review notes; RevenueCat offerings map to these product IDs.
- Availability: territories and pre-order if staged.

## 5. Review notes & the submission itself

- **App Review notes**: demo account if anything is gated, and one paragraph explaining
  anything unusual (background audio, local network use, Bluetooth) so the reviewer isn't
  surprised by permission prompts. The usage-description strings must match what the app
  visibly does.
- Attach the build (a TestFlight build ≤ 90 days old), confirm export compliance is answered
  by `ITSAppUsesNonExemptEncryption` in the build, submit each platform.
- **Release Xcode rule**: App Store release builds must come from a *release* Xcode — a
  beta-pinned Xcode Cloud workflow can ship TestFlight but not the store (gotchas §10).
  Repin the workflow before the submission build if it was on "Latest Beta or Release".

## Checklist

- [ ] Name/subtitle/keywords/description drafted in repo, pushed via asc
- [ ] Support + privacy URLs live
- [ ] Privacy nutrition label answered from actual SDK list
- [ ] Screenshots for every shipping platform uploaded
- [ ] Age rating, pricing, territories set
- [ ] IAP products created + reviewed (if any)
- [ ] Review notes + demo access written
- [ ] Workflow pinned to a release Xcode for the submission build
