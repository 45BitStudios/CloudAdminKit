# Binary-size playbook

Distilled from EmpressBlood's binary-size review (a >100 MB install traced back to two root
causes and cut roughly in half). Copy this file into every new repo as
`docs/binary-size-playbook.md`; `Tools/check-size.sh` is the enforcement half.

## The four rules that prevent the problem

1. **SwiftPM `.process` resources ship byte-for-byte** — no actool optimization, no app
   thinning. A resource's on-disk size IS its shipped size. Asset catalogs (`.xcassets`) are
   recompiled into `Assets.car` and thinned per device, so prefer catalogs for images the
   system should manage, and keep loose `Resources/` for data that must ship verbatim.
2. **Package resource bundles duplicate into every client target.** If the app AND an
   extension (widget, iMessage, watch) both link a library, its resource bundle ships twice.
   Keep heavy seeds in the **app target** and let extensions read the containing app's bundle
   (`Bundle(url: appBundleURL)`) — an appex lives inside `<App>.app/PlugIns/`, and the app
   bundle is readable from the extension sandbox. No App Group copy needed.
3. **Third-party SDKs stay out of extension-reachable targets.** Statically linked SDKs
   (store/analytics) duplicate into every appex that links the UI library. Put them behind a
   protocol seam in the Data layer, in a separate product linked by the app target only,
   injected at launch. (This is already the layering rule — size is the second reason it exists.)
4. **Heavy content streams post-install.** Bundled media is the offline-first seed only, with
   an explicit KB budget; full-quality tiers download OTA (CDN or Apple-Hosted Background
   Assets `prefetch` packs, which add zero to the App Store download).

## Encoding cheat sheet (biggest wins per minute spent)

| Asset | Do | Typical win |
|---|---|---|
| Placeholder/seed art | JPEG quality ~78, progressive, sized for display (not retina-perfect) | 26 MB → 10.5 MB on 154 cards, visually indistinguishable |
| Real art tiers | HEIC, multiple resolution tiers, OTA only | not in the binary at all |
| Gameplay SFX | `afconvert -f caff -d aac in.wav out.caf` (AVAudioPlayer/SpriteKit play AAC-in-CAF fine) | ~10:1 vs PCM WAV |
| **Notification sounds** | `afconvert -f caff -d ima4` — `UNNotificationSound` does **not** play AAC | ~4:1, and it actually plays |
| tvOS top-shelf / store imagestack | Flatten alpha (composited opaque anyway), 8-bit, re-export | multi-MB on photographic PNGs |
| PNGs kept as PNG | Lossless recompress (`oxipng`/`pngcrush`), pixels untouched | ~10% |

## Measuring — working tree vs truth

- `Tools/check-size.sh` — repo-side proxy; gates CI on the verbatim-resource budget.
- `Tools/check-size.sh --app <.app>` / `--archive <.xcarchive>` — built-product breakdown:
  per-appex, per-framework, per-bundle, `Assets.car`.
- **Ground truth:** export an archive with app thinning → `App Thinning Size Report.txt`
  gives per-device download/install sizes. Store-listed size also includes binary encryption,
  so even this is ±. `xcrun assetutil --info Assets.car` shows what actool actually emitted.
- Check sizes **per platform**: the tvOS/visionOS archives carry different asset subsets.

## Budgets

Set `RESOURCE_BUDGET_KB` in `Tools/check-size.sh` consciously at onboarding (default 10 MB of
verbatim resources) and treat raising it as a reviewed decision, not a reflex when the check
goes red. The one-line history of every raise belongs in the commit that raises it.

## Repo hygiene

Marketing/source images (logos, screenshots, Icon Composer sources are fine — they're
compile-time inputs) that aren't referenced by any target are clone weight; delete them or
move to Git LFS. `check-size.sh` lists repo-root files over 1 MB for exactly this.
