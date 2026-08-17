---
name: apple-app-onboarding
description: Onboard a new Apple multiplatform app repo to 45BitStudios standards — thin app shell over a Swift package, CLAUDE.md, SwiftLint/SwiftFormat CI gates, DocC + check-docs, Xcode Cloud CI + TestFlight workflows via the asc CLI, bundle-ID registration, privacy/compliance plists, and tag-driven releases. Use when creating a new iOS/macOS/visionOS/tvOS/watchOS app project or bringing an existing bare Xcode project up to studio standards.
---

# Apple App Onboarding

Bring a brand-new Apple app repo from "bare Xcode project" to "CI-gated, TestFlight-ready,
agent-friendly" in one pass. Distilled from shipping Empress Blood (45BitStudios/EmpressBlood)
through Xcode Cloud and TestFlight — every step here exists because skipping it cost a PR later.

**Installing this skill:** it lives in `45BitStudios/skills`. **Symlink it — don't copy it.**
Copying is what let this skill drift into three versions at once, with the most-correct copy
sitting unversioned in `~/.claude`:

```sh
git clone https://github.com/45BitStudios/skills.git ~/Dev/Studio45/skills   # once
ln -s ~/Dev/Studio45/skills/apple-app-onboarding ~/.claude/skills/apple-app-onboarding
```

Because it's a symlink, fixes you make while onboarding an app land in a working tree you can
review and commit — and a `git pull` updates every repo at once. When a new trap bites, add it
to `references/apple-multiplatform-ci-gotchas.md` **and**, if it's mechanically checkable, to
`templates/check-project.sh`: the doctor catches it in seconds, where a cloud build or upload
rejection costs 20 minutes.

## Ground rules

- **The `.xcodeproj` is created in Xcode, by the user — never generated or hand-built by you.**
  Everything else (package, scripts, configs, workflows, docs) is yours to create.
- **Run `asc` yourself — the studio expects it.** Registering bundle IDs, adding
  capabilities, creating the app record, and creating workflows are all agent work, and
  `asc web *` commands work off the machine's cached web session. Only two Phase 7 steps
  are genuinely manual, and only because the API has no endpoint for them (both verified,
  not assumed). Confirm the *values* first — a bundle ID or app record is effectively
  permanent — then run the command; don't hand the user a script to paste.
- **Templates live in `templates/` next to this file.** Copy them into the repo and substitute
  placeholders: `{{APP_NAME}}` (PascalCase product name, e.g. `EmpressBlood`), `{{BUNDLE_ID}}`
  (default `com.45bitstudios.{{APP_NAME}}`), `{{TEAM_ID}}` (default `SP7UUHBXPL`),
  `{{CATEGORY}}` (an `LSApplicationCategoryType` value). The workflow JSONs also carry
  `{{XCODE_VERSION_ID}}`/`{{PRODUCT_ID}}`/`{{REPOSITORY_ID}}`, filled from live asc queries in
  Phase 7. By the end of onboarding, `grep -r '{{' --exclude-dir=.claude` finds nothing.
- **Environment check first.** Compiling requires a Mac with Xcode. In a cloud/Linux session you
  can still do everything except build — flag verification steps as "run on the Mac" instead of
  skipping them silently.
- Work through the phases in order; each ends with a verifiable state. Commit per phase so a
  failed step is easy to unwind.

## Phase 0 — Interview & preflight

Ask the user (one question round, don't drip):

1. **App name** (PascalCase) and one-line description.
2. **Platforms** — default is all five (iOS/iPadOS, macOS, visionOS, tvOS, watchOS); confirm
   which this app actually ships.
3. **Extensions planned** — widgets, iMessage, notification service/content, App Clip, watch
   app. (Each needs a bundle ID registered in Phase 7 and a `platformFilter` if iOS-only.)
4. **App Store category** (`LSApplicationCategoryType`, e.g. `public.app-category.board-games`).
5. **Package layering** — default four targets: `<App>Core` (pure Swift, no UI imports),
   `<App>Data` (persistence over Core, no SwiftUI), `<App>Intents` (App Intents surface;
   Core + Data only), `<App>UI` (SwiftUI presentation). Add an extension-safe UI target (no
   heavy frameworks) only if widgets/snippets need shared views.
6. **The App Intents surface** — every app is intents-first (intents are the app's API for
   Siri, Shortcuts, Spotlight, widgets, and Apple Intelligence). Ask which nouns become
   entities, which verbs become action intents, and which screens get launcher intents; the
   answers seed `references/app-intents-playbook.md`'s checklist in Phase 3.
7. **Domain** — each app gets its own domain served by IkigaiServer (universal links, AASA,
   marketing site, JSON API all hang off it — see Phase 8). Also sketch the URL routes,
   reusing the entity nouns from item 6.

Preflight checks:

```sh
xcodebuild -version        # Mac session? Xcode present?
asc --version              # asc CLI available (Phase 7)?
swiftlint version; swiftformat --version   # brew install swiftlint swiftformat if missing
git rev-parse --git-dir    # repo initialized?
```

## Phase 1 — Xcode project (user does this part)

If `*.xcodeproj` doesn't exist yet, have the user create it in Xcode (≈5 min) and wait:

1. File ▸ New ▸ Project ▸ **Multiplatform ▸ App**. Product name `{{APP_NAME}}`, team
   45BitStudios (`{{TEAM_ID}}`), bundle ID `{{BUNDLE_ID}}`, SwiftUI lifecycle, Swift Testing.
2. Save the project **inside a subfolder of the repo root** (layout: `Repo/{{APP_NAME}}/
   {{APP_NAME}}.xcodeproj`) so the repo root stays free for `Package.swift`.
3. Add planned extension targets now if known (File ▸ New ▸ Target) — registering bundle IDs
   early avoids Xcode Cloud signing failures later (see gotchas §8). Name them distinctively
   (a target named "Widget" generates `struct Widget: Widget`, shadowing WidgetKit — gotchas
   §17), and audit new targets afterward: templates inherit beta deployment targets, ship
   lint-violating type names, and a Watch target's `AppIcon.appiconset` is empty until you
   fill it (apple-app-icons skill — empty Watch icons fail the iOS TestFlight archive only).
4. **Share the app scheme:** Xcode ▸ Product ▸ Scheme ▸ Manage Schemes ▸ tick **Shared**.
   An agent can equally write `xcshareddata/xcschemes/<App>.xcscheme` directly — it's plain
   XML; copy the structure from a scheme Xcode already made, using the target's
   `BlueprintIdentifier` from the pbxproj. Verify with `xcodebuild -list` (the scheme must
   appear), never by the file merely existing.
   Xcode keeps schemes in gitignored `xcuserdata/` by default, so the cloud sees no scheme at all
   and every workflow action fails with "scheme not found" (gotchas §20). Commit the resulting
   `xcshareddata/xcschemes/{{APP_NAME}}.xcscheme`.

**Read `references/apple-multiplatform-ci-gotchas.md` §16–§17 before auditing the new targets** —
they catalogue exactly what the templates get wrong (name shadowing, underscored type names,
deployment-target drift, `TRUEPREDICATE` activation rules, default display names, and where an
`Info.plist` may live). Rediscovering these by hitting them costs hours; reading costs minutes.

Verify: `ls */*.xcodeproj` finds exactly one project, one level below the repo root, and
`ls */*.xcodeproj/xcshareddata/xcschemes/` lists the app scheme.

## Phase 2 — CLAUDE.md & repo docs

1. Check for `CLAUDE.md` at the repo root. If missing, create it from
   `references/claude-md-template.md`, filling in the app's actual targets and layering table
   from the Phase 0 interview. If present, verify it covers: commands, module layering rules,
   the "thin shell over package" rule, test framework (Swift Testing), and the environment
   gotcha (cloud sessions can't compile). Add whatever's missing; don't duplicate what's there.
2. Copy `templates/README.md.template` → `README.md` (substitute, then fill the comment
   blocks from the interview) and `templates/pull_request_template.md` →
   `.github/pull_request_template.md`.

## Phase 3 — Swift package (the app becomes a thin shell)

1. Copy `templates/Package.swift.template` → `Package.swift` at the repo root; substitute
   placeholders and adjust targets to the Phase 0 layering decision.
2. Create `Sources/<Target>/` for each target and `Tests/<Target>Tests/` for Core and Data at
   minimum. Seed each target with one real type and each test target with one real
   `@Suite`/`@Test` (Swift Testing, **not** XCTest) so `swift test` is green and non-empty.
3. Move the template app code out of the app target: views/models go into the package; the app
   target keeps only `@main App` struct + assets + entitlements + Info.plist. The shell should
   be ~1 file that does `import {{APP_NAME}}UI; WindowGroup { RootView() }`.
4. **Link the package:** Xcode ▸ File ▸ Add Package Dependencies ▸ **Add Local…** ▸ select the
   repo root; link the UI library to the app target (Core/Data come transitively). An agent can
   instead write it into the pbxproj directly — **with Xcode quit** — by adding an
   `XCLocalSwiftPackageReference` (`relativePath = ..`), one `XCSwiftPackageProductDependency`
   per product, matching `PBXBuildFile` entries in the app's Frameworks phase, the target's
   `packageProductDependencies`, and the project's `packageReferences`. Prove it with a real
   `xcodebuild build`, not `plutil -lint`: only a build shows the package graph resolved.
5. **Critical check** (gotchas §1): the package reference in `project.pbxproj` must be
   `relativePath = ..` — a path that climbs above the repo root (`../../Name`) resolves locally
   but breaks on Xcode Cloud's fixed checkout path. Grep the pbxproj to confirm.
6. **Localization from day one** (retrofitting across many targets is painful): the template
   already sets `defaultLocalization: "en"`. Seed the UI target with
   `Sources/{{APP_NAME}}UI/Resources/Localizable.xcstrings` containing
   `{"sourceLanguage":"en","strings":{},"version":"1.0"}`, declare
   `resources: [.process("Resources")]` on that target, and add a String Catalog to the app
   target in Xcode (File ▸ New ▸ String Catalog). SwiftUI text auto-extracts on build.
7. **App Intents-first setup** — copy `references/app-intents-playbook.md` →
   `docs/app-intents-playbook.md` and follow its checklist: `AppIntentsPackage` conformance
   in the `<App>Intents` target, the `AppShortcutsProvider` in the **app shell** (never the
   package — phrase extraction needs the main bundle), **no**
   `AppIntentsPackage.includedPackages` for the SPM target (silent error-9004 shortcut
   breakage), a `LaunchInbox` mailbox in Data for navigation intents, and the entities/
   actions from the Phase 0 interview stubbed with their queries.
8. Copy `templates/gitignore.template` → `.gitignore` (merge if one exists).

Verify (Mac): `swift build && swift test` from the repo root; app scheme builds in Xcode.

## Phase 4 — Lint & format (CI-gated)

1. Copy `templates/swiftlint.yml` → `.swiftlint.yml` and `templates/swiftformat` →
   `.swiftformat`; substitute placeholders (the app-shell folder name is in `included`).
2. Copy `templates/lint.sh` → `Tools/lint.sh`, `chmod +x`.
3. Run `Tools/lint.sh --fix`, then `Tools/lint.sh` until clean — the CI gate in Phase 6 runs
   the exact same checks, so a dirty tree here means a red first build.

## Phase 5 — Docs process

1. Copy `templates/check-docs.sh` → `Tools/check-docs.sh`, `chmod +x`. It's toolchain-free
   (awk), so it runs in cloud sessions too. Run it; document any public API it flags.
2. Create a DocC catalog per library target: `Sources/<Target>/<Target>.docc/<Target>.md` with
   a landing page and a curated `## Topics` list. Keep Topics in sync when adding public types.
3. Convention (already in the CLAUDE.md template): doc comments are Apple-style `///` and
   explain *why*, not *what*. `Tools/check-docs.sh` must stay green.

## Phase 6 — CI scripts + Xcode Cloud workflow payloads

1. Copy `templates/ci_post_clone.sh` → `ci_scripts/ci_post_clone.sh` and
   `templates/ci_pre_xcodebuild.sh` → `ci_scripts/ci_pre_xcodebuild.sh`; substitute
   placeholders; `chmod +x` both. `ci_scripts/` must sit at the **repo root** — Xcode Cloud
   discovers it by convention. Post-clone gates the build on lint + format + `swift test`
   (package test schemes can't run natively in an app-project workflow — gotchas §4).
2. Copy `templates/workflow-ci.json` → `ci/workflow-ci.json` and
   `templates/workflow-testflight.json` → `ci/workflow-testflight.json`. Substitute
   `{{APP_NAME}}`; trim the `actions` arrays to the platforms chosen in Phase 0. Leave the
   `{{XCODE_VERSION_ID}}` / `{{PRODUCT_ID}}` / `{{REPOSITORY_ID}}` placeholders — they're
   filled from live asc queries in Phase 7. These files are the source-of-truth *exports*;
   the live workflows are created from them via asc.

## Phase 7 — App Store Connect (asc CLI)

Follow `references/asc-setup.md` step by step. Summary:

1. Register the app bundle ID **and one per extension target** (Xcode Cloud can register
   profiles but never new App IDs — gotchas §8). Enable capabilities matching entitlements.

   **Entitlements are two-sided, and the halves fail differently — do both, they're yours.**
   The ASC capability on the bundle ID only *permits* a thing; the target's `.entitlements`
   file is what actually *claims* it. Registering `APP_GROUPS` in ASC and stopping there is a
   silent runtime bug, not a build error: the app compiles, signs, and launches, then
   `UserDefaults(suiteName:)` returns nil and every `LaunchInbox` hand-off — intents, widgets,
   universal links — quietly does nothing. Nothing tells you; Siri just seems to ignore you.

   With Xcode quit: write `<Target>/<Target>.entitlements` and set `CODE_SIGN_ENTITLEMENTS`
   on **both** Debug and Release. Then prove it from the *signed product*, since a correct
   file that isn't wired reads identically to one that is:
   ```sh
   codesign -d --entitlements - --xml <built>.app | plutil -convert xml1 -o - -
   ```
   A local `xcodebuild -allowProvisioningUpdates` build also registers the App Group / iCloud
   container as a side effect — `asc` has no command for those.

   Claim only what the code actually uses. An iCloud entitlement with no CloudKit code is
   speculative and drags a container registration with it; add it alongside the code that
   reads it (YAGNI applies to entitlements too).
2. Create the app record with `asc web apps create` — it works off the cached web session, so
   run it yourself. Ask the user for name + SKU first (the name is globally unique and a
   removed record squats its bundle ID forever).
3. **Manual, once:** enroll the project in Xcode Cloud from Xcode (Report Navigator ▸ Cloud ▸
   Get Started). Not a policy call — `asc xcode-cloud products` has only `list`/`view`/`delete`,
   so there is no create endpoint to script. **Only after the app record has propagated**
   (`asc apps view --id` resolves) — enrolling early creates a product with a dangling app link
   that blocks TestFlight config (gotchas §14). Enrolment also connects the SCM repo: make sure
   it's *this* repo, since a similarly-named one in another namespace is easy to pick.
4. Query product/repo/Xcode-version IDs via asc, fill them into the `ci/*.json` payloads, and
   create both workflows: `asc xcode-cloud workflows create --file ci/workflow-ci.json` (same
   for TestFlight). Xcode/macOS version ids come from `asc xcode-cloud xcode-versions list` and
   `macos-versions list` — the "Latest Release" alias shares one id across both, so a single
   value fills `xcodeVersion` and `macOsVersion`. Prefer **Latest Release** over "Latest Beta or
   Release" (§10). Repos: `asc xcode-cloud scm repositories list`.
5. **Manual, once:** in the TestFlight workflow settings, enable **"Xcode Cloud automatically
   manages build number"**. Also not scriptable — the flag appears on neither `ciWorkflow` nor
   `ciProduct` attributes.

## Phase 8 — Deep links & IkigaiServer tenant

Every app is a tenant on IkigaiServer (one Host-routed deployment: marketing site, AASA,
push/Live Activities, CloudKit server-to-server, JSON APIs per app).

1. **App side** — follow `references/deep-links.md`: Associated Domains entitlement
   (`applinks:` + `appclips:` if there's a Clip), custom URL scheme in the Info.plist, and
   URL parsing in the Data layer that funnels into the same `LaunchInbox` mailbox the
   intents use — one navigation system for URLs, intents, widgets, and quick actions.
   Enable the Associated Domains **capability on the bundle ID** (pairs with Phase 7).
2. **Server side** — follow `references/ikigai-server.md`: register the tenant (domain, DNS,
   TLS, bundle ID, Team ID), add the AASA entries, stand up the marketing pages (the support
   and privacy pages become the App Store's required URLs), register the APNs key for
   push/Live Activities, and the CloudKit S2S key if used.
3. **API client** behind a protocol seam in the Data layer (same pattern as every SDK seam),
   base URL = the app's own domain, versioned path, Debug-only staging override.
4. Copy both references into the repo: `references/deep-links.md` → `docs/deep-links.md`,
   `references/ikigai-server.md` → `docs/ikigai-server.md`.

## Phase 9 — Release tooling

1. Copy `templates/tag-release.sh` → `Tools/tag-release.sh`, `chmod +x`.
2. Copy `templates/release-process.md` → `docs/release-process.md`; substitute placeholders.
3. The contract: nobody hand-edits `MARKETING_VERSION`. `Tools/tag-release.sh X.Y.Z` tags
   `vX.Y.Z` from a clean, up-to-date main; the tag triggers the TestFlight workflow;
   `ci_pre_xcodebuild.sh` stamps the version from `CI_TAG`; ASC manages build numbers.

## Phase 10 — Compliance & privacy (before the first upload, not after the first rejection)

1. Copy `templates/PrivacyInfo.xcprivacy` into the app target's folder (Xcode's synchronized
   folder groups auto-include it — no pbxproj edit). Audit required-reason APIs actually used;
   the template covers `UserDefaults` (`CA92.1`). Add one copy per extension that needs it.
2. Set in the app target. Studio convention: these live in the target's **Info.plist file**,
   not `INFOPLIST_KEY_*` build settings — one reviewable home, comments allowed, arbitrary
   keys supported, and localizable keys (display name, usage descriptions) sit where
   `InfoPlist.xcstrings` expects their fallbacks. Reserve build settings for values that
   genuinely vary per configuration, and for targets that have no plist file at all. Never
   both homes for one key (the doctor enforces this per target):
   - `ITSAppUsesNonExemptEncryption` = NO (if only exempt crypto like HTTPS — it's a legal
     declaration, confirm with the user)
   - `LSApplicationCategoryType` = `{{CATEGORY}}` (macOS archives are invalid without it)
   - `LSSupportsOpeningDocumentsInPlace` if `CFBundleDocumentTypes` is declared
3. If any extension is iOS-only (iMessage, notification UI): set **platform filters** on its
   embed + dependency rows so macOS/tvOS/visionOS archives don't bundle it (ITMS-90044 —
   gotchas §5).
4. **Names Apple will reject** (gotchas §19 — these pass every build and fail the upload):
   set `INFOPLIST_KEY_CFBundleDisplayName` on the app *and* the watch target (whose template
   default is literally `Watch`), and make sure `CFBundleName` — which Xcode derives from
   `PRODUCT_NAME` and which **cannot** be overridden any other way — isn't an Apple app's name.
   Renaming `PRODUCT_NAME` later drags the product reference, every `TEST_HOST`, and every shared
   scheme's `BuildableName` with it, so pick it correctly at Phase 1 instead.
5. **Purpose strings for APIs the binary actually calls** (ITMS-90683). If the code requests
   MusicKit / HomeKit / location / camera / mic, the matching `NS*UsageDescription` must
   exist in the plist home. A `project.yml`
   key that never landed in the pbxproj does not count.
6. **App icons for every shipping platform** — follow `references/app-icons.md`. The Watch
   target's own `AppIcon.appiconset` is a separate catalog the main `.icon` does **not**
   fill; the template ships it empty and that fails the **iOS** archive only (gotchas §18).
   tvOS Back / Top Shelf and visionOS back must be fully opaque. iMessage needs a populated
   stickersiconset. Missing icons pass the build and fail the upload — do this before the
   first tag. Use the apple-app-icons skill to generate and `actool`-verify.
6. Copy `references/apple-multiplatform-ci-gotchas.md` → `docs/apple-multiplatform-ci-gotchas.md`
   so future agents in this repo hit known traps with answers in-repo.

## Phase 11 — Binary-size budget

Small installs are a studio goal; size regressions are cheapest to catch at onboarding.

1. Copy `templates/check-size.sh` → `Tools/check-size.sh`, `chmod +x`, substitute
   `{{APP_NAME}}`. It audits everything that ships verbatim (SwiftPM target resources +
   app-target `Resources/`), flags oversized files, and fails over budget — CI runs it via
   `ci_post_clone.sh`, so the budget is enforced on every PR. `--app` / `--archive` modes
   give a built-product breakdown on the Mac.
2. Set `RESOURCE_BUDGET_KB` consciously (default 10 MB). Raising it later is a reviewed
   decision, recorded in the commit that raises it.
3. Copy `references/binary-size-playbook.md` → `docs/binary-size-playbook.md` — the rules
   (verbatim vs catalog, per-target bundle duplication, SDKs behind app-only seams, OTA for
   heavy content) and the encoding cheat sheet (JPEG q78 seeds, AAC-in-CAF SFX, IMA4 for
   notification sounds, flattened tvOS top-shelf art).
4. After the first archive exists, get ground truth once: export with app thinning and read
   `App Thinning Size Report.txt` (the script prints the command).

## Phase 12 — Verify & first green build

First copy `templates/check-project.sh` → `Tools/check-project.sh` (`chmod +x`, substitute) —
the project doctor. It mechanically verifies the traps that otherwise only fail on Xcode
Cloud or at upload: package reference stays inside the repo, deployment targets consistent
across every target and matching `Package.swift`, `MARKETING_VERSION` uniform, no Info.plist
key set both in a plist file and as an `INFOPLIST_KEY_*` build setting, category + export
compliance declared, privacy manifest present, Watch `AppIcon` slots populated, purpose
strings present when the matching API is used, `PRODUCT_NAME` / display name not an
Apple app name (ITMS-90129), App Intent title/description free of "apple" (ITMS-90626),
CloudKit entitlements have Production + a real container (ITMS-90046), tvOS/visionOS
Back and Top Shelf opaque at every scale, no leftover placeholders, scripts executable.
It's toolchain-free, so run it even in cloud sessions.

Then, on the Mac, in order:

```sh
Tools/check-project.sh             # project-configuration doctor healthy
swift test                         # package suites green
Tools/lint.sh                      # lint + format clean
Tools/check-docs.sh                # public API documented
Tools/check-size.sh                # bundled resources within budget
# one build per shipping platform — flushes availability errors before spending cloud minutes:
xcodebuild build -project {{APP_NAME}}/{{APP_NAME}}.xcodeproj -scheme {{APP_NAME}} \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates
# repeat for macOS / tvOS / visionOS / watchOS as applicable
```

Then commit, push, open a PR to main → the CI workflow should run and pass. When ready for
TestFlight, walk the **apple-testflight-archive** skill first (purpose strings, Watch
icons, category, daily upload cap), then `Tools/tag-release.sh 0.1.0`. First cloud build
takes ~15–20 min (fresh VM); subsequent ~5–8.

Finish by giving the user a checklist of what was set up, the manual-only steps still pending
(Xcode Cloud enrollment, build-number toggle, App Store metadata/screenshots), and any steps
skipped because the session couldn't compile.

## Beyond onboarding — submitting to the App Store

When the app is ready to go from TestFlight to submitted, follow
`references/app-store-listing.md`: metadata via asc, the privacy *nutrition label*
questionnaire (separate from `PrivacyInfo.xcprivacy`), per-platform screenshot sets, age
rating/pricing, review notes, and the release-Xcode pinning rule for the submission build.
