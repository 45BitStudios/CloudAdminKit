# Multiplatform Apple app + Xcode Cloud + TestFlight — Gotchas

Hard-won notes from shipping a multiplatform SwiftUI app (iOS/iPadOS/tvOS/macOS/visionOS +
watchOS, with a local Swift Package and several app extensions) through Xcode Cloud CI and
TestFlight. Ordered roughly by when they bite. Symptoms are the exact errors seen so future-you
can grep for them.

---

## 1. Local Swift Package reference must resolve inside the clone

**Symptom (Xcode Cloud):**
`Could not resolve package dependencies: the package at '/Volumes/workspace/<Name>' cannot be
accessed (... doesn't exist in file system)`

**Cause:** The app project referenced a local package with a relative path like
`../../MyKit`. It resolved on the dev machine only because the checkout folder happened to be
named `MyKit`. Xcode Cloud checks out to a **fixed** path (`/Volumes/workspace/repository`), so
any `..` traversal that escapes the repo root breaks.

**Fix:** Reference local packages with a path relative to the repo, never one that climbs above
it. If the package lives at the repo root and the `.xcodeproj` is in a subfolder, the reference
is `..` — not `../../<RepoName>`. Verify: the path must resolve correctly regardless of what the
checkout directory is named.

---

## 2. Embedded extensions can't have a higher deployment target than the host

**Symptom:** archive/validation failure, or extensions silently unavailable on the host's min OS.

**Cause:** Bumped the app to iOS 26 but left extensions/Watch at 27 (mixed values in pbxproj —
each target *and* each build config has its own).

**Fix:** Set the min deployment target consistently across **every** target (app, each extension,
Watch app, Watch widget) and both Debug/Release. Grep the pbxproj for
`*_DEPLOYMENT_TARGET = ` and confirm they all match. `Package.swift` platforms are separate —
update those too.

**That grep has a blind spot: an *absent* setting is not a passing one.** Xcode's multiplatform
template puts `appletvos` in `SUPPORTED_PLATFORMS` while writing **no** `TVOS_DEPLOYMENT_TARGET`
at all, so tvOS silently inherits the SDK's default floor — a *beta* SDK's, if that's what
created the project. Homestead onboarded with iOS/macOS/visionOS/watchOS pinned at 26.0 and tvOS
resolving to 27.0, with nothing in the pbxproj to grep for: no mixed value, no wrong value, just
silence. Verify what the build **resolves**, not what the file says:

```sh
xcodebuild -project App/App.xcodeproj -target App -showBuildSettings | grep _DEPLOYMENT_TARGET
```

`check-project.sh` now warns when `SUPPORTED_PLATFORMS` builds a platform whose deployment target
is never set. It keys off `SUPPORTED_PLATFORMS` rather than flagging every unset platform,
because an unset floor for a platform the target doesn't build is inert (the app target reports
`WATCHOS_DEPLOYMENT_TARGET` from the SDK and it means nothing).

---

## 3. Guarding OS-version-only APIs: gate the whole declaration, not just the body

When min-deployment < the OS that introduced an API, you must `#if`/`@available`-guard it.
Two traps:

- **`canImport(X)` is not the same as "API is available."** e.g. `#if canImport(CoreSpotlight)`
  is **true on tvOS**, but `IndexedEntity` / `CSSearchableItemAttributeSet` / `CSSearchableIndex`
  are *unavailable* on tvOS → compile error. Use `#if canImport(CoreSpotlight) && !os(tvOS)`.
- **Guard the signature, not only the body.** A function whose *return type* or protocol
  conformance is an unavailable type still fails even if the body is `#if`-guarded. Wrap the
  entire declaration:
  ```swift
  #if canImport(UserNotifications) && !os(tvOS)   // UNNotificationAttachment unavailable on tvOS
  private func portraitAttachment(...) -> UNNotificationAttachment? { ... }
  #endif
  ```
- **A symbol used unconditionally must be defined unconditionally.** If a helper is inside
  `#if !os(tvOS)` but a *non-guarded* caller uses it → "cannot find X in scope." Move the helper
  out of the guard.
- SwiftUI `Commands` / `CommandMenu` and the `.commands { }` scene modifier are **unavailable on
  tvOS and watchOS** — gate both the `Commands` type and the `.commands {}` call site.

**How to find them fast:** build the app for the suspect platform locally (see §11) — the compiler
lists every "only available in X" / "unavailable in Y" at once, far faster than one cloud run per
error. For runtime-gated new APIs on a lower min target, a reusable `ViewModifier` that branches on
`if #available(iOS N, *)` is the clean pattern (it's `#available`, *not* a macro).

---

## 4. Package tests don't run natively in Xcode Cloud when the package is local to an app project

**Symptom:** `Scheme <PkgScheme> is not currently configured for the build action` (using a
SwiftPM package scheme in a workflow whose container is the app `.xcodeproj`), or
`There are no test bundles available to test` (app-scheme references to package test targets).

**Cause:** A SwiftPM package test scheme uses `ReferencedContainer = "container:"` (the package
itself); it can't share the app's `.xcodeproj` container that a single workflow builds. And
adding package test targets to the *app* scheme's Test action doesn't reliably build the test
bundles.

**Fix that works:** run tests with **`swift test`** from a `ci_scripts/ci_post_clone.sh` — a
non-zero exit fails the build, so it gates CI. Reliable, no scheme gymnastics. Trade-off: results
appear in the build log, not as native ASC test-report tiles.
```sh
#!/bin/sh
set -e
cd "${CI_PRIMARY_REPOSITORY_PATH:-$CI_WORKSPACE/repository}"
swift test
```

---

## 5. iOS-only extensions get bundled into non-iOS archives → `platformFilter`

**Symptom (upload):**
`ITMS-90044: Unsupported Platform - The extension bundle .../Message.appex is not supported for
this platform` and `ITMS-90508: Invalid Info.plist value ... 'DTPlatformName' ... is invalid`.

**Cause:** The app scheme embeds an iOS-only extension (iMessage, widgets, notification service)
into the macOS/tvOS/visionOS archive, where it can't run.

**Fix:** In the target's **Embed Foundation Extensions** (Copy Files) build phase, set a platform
filter on each extension so it's only embedded where supported. In pbxproj the `PBXBuildFile`
gains `platformFilter = ios;` (single) or `platformFilters = (ios, macos, xros, );` (multiple),
and the matching `PBXTargetDependency` too. Xcode UI: the target's dependency/embed rows have a
"Platforms" dropdown — set each extension to the platforms it actually supports.

---

## 6. iMessage extension needs a populated App Icon set

**Symptom (upload):** `ITMS-90649: Missing App Icon` (repeated for sizes 54×40, 64×48, 81×60,
96×72, 120×90, 134×100, 148×110, 180×135) and `ITMS-90642: Missing Info.plist key ...
MSMessagesExtensionStoreIconName`.

**Cause:** The `iMessage App Icon.stickersiconset` existed but had **no images**, so no icons
shipped and no store icon was generated.

**Fix:** Populate the stickersiconset with **opaque** PNGs at every slot, including the **1024×768**
store icon (that one auto-generates `MSMessagesExtensionStoreIconName`). iMessage icons are mostly
**4:3 and must be opaque (no alpha)**. If your source art has alpha, composite it onto the brand
background. We matched the app icon by reading the Icon Composer recipe
(`icon.icon/icon.json` → gradient stops + logo scale) and rendering each size with a tiny Swift +
CoreGraphics script (no ImageMagick/Pillow needed).

---

## 7. Info.plist / App Store compliance keys

- `ITMS-90737` — app declares `CFBundleDocumentTypes` but not whether it opens files in place →
  add `LSSupportsOpeningDocumentsInPlace` (YES/NO).
- `ITMS-90242` — macOS archive invalid without an App Store category → add
  `LSApplicationCategoryType` (e.g. `public.app-category.board-games`).
- Export-compliance prompt on every upload **or** the ASC **App Encryption Documentation**
  page (“What type of encryption algorithms does your app implement?”) →
  `ITSAppUsesNonExemptEncryption` = NO in the **uploaded** main-target Info.plist
  (not `INFOPLIST_KEY_*` — create `Info.plist` beside the `.xcodeproj` if the
  target was generate-only). That is the same declaration as answering **None of the algorithms
  mentioned above** (OS HTTPS/TLS/CloudKit/CryptoKit only — confirm legally). Details:
  **apple-testflight-archive** skill.
- `ITMS-90683` — binary calls an API that needs a purpose string (`NSSpeechRecognitionUsageDescription`
  for `SFSpeechRecognizer`, `NSAppleMusicUsageDescription` for `MusicAuthorization.request()`,
  `NSHomeKitUsageDescription` for `HMHomeManager`, `NSLocationWhenInUseUsageDescription` for
  Core Location, camera/mic similarly). Apple scans the **linked binary**, not the happy path —
  SideQuest hit this on speech even though voice play is mostly TTS. `AVSpeechSynthesizer`
  does not need a key; recognition does. A `project.yml` key that never landed in the pbxproj
  does not count — grep the **pbxproj and Info.plist**. Full pre-upload list: the
  **apple-testflight-archive** skill.
- **Privacy manifest** (`PrivacyInfo.xcprivacy`) — declare required-reason APIs. Audit what you
  actually use; e.g. `UserDefaults` → `NSPrivacyAccessedAPICategoryUserDefaults` reason `CA92.1`.
  Watch for false positives: `GKTurnBasedMatch.creationDate` is **not** a file timestamp;
  `URLResourceValues.fileSize` is **not** the disk-space API. `check-project.sh` flags a
  missing category, missing export-compliance key, empty Watch icon slots, and missing
  purpose strings when the matching API is referenced.

---

## 8. Xcode Cloud can't register new bundle IDs — pre-register every embedded target

**Symptom (archive export):** `Automatic signing cannot register bundle identifier
"com.you.App.SomeExtension"` + `No profiles for '...' were found` → **Export failed**.

**Cause:** Xcode Cloud's automatic signing can create *profiles* but **cannot register new App
IDs**. Only the main app ID existed; each embedded extension/Watch bundle ID must exist first.

**Fix:** Register every embedded target's bundle ID (portal, or `asc bundle-ids create --identifier
com.you.App.Ext --name "..." --platform IOS` — normalizes to UNIVERSAL). Enable capabilities that
match each target's entitlements (App Groups, iCloud, etc.).

**But a *local* `xcodebuild -allowProvisioningUpdates` DOES register IDs** — only Xcode *Cloud*
can't. Build the app scheme locally before running `asc bundle-ids create` and Xcode will have
already created the app ID, so your create fails with *"An App ID with Identifier '…' is not
available"* (it exists — you own it) and it's stuck with Xcode's generated name
(`XC com 45bitstudios AI`) instead of a clean one. Register with asc **before** the first
signed local build, or rename in the portal afterwards. Don't read "not available" as "taken by
someone else" — check `asc bundle-ids list --paginate` first.

---

## 9. Xcode Cloud enrollment + `asc` workflow management

- **First enrollment is manual & interactive** (Xcode ▸ Report Navigator ▸ Cloud ▸ Get Started →
  grant Apple ID + connect GitHub). An API key alone can't create the Xcode Cloud *product*.
- After the product exists, the `asc` CLI manages workflows. `asc xcode-cloud workflows create
  --file x.json` takes the **raw ASC `CiWorkflowCreateRequest`** JSON.
- **`workflows update`** requires `data.id` in the body and **rejects** the `product` /
  `repository` relationships (create-only) — strip them.
- A **TEST action** requires `testConfiguration.testDestinations`; pull valid device/runtime IDs
  from a Xcode version's `testDestinations` (`asc xcode-cloud xcode-versions`).
- Pin Xcode/macOS via the "Latest Beta or Release" alias id (works for both the
  `ciXcodeVersions` and `ciMacOsVersions` relationships).
- API-triggered runs are "manual" — the workflow needs a matching manual start condition
  (`manualBranchStartCondition` / `manualTagStartCondition`) for `asc xcode-cloud run --branch`.
- **Enrollment's "Connect Source Code Repository" dialog can dead-end on public *transitive*
  package dependencies** (proven on TubeActions: `swift-collections`/`app-check` via
  GoogleSignIn, `swift-system`/`eventsource` via the MCP swift-sdk). Each dependency row shows
  "Not connected", **Next stays disabled**, and clicking "Connect…" bounces to *your org's*
  GitHub App installation page — which can only grant repos your org owns, so third-party rows
  can never connect there. This is purely an enrollment-UI gate: public repos clone
  **anonymously** just fine during actual builds. Workaround: temporarily comment the
  transitive-heavy dependencies out of `Package.swift` (safe when SDKs sit behind
  `#if canImport(...)` seams — features compile into their fallback branches), reset package
  caches, run enrollment with the slimmed graph, then restore `Package.swift`
  (`git checkout -- Package.swift` + clean rebuild; stale `.build`/DerivedData can make
  `canImport` half-succeed, so clean). Keep the strip uncommitted so it never reaches CI.

---

## 10. Xcode version pinning vs. beta SDKs

- **`swift-tools-version` is part of this trap too**: a local beta Xcode happily writes a
  manifest tools version (e.g. 6.4) newer than the Swift in the cloud image (e.g. 6.3.3),
  and every cloud action then fails in seconds at "Could not resolve package dependencies".
  Keep the manifest at the cloud image's Swift version or lower.

If any deployment target is on an OS whose SDK ships only in a **beta** Xcode (e.g. targeting
macOS/visionOS "next" before GA), you **cannot** pin CI to a *release* Xcode — those SDKs won't
exist and those platforms won't build. Stay on "Latest Beta or Release" until the OSes ship.
Note: App Store *release* submission (not TestFlight) rejects beta-Xcode binaries, so pin to a
release Xcode before shipping — which is only possible once the targeted OSes are GA.

**Symptom (sudden, with NO project change):** every action errors within seconds with
`The project 'X' cannot be opened because it is in a future Xcode project file format (NNN)`,
on a branch that built green days earlier. The "Latest Beta or Release" alias re-resolved
(a beta image retired, or a new release promoted) to an Xcode **older** than the one that last
saved the project's `objectVersion`. Nothing in the diff causes or fixes it — it hits every
branch, including main. Check which Xcode the failed build used (the ASC build page, or
`asc xcode-cloud xcode-versions`), then either re-save the project in the Xcode you standardize
on (File Inspector ▸ Project Format) and push, or pin the workflow to an Xcode that reads the
format.

---

## 11. Verifying a single platform locally (fast loop)

```sh
# MUST pass -project from the repo root, or xcodebuild picks the *package* workspace
# (which has no app scheme) → "does not contain a scheme named ...".
xcodebuild build -project App/App.xcodeproj -scheme App \
  -destination 'generic/platform=tvOS' -allowProvisioningUpdates
```
Package tests: `swift test` from the repo root. For a full multiplatform archive check, prefer a
local `xcodebuild build` per platform to flush compile errors before spending Xcode Cloud minutes
(ITMS validation errors, however, only surface on an actual TestFlight upload).

---

## 12. Tooling / process traps

- **Editing `project.pbxproj` while Xcode is open can crash Xcode.** Prefer Xcode UI or
  `xcodebuild`/build-setting tooling; if you must script it, do it with Xcode closed or in a
  separate git worktree that Xcode doesn't have open.
- **Auto Info.plist tools can re-serialize and *drop* keys.** After any programmatic Info.plist
  edit, verify with `plutil -lint` **and** a `git diff` that only the intended lines changed
  (compare key counts before/after).
- **Xcode synchronized folder groups** (`PBXFileSystemSynchronizedRootGroup`): files dropped into
  a target's folder are auto-included — no pbxproj edit needed (handy for adding
  `PrivacyInfo.xcprivacy`).
- **Build numbers** auto-increment per Xcode Cloud run, so re-runs don't collide. First cloud
  build is slow (~15–20 min, fresh VM); later ones ~5–8.
- **Keep single sources of truth for Info.plist values.** Don't set the same key both in the
  Info.plist file *and* as an `INFOPLIST_KEY_*` build setting — pick one. Studio convention:
  the **plist file** is the home; keep `INFOPLIST_KEY_*` only for values that vary per build
  configuration, or on targets that have no plist file. `Tools/check-project.sh` flags
  same-target doubles. A `project.yml` / XcodeGen `INFOPLIST_KEY_*` that was never applied
  to the pbxproj is not a source of truth — grep the pbxproj.
- **`asc … list` paginates and truncates silently — always `--paginate`.** A bare
  `asc bundle-ids list` returned one page (and *zero* of the five IDs actually being looked
  for); `--paginate` returned all 138. There is no warning and no ellipsis, so the failure mode
  is a confident **false negative** — "it isn't registered" when it is. Any "does X exist?"
  check against a list endpoint needs `--paginate` before you believe a negative.
- **`ciWorkflows` GET omits `actions`** — a created workflow reads back with no `actions` key,
  which looks like the build actions silently failed to save. They didn't; the API just doesn't
  return them. Sanity check: Xcode's own auto-created Default workflow reports none either.
  Verify actions by triggering a run, not by reading the workflow.

---

## 13. Beta Xcode silently upgrades the project file format → cloud can't open it

A beta Xcode (e.g. Xcode 27) can stamp `project.pbxproj` with a future `objectVersion` (110)
even when the project declares `preferredProjectObjectVersion = 77` — and every Xcode Cloud
action on a release image then dies with *"cannot be opened because it is in a future Xcode
project file format"*, on all platforms at once.

Fix: set `objectVersion` back to the declared preferred version (one-line pbxproj edit),
verify locally (`xcodebuild -list` + one build), commit. Staying on the release-compatible
format also keeps App Store *release* submission viable (release submissions reject
beta-Xcode binaries — §10). `Tools/check-project.sh` flags the mismatch.

**The edit does not stick while the project is open in the beta Xcode.** Xcode rewrites
`objectVersion` back to 110 on its next save of the pbxproj, which can land *between* your
edit and your `git commit` — so the fix silently vanishes and the commit contains 110 while
the working tree looked right when you checked. Quit Xcode first, then edit, then
`git show HEAD:<path>/project.pbxproj | grep objectVersion` to confirm what actually got
committed rather than trusting the file on disk. Re-opening in the beta re-upgrades it, so
this is a recurring chore until the release Xcode catches up — the doctor is what catches the
regression.

**This is not a one-time fix — it recurs.** Every Xcode save re-stamps it while you're on a
beta (adding a target, toggling a capability, renaming a file). It came back three times in one
onboarding session. Treat it as a pre-push ritual: run `Tools/check-project.sh` after *any*
stretch of Xcode work, not once at setup. If the user is editing in Xcode while you work, re-run
the doctor before you trust an earlier green result.

## 14. Don't enroll Xcode Cloud until the app record has propagated

Enrolling minutes after creating the app record can produce a ciProduct with a **dangling app
link**. Symptoms: `ciProducts?filter[app]=<id>` returns empty and the product is missing from
every list API (direct by-ID reads work); GitHub check `details_url`s contain an empty app
segment (`…/apps//ci/builds/…`); and Xcode refuses to save archive/TestFlight workflow config
with *"set up this product for distribution first"* — which would also fail the first upload.

There is no API to repair the link. Recovery: `asc xcode-cloud products delete --id … --confirm`,
`git rm` the committed `<App>.xcodeproj/xcshareddata/xcodecloud/` manifest (a stale manifest
makes re-enrollment fail with "Failed to create workflow"), **quit Xcode**, reopen, Get Started
again. Prevention: after creating the app record, wait until `asc apps view --id <appId>`
resolves before enrolling.

## 15. Recovering the ciProduct ID when list APIs lag

Enrollment commits `<App>.xcodeproj/xcshareddata/xcodecloud/manifest.json`; its `targets[].id`
**is** the ciProduct ID. Use it (`asc xcode-cloud products view --id …`) when `ciProducts`
listings haven't caught up — workflow create payloads only need the ID, not the listing.

## 16. `INFOPLIST_FILE` must not point inside a synchronized folder group

A target's `Info.plist` file placed in its synchronized folder gets picked up twice — once by
`ProcessInfoPlistFile`, once as a copied resource → *"duplicate output file"* + a Copy Bundle
Resources warning. Keep the plist **next to the `.xcodeproj`** (outside any synchronized root)
with `INFOPLIST_FILE = Info.plist`. (`PrivacyInfo.xcprivacy` is a genuine resource — that one
belongs *inside* the target folder.)

## 17. Xcode extension-target templates ship landmines

Adding extension/watch targets in Xcode (Phase 1 step 3) plants several traps — audit right
after creating them:

- **Name shadowing:** a widget target named "Widget" generates `struct Widget: Widget` /
  `struct WidgetBundle: WidgetBundle`, shadowing the WidgetKit protocols → does not compile.
  Name targets distinctively, or rename the template types immediately.
- **Underscored type names** (`Watch_Watch_AppApp`) from multi-word target names violate
  SwiftLint `type_name` — rename.
- **`NSExtensionActivationRule = TRUEPREDICATE`** in Share/Action extension templates: builds,
  runs, and debugs fine, then the App Store rejects the upload (ITMS-90362, §19). Replace with a
  dictionary naming the content types actually handled — before the first tag, not after.
- **Default display names:** a watch target ships `INFOPLIST_KEY_CFBundleDisplayName = Watch`,
  which collides with Apple's own app (ITMS-90129, §19).
- **Empty Watch `AppIcon.appiconset`:** the template writes a 1024 `watchos` slot with no
  `filename`. The main app `.icon` does not fill it. Fails the iOS archive only (§18).
  Generate into `Watch/Assets.xcassets` with the apple-app-icons skill.
- **Deployment-target drift:** new targets inherit the current (possibly beta) SDK's
  deployment target, diverging from the app and `Package.swift` — realign (§2, the doctor
  catches it).
- **`NSExtensionActivationRule = TRUEPREDICATE` fails the upload, not just review.** Share and
  Action templates ship the *string* `TRUEPREDICATE` ("offer this extension for anything") →
  **ITMS-90362: Invalid Info.plist value** and a FAILED archive action. The compiler warning
  reads like a future problem (*"before you submit… the app will be rejected"*), so it's easy
  to file as a review-time issue and lose an hour when the build dies — it's a **hard upload
  blocker**. Replace with a dict of only what the extension can actually consume, e.g.
  `NSExtensionActivationSupportsText` / `…SupportsWebURLWithMaxCount`. Every type listed makes
  the app appear in the share sheet for that content, so keep it narrow.
- **Other placeholder plist values that ship silently:** notification-content templates set
  `UNNotificationExtensionCategory = myNotificationCategory`. Valid, so nothing complains — but
  it matches no category the app sends, so the extension never appears. Audit template plists
  for `my*` / `TRUEPREDICATE`-style placeholders before the first upload.
- **Stale scheme in the enrollment workflow:** the auto-created Default workflow can pin a
  scheme name that no longer exists ("A scheme called X does not exist"). Moot once you replace
  Default with the `ci/` payload workflows — which build the watch app via the iOS archive
  (Embed Watch Content) rather than a separate watchOS action.

## 18. "Preparing build for App Store Connect failed" is an opaque umbrella error

`** ARCHIVE SUCCEEDED **`, the export produces a correctly signed IPA, and then the action
FAILs with one unexplained ERROR — *"Preparing build for App Store Connect failed"*. It is
Xcode Cloud's post-archive hand-off to ASC, it emits **no log artifact**, and the API gives you
that bare string and nothing else. It is not one bug; it's the bucket every upload rejection
lands in. Confirmed causes so far:

- **Empty icon catalogs** (fresh Xcode templates). The real cause appears only as a **warning**
  in the same run's issues (e.g. *"None of the input catalogs contained a matching App Icon &
  Top Shelf Image brand assets collection named 'AppIcon'"*). Run the apple-app-icons skill —
  it also fills the iMessage stickersiconset, which fails uploads the same way — and verify per
  platform with `actool`.
- **Empty Watch `AppIcon` (iOS archive only).** Watch is `platformFilter = ios`. The Watch
  target's catalog is a 1024 slot with no PNG. macOS/tvOS/visionOS from the same run succeed
  because they never embed Watch. `actool` the **Watch** catalog, not the main app's. The
  doctor flags a `watchos` slot with no `filename`.
- **Transparent tvOS/visionOS Back or Top Shelf.** *"The last image stack layer with content,
  “Back”, must be a fully opaque bitmap"* (alpha at 0,0). Flatten onto the brand fill first.
- **An invalid Info.plist value in an embedded bundle**, e.g. `TRUEPREDICATE` (§17) → ITMS-90362.
- **A bundle/display name Apple has taken**, or a watch app whose `WKCompanionAppBundleIdentifier`
  no longer matches its parent → ITMS-90129 / ITMS-90538. Full catalogue and fixes in **§19**;
  `check-project.sh` catches the last two locally.
- **ExtensionKit `.appex` in `PlugIns/` instead of `Extensions/`.** Warning names the bundle;
  the umbrella error is the upload.

**Diagnosing it — in this order, because the cheap signals are the good ones:**

1. **Read the ASC email.** It names the exact ITMS code and the offending bundle
   (*"ITMS-90362 … in bundle AI.app/PlugIns/Share.appex"*). The API never surfaces this. Ask
   the user to check the Apple mail if you don't have it — it is faster and more precise than
   any amount of log archaeology, and it is the *only* place the real error appears.
2. **Check the run's WARNINGS, not just its errors.** For both known causes the actual
   explanation was logged as a warning next to the useless error.
3. **Diff archive actions by platform** (`asc xcode-cloud actions list --run-id …`). If
   **only iOS** failed, inspect what iOS uniquely embeds: Watch icon first, then NSE/NCE /
   iMessage / ExtensionKit. If only macOS failed, check `LSApplicationCategoryType`. If
   tvOS/visionOS failed with an opacity warning, flatten Back/Top Shelf. Since §5 filters
   iOS-only extensions out of the other archives, a plist/icon defect in an appex looks
   like a mysterious iOS-only failure.

**Red herrings in the export logs** — all of these appear in exports that *succeed*, so don't
chase them: `[OPTIONAL] Didn't find embedded provisioning profile …` (the archive is unsigned at
that stage), *"Unable to authenticate with App Store Connect"* / *"Failed to find an account
with App Store Connect access for team …"* from the "Session Proxy Provider" account, and
*Command line name "app-store" is deprecated*.

---

## 19. The first TestFlight upload rejects what every local build accepts

ITMS validation runs **only on a real upload** — `xcodebuild`, Xcode Cloud, and the doctor all
pass first. Contacts' first tag shook out four at once; all are Xcode-template defaults or rename
fallout, so budget one upload cycle for them on any new app. (`check-project.sh` now catches the
90362, 90538, empty Watch icon, missing category/compliance, and missing purpose-string cases
locally — run it before tagging.)

**ITMS-90129 — "bundle name or display name that is already taken."** Two independent causes:
the app target set no `CFBundleDisplayName`, so the name Apple checked fell back to `CFBundleName`
= `$(PRODUCT_NAME)`; and the watch target shipped Xcode's default display name `Watch`. Both
collide with Apple's first-party apps.

`CFBundleName` **cannot be overridden**. Xcode's Info.plist generator always derives it from
`PRODUCT_NAME` and beats both `INFOPLIST_KEY_CFBundleName` (silently ignored — no error, no
effect) and a real `INFOPLIST_FILE` that sets the key. Renaming `PRODUCT_NAME` is the only fix,
and it drags along the product's `PBXFileReference` path, every `TEST_HOST`, and `BuildableName`
in **every** shared scheme that builds the app. Scheme *names* are unaffected, so Xcode Cloud
workflows keep resolving. Set `CFBundleDisplayName` for what users read; keep `CFBundleName`
≤15 chars and distinct from any Apple app.

**ITMS-90362 — invalid `NSExtensionActivationRule`.** See §17: the template's `TRUEPREDICATE`
must become a declarative dictionary (`NSExtensionActivationSupportsFileWithMaxCount`,
`…SupportsWebURLWithMaxCount`, `…SupportsText`, …).

**ITMS-90538 — `WKCompanionAppBundleIdentifier` doesn't match the parent.** A watch app records
its parent's bundle ID in its **own** setting (`INFOPLIST_KEY_WKCompanionAppBundleIdentifier`),
not `PRODUCT_BUNDLE_IDENTIFIER`. The general rule this teaches:

> **After any bundle-ID or product rename, grep the whole repo for the OLD string — never for the
> settings you expect to hold it.** A `sed` anchored to `PRODUCT_BUNDLE_IDENTIFIER = ` passes
> silently while the watch app points at an app that no longer exists.

Verify against the **built** `Info.plist`, not the build settings — the generator's overrides mean
a setting can be present and ineffective:

```sh
xcodebuild build -project App/App.xcodeproj -scheme App -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/dd
APP=/tmp/dd/Build/Products/Debug-iphoneos/App.app     # NB: named after PRODUCT_NAME
plutil -extract CFBundleName        raw "$APP/Info.plist"
plutil -extract CFBundleDisplayName raw "$APP/Info.plist"
plutil -extract WKCompanionAppBundleIdentifier raw "$APP/Watch/WatchApp.app/Info.plist"
```

---

## 20. The app scheme must be SHARED or Xcode Cloud can't see it

Xcode auto-creates schemes into `<App>.xcodeproj/xcuserdata/<user>.xcuserdatad/xcschemes/`, which
is (correctly) gitignored. `xcodebuild -list` shows them locally, so nothing looks wrong — but the
cloud clones the repo and every workflow action reports *"The scheme 'X' was not found in this
project."*

Fix: Xcode ▸ Product ▸ Scheme ▸ Manage Schemes ▸ tick **Shared**. That writes
`<App>.xcodeproj/xcshareddata/xcschemes/<App>.xcscheme`, which is **not** gitignored — commit it.
Only the scheme the workflows name needs sharing; package schemes are regenerated from
`Package.swift`. `xcshareddata/` also holds `xcodecloud/manifest.json` from enrollment (§14) —
commit that too. `check-project.sh` checks for the shared scheme.

## 21. A private package dependency needs its own Xcode Cloud repository grant — being
    connected as *some other* product's primary repo doesn't count

`Package.swift` referencing a private repo (e.g. another 45BitStudios app's shared package)
fails package resolution on Xcode Cloud with `Failed to clone repository ...: fatal: could not
read Username for 'http://github.com': terminal prompts disabled` — even though `asc
xcode-cloud scm repositories list` shows the repo as generally accessible (it's connected as
the *primary* repository of a different product).

Xcode Cloud scopes git credentials per-product: a private package dependency is an "additional
repository" that has to be explicitly granted **on that specific product**, separately from
whatever access another product already has. `asc xcode-cloud products additional-repositories`
is **list-only** — there is no create/update endpoint, so this can't be scripted. Grant it once,
manually, in Xcode: open the workflow (Xcode ▸ Report Navigator ▸ Cloud, or the product's
workflow editor), which detects the unauthorized dependency on the next build attempt and walks
through an OAuth-style grant for that repository. After granting, `asc xcode-cloud products view
--id <id>` shows the repo under `relationships.additionalRepositories`.

## 22. A gitignored `Package.resolved` fails Xcode Cloud once automatic resolution is off

Xcode Cloud disables automatic dependency resolution by default (reproducibility), which
requires a checked-in `Package.resolved` — but some starter `.gitignore`s (this isn't in this
skill's own `templates/gitignore.template`, but has been hand-added to individual repos) still
carry the classic local-dev line `Package.resolved`, a holdover from when SwiftPM apps
regenerated it freely. Adding a new dependency then fails the Build/Archive action with:

```
Could not resolve package dependencies:
  a resolved file is required when automatic dependency resolution is disabled and should be
  placed at /Volumes/workspace/repository/<path>/project.xcworkspace/xcshareddata/swiftpm/Package.resolved.
  Running resolver because the following dependencies were added: '<name>' (<url>)
```

The trap: the file exists locally (Xcode regenerates it on every local build) and looks
committed if you only check `git status` after it already exists on disk — check `git
ls-files Package.resolved` instead. Fix: remove the `Package.resolved` line from `.gitignore`,
then commit **both** copies — the SPM one at the repo root and the separate one Xcode
maintains at `<App>.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (run
`xcodebuild -resolvePackageDependencies -project <proj> -scheme <scheme>` first if the
workspace copy is missing or stale). Same root cause, same fix as §6's Package.resolved
guidance — this entry exists because the *symptom* (gitignore rule, not staleness) is easy to
misdiagnose.

## 23. An SPM **build-tool** plugin (e.g. mlx-swift's `CudaBuild`) fails Xcode Cloud with
    "must be enabled before it can be used" — and `defaults write` genuinely cannot fix it

Any dependency that declares a SwiftPM **build-tool plugin** on a target it unconditionally
builds — `mlx-swift`'s `Cmlx` target ships `plugins: [.plugin(name: "CudaBuild")]` with no
platform gate — trips Xcode's interactive "trust this plugin" gate. Locally that's a one-time
Xcode dialog; Xcode Cloud's non-interactive build system has no dialog to answer, so the
Build/Archive action fails:

```
Plugin "CudaBuild" from package "mlx-swift" must be enabled before it can be used
```

...and cascades into unrelated "Unable to resolve module dependency" errors for the app's own
targets once the package graph build aborts — don't chase those as a separate bug first.

**Do not spend time on `defaults write` variants for a build-tool plugin — it does not work on
Xcode Cloud, full stop, confirmed by direct experiment.** The obvious-looking fix (widely
repeated online, including an Apple engineer's own forum answer for a *different* case — see
below) is:

```sh
defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES  # the "sic" typo'd key Xcode actually reads
defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidation -bool YES     # correctly spelled, in case Apple fixes the typo
killall cfprefsd 2>/dev/null || true                                                      # flush the prefs cache
```

All three were tried, in combination, in `ci_post_clone.sh` (before the Build action, since
`ci_pre_xcodebuild.sh` is too late). **Locally**, setting these keys reliably turns a failing
`xcodebuild build` into `BUILD SUCCEEDED` — so the mechanism is real and the keys are correctly
spelled. **On Xcode Cloud**, across five consecutive build attempts (each isolating one more
variable — plain key, typo'd key, both keys + cfprefsd flush), the identical `CudaBuild` error
recurred every single time. Apple's own documentation and forum threads (e.g.
`developer.apple.com/forums/thread/739347`, `.../732893`) only ever demonstrate this working
for **macro** plugins (`IDESkipMacroFingerprintValidation`, no typo) — never for build-tool
plugins. Treat that asymmetry as real: macro trust has a working non-interactive bypass on
Xcode Cloud; build-tool plugin trust apparently does not.

**The actual fix is to remove the plugin from the dependency graph, not bypass its trust
gate.** `CudaBuild` was added recently and only for Linux CUDA support (`mlx-swift` PR #413,
merged 2026-06-18) and is a documented no-op on every platform Apple ships ("CUDA is
disabled" — confirmed in a local build log). Pin the offending package to the last tag before
the plugin was introduced, as an *explicit* dependency in your own `Package.swift` even if you
never reference one of its products directly — SPM unifies it with whatever range the real
dependency (here, `mlx-swift-lm`) already declares:

```swift
// mlx-swift-lm's own floor is .upToNextMinor(from: "0.31.4") — pinning exactly there
// satisfies both constraints and keeps 0.31.5+'s CudaBuild plugin out of the graph.
.package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.31.4"),
```

Verify with `swift package resolve` (not `xcodebuild -resolvePackageDependencies` — in
practice its resolver did not honor an `exact:` pin mixed with another package's looser range
the same way the plain SwiftPM CLI resolver did; this doesn't matter for Xcode Cloud itself,
since automatic resolution is disabled there and it just uses whatever `Package.resolved` is
committed, but it means don't trust `xcodebuild`'s own resolver to prove the pin worked —
check the resulting `Package.resolved` file directly). Then commit **both** copies (§22) and
confirm with a real `xcodebuild build`.

**Correction, learned the hard way in the same debugging session as the above:** the macro
case is *not* reliably fixable with `defaults write` on Xcode Cloud either, despite an Apple
engineer's forum answer endorsing exactly this for a macro-trust error
(`developer.apple.com/forums/thread/739347`), despite it being spelled correctly with no typo,
and despite it verified `BUILD SUCCEEDED` locally. Once `CudaBuild` was eliminated per the fix
above, the *next* build still failed identically on `mlx-swift-lm`'s `MLXHuggingFaceMacros`
macro plugin — `IDESkipMacroFingerprintValidation` had been present in `ci_post_clone.sh` the
whole time and never took effect there. Don't assume the macro/build-tool-plugin asymmetry
implied earlier in this entry holds in general; on this infrastructure, *neither* kind of
plugin trust was bypassable non-interactively. Treat every `defaults write` plugin/macro-trust
claim as unverified until you've watched an actual Xcode Cloud build go green on it — a local
`BUILD SUCCEEDED` proves the key is spelled right, not that Xcode Cloud honors it.

**The general, reliable fix for either kind of plugin: eliminate it from the graph, don't try
to bypass its trust gate.** Two concrete techniques, both used together in the same repo:

1. **Version-pin around it** (shown above) — works when the plugin was added in a specific
   release and an earlier compatible tag predates it.
2. **Hand-write the macro's expansion** — works when the offending plugin is a **macro**
   (`.macro(...)` target) whose expansion is simple boilerplate, which is common: many
   "adapter"/"bridge" macros just generate a protocol-conformance forwarding struct. Read the
   macro's actual `MacroExpansionContext` implementation in the dependency's source (small,
   usually one file) — if it's straight-line forwarding with no real code generation logic,
   copy the expansion verbatim into your own code as a plain struct/function, and drop the
   macro's product dependency entirely. `mlx-swift-lm`'s `#adaptHuggingFaceTokenizer` (used to
   wrap `Tokenizers.Tokenizer` as `MLXLMCommon.Tokenizer`) was exactly this: a ~30-line
   one-to-one method-forwarding struct with zero metaprogramming, safe to inline. Comment the
   inlined code with where it came from and why, so a future dependency bump doesn't silently
   drift from upstream's real behavior.

If neither applies — no older tag exists, and the plugin does real code generation that can't
be hand-copied — the remaining options are: vendor/fork the dependency with the plugin
declaration stripped, or accept that this specific dependency can't build on Xcode Cloud
non-interactively and needs a different CI provider / self-hosted runner for that target.

**If you still want to try the `defaults write` bypass first (e.g. as a quick stopgap while
you work out a real fix), the keys are:**

```sh
defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES  # sic — real Apple-side typo, build-tool plugins
defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidation -bool YES     # correct spelling, in case Apple fixes the typo
defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES             # correctly spelled, macros
killall cfprefsd 2>/dev/null || true                                                      # flush the prefs cache
```

**Security note:** these keys are global to the CI runner — they trust *every* plugin/macro of
that kind in the dependency graph, not just the one that triggered the error, for the lifetime
of the runner. There's no narrower per-plugin trust that survives a fresh Xcode Cloud checkout
(the local equivalent, `~/.swiftpm/security/plugins.json`, is keyed to a commit hash and isn't
persisted across cloud checkouts). Flag this tradeoff to the user rather than applying it
silently — and confirm on an actual Xcode Cloud build before believing it worked.
