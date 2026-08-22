---
name: apple-swiftui-previews
description: >
  Add SwiftUI #Preview with mock data to every view, a preview-capture CLI that
  writes Designs/previews/<device>/ PNGs (iphone, ipad, mac, tv, vision, watch),
  a compare script against a previous git revision, a shared Screens Xcode
  scheme, and an Xcode Cloud Screens workflow. Proven on Tubeactions and
  Homestead. Use when the user wants previews, design screenshots, visual
  history, screenshot diffs, iPad/Mac/TV/Watch canvases, a Screens/Design
  scheme, or runs /apple-swiftui-previews.
---

# SwiftUI previews + design screenshots

Land the Tubeactions preview pipeline on an existing studio Apple app. One repo
per run. Do not attach capture to every normal app compile.

**Working examples:** `Studio45/Tubeactions` and `Studio45/Home` (`Sources/*/Preview/`,
`Tools/check-previews.sh`, `Tools/capture-previews.sh`, scheme `Screens`,
`Designs/previews/<device>/`).

Templates live in `templates/` next to this file. Substitute placeholders, then
`grep -r '{{' --exclude-dir=.git` must be empty.

| Placeholder | Example |
|---|---|
| `{{UI_MODULE}}` | `HomesteadUI` |
| `{{UI_SOURCE_PATHS}}` | `Sources/HomesteadUI` (space-separated find roots; add Share if it has SwiftUI) |
| `{{APP_NAME}}` | `Homestead` (Xcode target / `.app` basename) |
| `{{XCODEPROJ_DIR}}` | `Homestead` (folder that contains the `.xcodeproj`) |
| `{{XCODEPROJ_FILENAME}}` | `Homestead.xcodeproj` |
| `{{APP_TARGET_ID}}` | `61BAC72B…` (`PBXNativeTarget` id for the app, from pbxproj) |
| `{{PRODUCT_ID}}` / `{{REPOSITORY_ID}}` / `{{XCODE_VERSION_ID}}` | from `ci/workflow-ci.json` or `asc xcode-cloud` |

## Phase 0 — Which app

Ask once: which repo. Then discover, don't guess:

```sh
ls Sources/          # UI module
ls */*.xcodeproj     # app shell
ls ci/workflow-ci.json
```

Reuse existing mock data (`SampleHomeData`, `PreviewStores`, …). Do not invent a
second sample catalog.

## Phase 1 — Tooling

Copy and substitute:

- `templates/check-previews.sh` → `Tools/check-previews.sh`
- `templates/capture-previews.sh` → `Tools/capture-previews.sh`
- `templates/compare-previews.sh` → `Tools/compare-previews.sh`
- `templates/compare-previews.swift` → `Tools/compare-previews.swift`
- `templates/ci_post_xcodebuild.sh` → `ci_scripts/ci_post_xcodebuild.sh` (merge if the repo already has one)
- `templates/workflow-screens.json` → `ci/workflow-screens.json`

`chmod +x` the scripts. Wire `Tools/check-previews.sh` into `ci_scripts/ci_post_clone.sh`
next to lint (cheap, no compile). Do **not** run capture from post-clone.

Add `ci_scripts/ci_post_xcodebuild.sh` to `Tools/check-project.sh`'s executable list
if that file exists.

## Phase 2 — Mock data + preview overrides

In `Sources/{{UI_MODULE}}/Preview/PreviewData.swift`:

- Fixed UUIDs and dates (screenshots must not jitter).
- No network image URLs (posters fall back to a gradient).
- A factory that builds the screen's view model **without** hitting the network.

Singletons (`FooAuthManager.shared`, `@AppStorage` on the App Group suite) need an
optional preview override, same pattern as Tubeactions `previewIsSignedIn`. Seed
`@State` in `init` when capture must see data — `.task` often has not run yet.

## Phase 3 — `#Preview` on every file-scope View

Every `Sources/{{UI_MODULE}}/**/*.swift` (and Share, if present) whose first-column
line is `struct Foo: View` or `public struct Foo: View` gets `#Preview("Name")` or
a `PreviewProvider`. Nested `private struct` rows are covered by the parent file.

States (signed-out / signed-in / loading / empty / error, feature on / off) are
**separate named previews**, not one preview with comments. Pass arguments through
the view initializer or `PreviewData.viewModel(...)`. Interactive canvas toggles
use `@Previewable @State`; those do not produce extra PNGs.

Run `Tools/check-previews.sh` until it prints the ok line.

## Phase 4 — Capture catalog + executable

Copy `templates/PreviewCapture.swift` → `Sources/{{UI_MODULE}}/Preview/PreviewCapture.swift`.
Keep the NSHostingView macOS path (plain `ImageRenderer` emits empty NavigationStack/List
bitmaps). Fill `PreviewCaptureScreen` with **product screens only** (Home, Search, Settings,
not every private row). Each case must match a named `#Preview`.

Keep `PreviewCaptureDevice` from the template (`iphone`, `ipad`, `mac`, `tv`,
`vision`, `watch`). Capture writes `Designs/previews/<device>/<Screen>-{light,dark}.png`.
`--devices` on the CLI selects a subset. These are 2D macOS layouts at that canvas
(compact size class on iPhone/Watch, regular otherwise) — not a watchOS/tvOS/visionOS
runtime. Skip MapKit-heavy screens; they can infinite-loop in an offscreen hosting view.

Copy `templates/PreviewCaptureMain.swift` → `Sources/preview-capture/PreviewCaptureMain.swift`.

Add to `Package.swift`:

```swift
.executable(name: "preview-capture", targets: ["preview-capture"]),
// ...
.executableTarget(
    name: "preview-capture",
    dependencies: [
        "{{UI_MODULE}}",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
    ],
    path: "Sources/preview-capture",
    swiftSettings: sharedSwiftSettings
),
```

Add `swift-argument-parser` if the package doesn't already depend on it.

## Phase 5 — Screens scheme

Copy `templates/Screens.xcscheme` →
`{{XCODEPROJ_DIR}}/{{XCODEPROJ_FILENAME}}/xcshareddata/xcschemes/Screens.xcscheme`.

Grep the pbxproj for `isa = PBXNativeTarget` / the app target name to fill
`{{APP_TARGET_ID}}`. **Do not** point the scheme at the SPM `preview-capture`
executable — Xcode reports `Scheme Screens is not currently configured for the
build action.` Point it at the app target (Tubeactions does this). Capture runs
from the scheme post-action (`Tools/capture-previews.sh`, all devices) and from
`ci_post_xcodebuild.sh`.

Verify: `xcodebuild -project {{XCODEPROJ_DIR}}/{{XCODEPROJ_FILENAME}} -scheme Screens -destination 'generic/platform=macOS' -showBuildSettings` prints `PRODUCT_NAME`.

## Phase 6 — Xcode Cloud

Fill IDs in `ci/workflow-screens.json` from the existing CI workflow
(`asc xcode-cloud workflows --app …` / `ci/workflow-ci.json`). Create it:

```sh
asc xcode-cloud workflows create --file ci/workflow-screens.json
```

One macOS BUILD of scheme `Screens`. PRs to `main` + manual branch. Do not add
this action to the existing CI workflow.

## Phase 7 — Capture once

On a Mac:

```sh
Tools/check-previews.sh
swift build --product preview-capture
Tools/capture-previews.sh
```

Commit `Designs/previews/<device>/*.png` with the UI change. Git history of that
folder is the visual timeline. README should mention scheme **Screens**,
`check-previews.sh`, `capture-previews.sh`, and `compare-previews.sh`.

Layout:

```
Designs/previews/
  iphone/   Dashboard-light.png   Dashboard-dark.png
  ipad/     …
  mac/      …
  tv/       …
  vision/   …
  watch/    …
```

```sh
Tools/capture-previews.sh                       # all devices
Tools/capture-previews.sh Designs/previews iphone,ipad
```

The CLI is a **macOS** executable. iPad/Mac/TV/vision/watch folders are the same
SwiftUI tree laid out at that canvas (and `horizontalSizeClass` compact vs
regular). They are not a watchOS / tvOS / visionOS runtime — `#if os(watchOS)`
views will not appear. For those, add a `#Preview` in the Watch/tvOS/vision
module and open the canvas on that destination.

Xcode canvas (any platform you can select as run destination):

```swift
#Preview("Dashboard") { DashboardView().appPreviewChrome() }
#Preview("Dashboard iPad") {
    DashboardView()
        .appPreviewChrome()
        .previewDevice(PreviewDevice(rawValue: "iPad Pro 11-inch (M4)"))
}
```

True watchOS / tvOS / visionOS canvas previews live in those modules (`WatchUI`, …)
behind `#if os(watchOS)` and are opened with that run destination — the PNG CLI
will not render them.

## Phase 8 — Compare current vs previous

Git is the archive. GitHub's PR image viewer (2-up / swipe / onion-skin) is the
best committed comparison. Locally, after a capture:

```sh
Tools/compare-previews.sh            # working tree vs last commit (HEAD)
Tools/compare-previews.sh main       # vs main
Tools/compare-previews.sh v1.2.0     # vs a tag
```

Output is `Designs/previews-diff/` (gitignored):

- `<device>/<Screen>-light-compare.png` — previous | current | magenta pixel diff
- `<device>/<Screen>-light-diff.png` — changed pixels only
- `summary.txt` — same / changed / new / removed, with % of pixels that moved

Add `Designs/previews-diff/` to `.gitignore`. Do not commit the diffs — they are
derived. The Screens Cloud workflow runs the same compare against the PR's
destination branch and copies the folder into the result bundle.

## Traps (from Tubeactions)

- Capture is **not** every Xcode compile of the app scheme — only Screens / `capture-previews.sh`.
- macOS `ImageRenderer` of `NavigationStack`/`List` is empty; use the NSHostingView helper in the template.
- `bitmap.size` must be **points**, `pixelsWide/High` the device scale (2× except tv at 1×), or content sits in a corner of a black canvas.
- Output is `Designs/previews/<device>/`, not a flat folder. `compare-previews.sh` recurses.
- Device folders are 2D macOS layouts. `#if os(watchOS)` / tvOS / visionOS views will not appear in the PNG CLI.
- `UNUserNotificationCenter.current()` traps in `preview-capture` (`bundleProxyForCurrentProcess is nil`) — default arguments, `AppModel` init, and `registerCategories()` all count. Move `.current()` inside the function, skip when `Bundle.main.bundleURL.pathExtension != "app"`, and add a preview override.
- `CKContainer(identifier:)` traps in the capture CLI (no iCloud entitlement). Preview factories must not construct CloudKit containers — offline/`usesCloudKit: false` stores, or skip `FeatureFlagService`/`AnalyticsService` configure in `AppModel(preview: true)`.
- MapKit in an offscreen `NSHostingView` can hit an AppKit constraint loop — keep Map out of the capture catalog.
- After a successful write the CLI must `Foundation.exit(0)`. NSHostingView/NSWindow can leave AppKit's run loop alive so Screens hangs after every PNG is already on disk.
- Shared auth / App Group `@AppStorage` will show whatever is on disk unless you add a preview override.
- `#Preview` does not take `arguments: [true, false]`. Use multiple named previews or `@Previewable @State`.
- Cloud will not see the scheme until `Screens.xcscheme` is on the branch it builds.
- Screens scheme post-actions inherit xcodebuild's env. That breaks `swift run`: `SDKROOT=auto` (`SDK "auto" cannot be located`), `OTHER_SWIFT_FLAGS` without `-package-name` (`package` access fails), and `BUILD_DIR`/`OBJROOT` (SPM product not found, e.g. `IkigaiAppShell`). `capture-previews.sh` must run `swift` via `env -i` (keep HOME/PATH/DEVELOPER_DIR). Unsetting SDKROOT alone is not enough.
- `swift run preview-capture` uses `Package.swift` + `Package.resolved`, not the Xcode target graph. Every product a UI target links must exist as an SPM product on the resolved pin (`swift package update` if Xcode is ahead of the pin).
- `install.sh --into-all` vendors this skill into `.agents/skills`. It does **not** refresh `Tools/capture-previews.sh` in each app — re-copy the template when the script changes.
