---
name: apple-app-icons
description: Generate complete Apple app-icon asset catalogs for iOS, macOS, watchOS, tvOS, and visionOS from master art PNGs — every required size, the layered tvOS brandassets (App Icon + Top Shelf), the visionOS solidimagestack, all Contents.json wiring, Xcode build-setting overrides, and actool verification. Use this whenever the user wants app icons added, generated, resized, or "showing up" for any Apple platform or Xcode target, mentions AppIcon.appiconset, brandassets, imagestacks, Top Shelf images, or says their app has no icon on tvOS/visionOS/watchOS — even if they only name one platform. Also covers wiring Icon Composer .icon documents (liquid glass, iOS/macOS/watchOS 26+) alongside the bitmap catalogs.
---

# Apple App Icons — all platforms from master art

Build every platform's icon assets from master art with the bundled generator, wire the
Xcode project, and verify with `actool` — no manual slot-by-slot work in Xcode.

## Inputs to collect first

- **Master art**: one square PNG, ideally 1024×1024 (required). Look for it in the repo
  (`Design/`, `Assets/`, `art/`…) before asking the user.
- **Optional dedicated art** (better results when available, but everything can be derived
  from the square master): a 5:3 tvOS icon (400×240 or larger), a 1280×768 tvOS App Store
  icon, a wide Top Shelf banner, iOS dark/tinted 1024 variants.
- **Target catalog**: the app target's `Assets.xcassets` path.
- **Which platforms** the project actually builds for — check `SUPPORTED_PLATFORMS` in
  `project.pbxproj`. Don't generate assets for platforms the project can't build; offer
  them as an option instead.

## Step 1 — Generate

```bash
swift <skill-path>/scripts/generate_icons.swift \
  --master path/to/master-1024.png \
  --out path/to/Assets.xcassets \
  --platforms ios,macos,watchos,tvos,visionos   # trim to what the project supports
# optional: --icon-name AppIcon --tv-icon art.png --tv-store art.png --topshelf art.png \
#           --ios-dark dark.png --ios-tinted tinted.png
```

What it produces (see `references/catalog-structures.md` for the exact layouts and why):

| Platform | Asset | Notes |
|----------|-------|-------|
| iOS | `AppIcon.appiconset` 1024 universal (+ dark/tinted if given) | single-size, Xcode 14+ style |
| macOS | same appiconset, 16–512 @1x/@2x slots | downscaled from master |
| watchOS | same appiconset, 1024 `platform: watchos` entry | single-size |
| tvOS | `App Icon & Top Shelf Image.brandassets` | layered 400×240 + 1280×768 imagestacks, Top Shelf 1920×720 + wide 2320×720, each @1x/@2x |
| visionOS | `AppIconVision.solidimagestack` | 1024 px = 512 pt @2x |

Key behaviors, so you can explain them to the user:

- Art that doesn't match a target aspect ratio is scaled to fit and the background is
  extended by stretching the outermost pixel rows/columns — seamless for gradient or
  solid backgrounds (most icon art). If the master has a busy full-bleed background, the
  extension will look wrong; ask for dedicated 5:3 / Top Shelf art in that case.
- tvOS/visionOS layered stacks get the full art as the **Back** layer and a transparent
  **Front** layer. That's valid and standard when the art is a flat composite; mention
  that real parallax needs layered art (Icon Composer) as a later upgrade.
- **Back and Top Shelf bitmaps must be fully opaque.** Upload rejects a stack whose last
  content layer has alpha at (0, 0): *"The last image stack layer with content, “Back”,
  must be a fully opaque bitmap."* Same for Top Shelf Wide. Composite onto the brand
  fill first (`sips -g hasAlpha` must report `no`). A `.icon` with a transparent
  canvas is a common source — flatten before generating tv/vision.
- Do **not** pre-round corners or pre-crop circles — the OS applies every mask.

## Step 2 — Wire the Xcode project

- **Dedicated target per platform**: each target just sets
  `ASSETCATALOG_COMPILER_APPICON_NAME` to the right asset name (`AppIcon`,
  `App Icon & Top Shelf Image`, `AppIconVision`).
- **Single multiplatform target** (one target, several `SUPPORTED_PLATFORMS`): add
  per-SDK overrides to **both** Debug and Release configurations in `project.pbxproj`
  (the generator prints the exact block). Without these, tvOS/visionOS silently build
  with no icon because the shared `AppIcon` set has no tv/vision entries.
- **watchOS**: the Watch app is always its **own target with its own `Assets.xcassets`**.
  Point `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` at *that* catalog. A main-app
  `.icon` or `AppIcon.appiconset` does **not** fill it. Xcode's Watch template writes a
  1024 `watchos` slot with **no `filename` and no PNG** — `actool` on the *main* catalog
  stays green, then the iOS TestFlight archive fails (Watch is `platformFilter = ios`
  only). Generate into the Watch catalog, not the main one:

  ```bash
  swift <skill-path>/scripts/generate_icons.swift \
    --master path/to/master-1024.png \
    --out path/to/Watch/Assets.xcassets \
    --platforms watchos
  ```

  Then `actool` **that** catalog (`watchsimulator` / `watch`). Audit every
  `AppIcon.appiconset` whose `Contents.json` has `"platform": "watchos"`: each slot
  needs a `filename` that exists on disk. Empty iOS/mac slots next to a `.icon` are
  fine; an empty Watch slot is not.

After editing `project.pbxproj`, run `plutil -lint project.pbxproj` to confirm it still
parses.

## Step 3 — Verify (don't skip)

`actool` compiles per platform in seconds — far cheaper than a full build:

```bash
xcrun actool --compile /tmp/actool-out --platform appletvsimulator --target-device tv \
  --minimum-deployment-target 17.0 --app-icon "App Icon & Top Shelf Image" \
  --output-partial-info-plist /tmp/actool-out/partial.plist path/to/Assets.xcassets
plutil -p /tmp/actool-out/partial.plist   # expect CFBundlePrimaryIcon (+ TVTopShelfImage on tvOS)
```

**Gotcha: `--target-device` is required.** Without it actool exits 0 but compiles
*nothing* — an empty partial plist and no `Assets.car`, with no error. Pairs:
`iphonesimulator`/`iphone`, `macosx`/`mac`, `watchsimulator`/`watch`,
`appletvsimulator`/`tv`, `xrsimulator`/`vision`, and use each platform's icon name.
`references/catalog-structures.md` has the full per-platform command table.

For final confidence, an `xcodebuild` for the relevant simulator destination proves it
end-to-end; check the built app's `Info.plist` registers `CFBundleIcons` →
`CFBundlePrimaryIcon` (and `TVTopShelfImage` on tvOS).

## Icon Composer `.icon` files (iOS/iPadOS/macOS/watchOS 26+)

If the user has (or wants) a layered liquid-glass icon, that's an Icon Composer `.icon`
document — a folder bundle with an `icon.json` recipe plus an `Assets/` folder of layer
images. Authoring one is a design-tool workflow (Icon Composer ships inside Xcode at
`Xcode.app/Contents/Applications/Icon Composer.app`), but **wiring an existing `.icon`
is your job**:

1. Put `<Name>.icon` in the app target's folder (with synchronized folder groups it's
   picked up automatically; older projects need it added to the target).
2. Set `ASSETCATALOG_COMPILER_APPICON_NAME = <Name>` (the basename, no extension).
3. **The `.icon` only covers iOS, iPadOS, macOS, and watchOS.** tvOS and visionOS still
   need this skill's brandassets/solidimagestack plus the per-SDK overrides from Step 2
   — the two mechanisms compose, which is exactly how production apps ship.
4. Older-OS fallback: Xcode renders flattened icons from the `.icon` for pre-26
   deployment targets automatically; a same-named `.appiconset` (from Step 1) acts as an
   explicit override for older systems when both exist.

Icon Composer can export a flat 1024 PNG (File → Export) — use that as `--master` for
the generator so the bitmap platforms match the liquid-glass design. See
`references/catalog-structures.md` for the `.icon` bundle layout.

## iMessage sticker icon sets

The generator does NOT cover the Messages extension's
`iMessage App Icon.stickersiconset` — and an unpopulated one fails the TestFlight upload
(uploads need all 13 slots, including the 1024×768 store icon, all **opaque**). Use the
bundled filler:

```bash
swift <skill-path>/scripts/fill_stickers_icons.swift path/to/master-1024.png \
  "path/to/Message/Assets.xcassets/iMessage App Icon.stickersiconset"
```

It writes all 13 slots (iPhone/iPad/universal landscape + both marketing sizes) and the
`Contents.json`. Landscape slots are aspect-fit letterboxed, with the padding color
**sampled from the master's corner pixel** — never a hardcoded color, or light art gets
black bars (and vice versa).

**Verifying stickers needs two flags the Step 3 table doesn't have.** A stickersiconset is
not an app icon: with only `--app-icon` + `--target-device`, actool exits **0** and compiles
**nothing** — empty partial plist, no `Assets.car`, no error. That reads as a broken
stickersiconset, so the trap is spending the next hour "fixing" assets that were already
correct. Add `--stickers-icon-role` and `--sticker-pack-identifier-prefix`:

```bash
xcrun actool --compile /tmp/actool-msg --platform iphonesimulator \
  --target-device iphone --target-device ipad \
  --minimum-deployment-target 26.0 \
  --app-icon "iMessage App Icon" \
  --stickers-icon-role extension \
  --sticker-pack-identifier-prefix com.you.App.Message.sticker-pack. \
  --output-partial-info-plist /tmp/actool-msg/partial.plist \
  path/to/Message/Assets.xcassets
plutil -p /tmp/actool-msg/partial.plist
```

Expect `CFBundleIcons` → `CFBundlePrimaryIcon` **and `MSMessagesExtensionStoreIconName`**.
That second key is the whole point of the 1024×768 slot — its absence is ITMS-90642 at
upload. Confirm opacity too (`sips -g hasAlpha`); alpha in these icons is rejected.

## Per-platform art variants

Different platforms sit on different backgrounds — dark art often reads better on tvOS
(dark home screen) and watchOS (black watch faces) while light art suits iOS/macOS. Run
the generator once per art variant with only that variant's platforms:

```bash
swift generate_icons.swift --master light.png --ios-dark dark.png --out App/Assets.xcassets --platforms ios,macos,visionos
swift generate_icons.swift --master dark.png  --out App/Assets.xcassets --platforms tvos
swift generate_icons.swift --master dark.png  --out Watch/Assets.xcassets --platforms watchos
```

**Regeneration scope warning:** iOS, macOS, and watchOS entries share ONE
`AppIcon.appiconset` — regenerating any one of them alone into a shared catalog rewrites
the whole set and silently drops the other platforms' entries. Regenerate those together
(or give watchOS its own catalog — watch apps are separate targets anyway). tvOS
(`.brandassets`) and visionOS (`.solidimagestack`) are separate folders, safe to
regenerate individually.

## Diagnosing an iOS-only TestFlight icon failure

If `Archive - iOS` fails *"Preparing build for App Store Connect failed"* while
macOS/tvOS/visionOS from the same run succeed, the defect is almost always in a bundle
only iOS embeds: Watch (`platformFilter = ios`), then NSE/NCE/iMessage. `actool` the
**Watch** catalog first — an empty 1024 `watchos` slot is the usual cause. Do not
"fix" the main app icon; it already uploaded on the other platforms.

## Scope notes

- If an `AppIcon.appiconset` already exists with entries you'd clobber, read its
  `Contents.json` first and merge (the generator overwrites the whole set — pass a
  different `--icon-name` or regenerate all platforms together so nothing is lost).
