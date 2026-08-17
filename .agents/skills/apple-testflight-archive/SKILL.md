---
name: apple-testflight-archive
description: Pre-upload gate for Apple TestFlight / App Store Connect archives. Walk the checklist for purpose strings (ITMS-90683), Watch icons, category, export compliance (ITSAppUsesNonExemptEncryption, the ASC "App Encryption Documentation" questionnaire), bundle IDs, platformFilters, App Intent "apple" wording (ITMS-90626), empty iCloud environment (ITMS-90046), and the 150/day upload cap (ITMS-90383). Use when preparing a TestFlight archive, diagnosing "Preparing build for App Store Connect failed", Organizer "Uploaded to Apple" but TestFlight No Builds, the App Encryption Documentation page, missing encryption/compliance keys, or an ASC email (ITMS-90683, 90626, 90242, 90129, 90046, 90362, 90383, 90391). Also /apple-testflight-archive.
---

# Apple TestFlight archive

Walk this **before** every first upload and after adding Watch, Share, Speech, or location.
A green local `xcodebuild` is not enough — ITMS only runs on a real upload.
Organizer **"Uploaded to Apple"** is not TestFlight. The **ASC email** and
`asc builds uploads list --app <id>` are where the ITMS code appears.

Do **not** spray TestFlight retriggers: the account cap is ~**150 binary uploads/day**
(ITMS-90383). Each platform archive (iOS / macOS / tvOS / visionOS) counts as one.

`Tools/check-project.sh` catches the mechanical items. This list is the full gate.
Icon generation: `apple-app-icons` skill. New-app setup: `apple-app-onboarding`.

## 0. Account / timing

- [ ] Under the daily upload cap (wait 24h after ITMS-90383)
- [ ] App record exists and `asc apps view` resolves
- [ ] Xcode Cloud product enrolled **after** the app record propagated
- [ ] Shared app scheme committed (`xcshareddata/xcschemes/`)
- [ ] TestFlight workflow exists, manual start enabled, auto build numbers on
- [ ] Private package deps granted on **this** product
- [ ] `Package.resolved` committed (root + workspace copy) if auto-resolve is off

## 1. Signing & IDs

- [ ] Team `SP7UUHBXPL` on every shipping target
- [ ] Main bundle ID registered (`asc bundle-ids list --paginate`)
- [ ] Every embedded ID registered: Watch, widget, NSE, NCE, Share, iMessage, App Clip, ExtensionKit
- [ ] Capabilities on each App ID match entitlements actually claimed
- [ ] Entitlements file wired (`CODE_SIGN_ENTITLEMENTS`) on Debug **and** Release
- [ ] Claim only what the code uses (no speculative iCloud / App Groups)
- [ ] If CloudKit is claimed: `com.apple.developer.icloud-container-environment` =
      `Production` and a real container ID. An empty `""` environment fails
      **every** platform (ITMS-90046 on iOS / macOS / tvOS / visionOS). Empty
      `icloud-container-identifiers` + CloudKit services is the usual cause —
      Xcode still signs the empty environment key. Drop unused CloudKit instead.
- [ ] App Clip IDs not pre-created without the App Clip capability
- [ ] Watch `WKCompanionAppBundleIdentifier` equals the parent app ID (ITMS-90538)

## 2. Info.plist / compliance (one home per key)

Never set the same key in both `Info.plist` and `INFOPLIST_KEY_*`.
Plist file is the studio home. First-class apps keep `ITSAppUsesNonExemptEncryption`
in the main `Info.plist` (create the file beside the `.xcodeproj` if the target was
generate-only). `INFOPLIST_KEY_*` is for keys that vary per configuration.
An open Xcode window can re-add `INFOPLIST_KEY_ITS*` and rewrite/strip the plist
on save — re-check both homes after any Xcode session.

- [ ] `ITSAppUsesNonExemptEncryption` = NO in the **main app Info.plist** (not
      `INFOPLIST_KEY_*`). Required to skip the **App Encryption Documentation** questionnaire.
- [ ] `LSApplicationCategoryType` set (macOS is invalid without it — ITMS-90242)

### Export compliance / App Encryption Documentation

ASC **Distribution → App Encryption Documentation** asks:

> What type of encryption algorithms does your app implement?

| Radio option | When |
|---|---|
| Proprietary / not accepted as standard (IEEE, IETF, ITU, …) | Custom crypto you invented |
| Standard algorithms **instead of or in addition to** Apple OS crypto | You ship your own AES/TLS/etc. |
| Both of the above | Both |
| **None of the algorithms mentioned above** | HTTPS/TLS, CloudKit, Keychain, CryptoKit **as provided by the OS only** |

Studio apps that only use OS/exempt encryption declare **None** — same fact as
`ITSAppUsesNonExemptEncryption = NO` (`<false/>` in a plist). That is a legal
declaration; confirm before setting it.

The yellow callout on that page is the bypass: put the key in the uploaded
binary and ASC does not make you fill the form on every upload.

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

Wire it with `GENERATE_INFOPLIST_FILE = YES` plus `INFOPLIST_FILE = Info.plist`
on the main target (Debug and Release). Sit the file **beside** the `.xcodeproj`,
not inside a synchronized source folder, or Xcode copies it as a resource
("duplicate output file"). Do not also set `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption`.

The key must be in the **build you attach**. The form still appears if you
selected an older binary from before the key existed, or if you are on the
version listing (not the upload) — then answer **None of the algorithms
mentioned above**.

`Tools/check-project.sh` fails when the key is in neither home.
- [ ] `LSSupportsOpeningDocumentsInPlace` if `CFBundleDocumentTypes` exists
- [ ] `CFBundleDisplayName` on the **app** (not an Apple name)
- [ ] Watch display name is **not** `Watch` (ITMS-90129)
- [ ] `PRODUCT_NAME` / `CFBundleName` ≤15 chars and not an Apple app name
      (`Stocks` / `Watch` / `Music` fail ITMS-90129 even when the display name is fine —
      `CFBundleName` is always derived from `PRODUCT_NAME`)
- [ ] Share/Action: no `<string>TRUEPREDICATE</string>` (ITMS-90362)
- [ ] App Intent `title` / `IntentDescription` must not contain **"apple"**
      (ITMS-90626). Comments and `perform()` dialogs are fine; the extracted
      metadata is what Apple scans. "Apple Intelligence" is the usual trip.
- [ ] `PrivacyInfo.xcprivacy` in the app target (UserDefaults → `CA92.1` at minimum)

### Purpose strings — required if the **binary** references the API (ITMS-90683)

Apple scans the linked binary, not the happy path. A `#if` that still compiles the
symbol, or an SDK that imports it, still needs the key.

| If the code / entitlement has | Required key |
|---|---|
| `SFSpeechRecognizer` / Speech framework | `NSSpeechRecognitionUsageDescription` |
| `AVAudioRecorder` / live mic capture | `NSMicrophoneUsageDescription` |
| `MusicAuthorization` / MusicKit library | `NSAppleMusicUsageDescription` |
| `HMHomeManager` / HomeKit | `NSHomeKitUsageDescription` |
| `CLLocationManager` / `CLMonitor` | `NSLocationWhenInUseUsageDescription` (and Always if used) |
| Camera / photo library / contacts / Bluetooth / motion | matching `NS*UsageDescription` |

`AVSpeechSynthesizer` (TTS only) does **not** need a speech key. Recognition does.

## 3. Icons (pass `actool` **per catalog**, not just the main app)

- [ ] iOS/macOS: `.icon` and/or filled `AppIcon.appiconset`
- [ ] **Watch target** `AppIcon.appiconset`: 1024 `watchos` slot has a PNG on disk
      (main `.icon` does **not** fill this; empty = iOS-only TF fail —
      ITMS-90391 / ITMS-90713)
- [ ] tvOS brandassets: Back + Top Shelf **fully opaque at every scale**
      (`sips -g hasAlpha` → no on both `@1x` and `@2x`). Front layers keep alpha.
      `sips` BMP/JPEG round-trip often **leaves** the alpha channel — write a PNG
      with no alpha (`kCGImageAlphaNoneSkipLast`) and re-check.
- [ ] visionOS solidimagestack: Back fully opaque (same flatten rule)
- [ ] Per-SDK `ASSETCATALOG_COMPILER_APPICON_NAME` on the multiplatform target
- [ ] iMessage stickersiconset fully populated, opaque, including 1024×768
- [ ] ExtensionKit `.appex` embedded in `Extensions/`, not `PlugIns/`

```sh
xcrun actool --compile /tmp/actool-watch --platform watchsimulator --target-device watch \
  --minimum-deployment-target 26.0 --app-icon AppIcon \
  --output-partial-info-plist /tmp/actool-watch/partial.plist \
  path/to/Watch/Assets.xcassets
plutil -p /tmp/actool-watch/partial.plist   # expect CFBundlePrimaryIcon
```

## 4. Embeds & platforms

- [ ] iOS-only extensions: `platformFilter = ios` on embed **and** dependency
- [ ] Widget: `platformFilters = (ios, macos, xros)` if it actually runs there
- [ ] Watch embed: `platformFilter = ios` (Embed Watch Content)
- [ ] Deployment targets consistent across app / Watch / every extension / `Package.swift`
- [ ] `#if canImport(X)` is not treated as "API exists" (gate tvOS/watchOS-unavailable APIs)

## 5. Local proof (before spending a cloud upload)

```sh
Tools/check-project.sh
swift test
Tools/lint.sh
xcodebuild build -project App/App.xcodeproj -scheme App \
  -destination 'generic/platform=iOS'
# repeat macOS / tvOS / visionOS
```

- [ ] Doctor healthy
- [ ] Package tests green
- [ ] Each shipping platform compiles
- [ ] Built app: `plutil -extract CFBundleDisplayName` / Watch companion ID look right

## 6. Upload (each platform = 1 toward the daily cap)

- [ ] Trigger **one** TestFlight workflow on `main`, or one **new** local archive
      (do not re-upload an old Organizer row from before the fix)
- [ ] Read the **ASC email**, not just Xcode Cloud's "Preparing build… failed"
- [ ] If only iOS failed → Watch icon / iOS-only appex first
- [ ] If only macOS failed → category
- [ ] If tvOS/visionOS failed with opacity → flatten Back/Top Shelf (every scale)
- [ ] Do not retrigger the whole studio on a single-key miss

### Organizer green, TestFlight empty

Transporter accept ≠ processed build. `asc builds list --app <id>` stays empty
and testers show **No Builds Available** until processing **succeeds**.

```sh
asc builds uploads list --app <id>          # FAILED + ITMS code per platform
asc builds list --app <id>                  # empty = nothing processed
asc builds count --app <id>                 # 0 = TestFlight has nothing to show
```

Look at TestFlight → **Builds** (or Distribution → iOS), not the Testers tab.
Testers stay empty until a processed build exists **and** is in the group.

A `FAILED` upload does not create a TestFlight build. Bump
`CURRENT_PROJECT_VERSION` and archive again after the fix — Organizer will
otherwise re-send the rejected binary. `asc builds next-build-number` only
sees **processed** builds, so it can still say `1` after many failed uploads.

## 7. After a green TestFlight build

- [ ] Internal testers can install
- [ ] Export-compliance answered by `ITSAppUsesNonExemptEncryption` in **this** build
      (ASC App Encryption Documentation should not reappear; if it does, pick **None**)
- [ ] Then listing work: apple-app-onboarding `references/app-store-listing.md`
