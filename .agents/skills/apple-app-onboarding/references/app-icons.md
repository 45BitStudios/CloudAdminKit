# App icons — every platform wants a different format

Icons are upload-time failures, not build-time failures: a missing or wrong-format icon
surfaces as an ITMS error on the first TestFlight upload. Set them all up during onboarding,
right after the extension targets exist. One design source, then fan out per platform.

## Icon Composer covers iOS/iPadOS, macOS, and watchOS — not tvOS or visionOS

Design the icon once in **Icon Composer** (ships with Xcode 26): layered artwork that the
system renders as Liquid Glass, in light/dark/tinted variants, for iPhone, iPad, Mac, and
Apple Watch.

1. Save the `.icon` file (e.g. `AppIcon.icon`) into the app target's folder — synchronized
   folder groups auto-include it, no pbxproj edit.
2. Point each target's **App Icon** setting (`ASSETCATALOG_COMPILER_APPICON_NAME` /
   the "App Icons and Launch Screen" pane) at it for the iOS/macOS app and the watch app.
3. Keep the source project for the icon (the Composer document) in the repo — regenerating
   variants later is otherwise painful. The recipe inside (`AppIcon.icon/icon.json`) is
   readable JSON (gradient stops, layer scale); useful for programmatically matching brand
   colors elsewhere.

The App Store marketing icon (1024×1024) is generated from the same artwork; it must be
**opaque** — validation rejects alpha.

## tvOS — layered parallax icon + Top Shelf, in the asset catalog

Icon Composer does not produce tvOS assets. In the tvOS target's asset catalog create the
**App Icon & Top Shelf Image** brand-assets set; every slot below is required for App Store
submission:

| Asset | Size (@1x / @2x) | Notes |
|---|---|---|
| App Icon | 400×240 / 800×480 | 2–5 layers (front/middle/back) for the parallax effect |
| App Icon — App Store | 1280×768 | layered, same artwork |
| Top Shelf Image Wide | 2320×720 / 4640×1440 | shown when the app is in the top row |

Layers are separate PNGs per slot; the back layer **and both Top Shelf images** must be
fully opaque (`sips -g hasAlpha` → `no`). Alpha at pixel (0, 0) is rejected at upload
even when `actool` is green. Flatten `.icon` composites onto the brand fill first. A
flat icon dropped into one layer "works" but looks dead next to every other tvOS app —
split at least background / logo into two layers.

## visionOS — 3-layer circular icon

In the visionOS target's asset catalog, the App Icon set takes **three 1024×1024 layers**
(back / middle / front). The back layer must be opaque; middle and front use alpha. The
system applies the circular mask and depth — don't pre-mask the artwork to a circle.

## watchOS — the Watch target's catalog is not the main app's `.icon`

Xcode's Watch template creates `Watch/Assets.xcassets/AppIcon.appiconset` with a 1024
`watchos` slot and **no `filename`**. Putting `AppIcon.icon` on the **main** app (or
filling the main `AppIcon.appiconset`) does **not** populate that catalog. Watch is
embedded only in the iOS archive (`platformFilter = ios`), so an empty Watch icon looks
like a mysterious iOS-only TestFlight failure while macOS/tvOS/visionOS succeed.

Generate into the Watch catalog with the apple-app-icons skill (`--platforms watchos
--out Watch/Assets.xcassets`) and `actool` **that** path. The system applies the
circular mask — don't pre-mask. A Watch widget's empty `AppIcon` is inert; the Watch
**app** catalog is not.

## iMessage extension — the trap that costs an upload

The `iMessage App Icon.stickersiconset` must be **fully populated** with **opaque** PNGs at
every slot (mostly 4:3: 54×40 … 180×135) **including the 1024×768 store icon** — that slot is
what auto-generates `MSMessagesExtensionStoreIconName`. An empty iconset uploads fine and then
fails with ITMS-90649 + ITMS-90642. Composite alpha art onto the brand background first.

## Rendering derived sizes without design tools

Proven approach from EmpressBlood: read the Icon Composer recipe (`icon.json` → gradient stops
+ logo scale) and render each required size with a ~40-line Swift + CoreGraphics script
(`swift render-icons.swift`) — no ImageMagick/Pillow dependency, output is already opaque, and
re-running it after an artwork tweak regenerates every slot identically.

## Onboarding checklist

- [ ] `AppIcon.icon` (Icon Composer) in the app target; set for iOS/iPadOS, macOS
- [ ] Watch **target** `AppIcon.appiconset`: 1024 `watchos` slot has a PNG on disk (`actool` that catalog)
- [ ] tvOS brand assets: layered App Icon (400×240, 1280×768) + Top Shelf — Back and Top Shelf opaque
- [ ] visionOS: 3 × 1024×1024 layers, opaque back, no pre-masking
- [ ] iMessage extension (if present): stickersiconset fully populated, opaque, incl. 1024×768
- [ ] All marketing/store icons opaque — no alpha channel anywhere App Store validation looks
