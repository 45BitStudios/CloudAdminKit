# Asset catalog structures & verification reference

Exact on-disk layouts the generator produces, per-platform slot tables, and the full
verification command table. All `Contents.json` files carry
`"info": {"author": "xcode", "version": 1}`.

## iOS / macOS / watchOS — `<IconName>.appiconset`

One appiconset can serve all three; `actool` filters entries by platform at build time.

```
AppIcon.appiconset/
├── Contents.json
├── AppIcon-1024.png            # ios universal 1024 (+ -dark / -tinted variants)
├── mac-16.png … mac-512@2x.png # macOS 16/32/128/256/512 pt @1x+@2x
└── AppIcon-watch-1024.png      # watchos universal 1024
```

Entry shapes:

```json
{ "filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024" }
{ "appearances": [{ "appearance": "luminosity", "value": "dark" }],
  "filename": "AppIcon-1024-dark.png", "idiom": "universal", "platform": "ios", "size": "1024x1024" }
{ "filename": "mac-256@2x.png", "idiom": "mac", "scale": "2x", "size": "256x256" }
{ "filename": "AppIcon-watch-1024.png", "idiom": "universal", "platform": "watchos", "size": "1024x1024" }
```

macOS pixel sizes: 16, 32 (16@2x), 32, 64 (32@2x), 128, 256 (128@2x), 256, 512 (256@2x),
512, 1024 (512@2x).

**Watch target catalog is separate.** Xcode's Watch template writes the same 1024
`watchos` shape **with no `filename`**. A main-app `.icon` does not populate
`Watch/Assets.xcassets/AppIcon.appiconset`. Generate `--platforms watchos --out
Watch/Assets.xcassets` and `actool` that path. A slot without `filename` (or a
filename that is not on disk) fails the iOS TestFlight archive.

## tvOS — `App Icon & Top Shelf Image.brandassets`

tvOS icons cannot live in an appiconset; they must be a brandassets bundle of layered
imagestacks plus Top Shelf imagesets. tvOS devices are 1x, but @2x slots are used for
App Store marketing — populate both.

```
App Icon & Top Shelf Image.brandassets/
├── Contents.json                       # role map, below
├── App Icon.imagestack/                # home-screen icon, 400x240 pt
│   ├── Contents.json                   # {"layers": [Front, Back]}
│   ├── Front.imagestacklayer/
│   │   ├── Contents.json               # info only
│   │   └── Content.imageset/           # front.png 400x240 + front@2x.png 800x480
│   └── Back.imagestacklayer/…          # back.png / back@2x.png
├── App Icon - App Store.imagestack/…   # same shape, 1280x768 / 2560x1536
├── Top Shelf Image.imageset/           # topshelf.png 1920x720 + @2x 3840x1440
└── Top Shelf Image Wide.imageset/      # topshelf-wide.png 2320x720 + @2x 4640x1440
```

brandassets `Contents.json`:

```json
{
  "assets": [
    { "filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768" },
    { "filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240" },
    { "filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720" },
    { "filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

Layer imagesets use `"idiom": "tv"` with `"scale": "1x"` / `"2x"`. An imagestack needs
at least two layers; a fully transparent Front layer is valid (flat-art ports do this).
**Back and Top Shelf images must be fully opaque** (`sips -g hasAlpha` → `no`). Alpha
at pixel (0, 0) is rejected at upload even when `actool` succeeds.

## visionOS — `<IconName>Vision.solidimagestack`

```
AppIconVision.solidimagestack/
├── Contents.json                       # {"layers": [Front, Back]}
├── Front.solidimagestacklayer/
│   ├── Contents.json                   # info only
│   └── Content.imageset/               # vision-front.png (transparent OK)
└── Back.solidimagestacklayer/…         # vision-back.png (must be opaque)
```

Image entries: `{ "filename": "vision-back.png", "idiom": "vision", "scale": "2x" }`.
1024 px = 512 pt @2x. The system applies the circular mask and gaze-driven depth.

## Icon Composer `.icon` documents (OS 26+)

A `.icon` is a folder bundle authored in Icon Composer (bundled with Xcode 26 at
`Xcode.app/Contents/Applications/Icon Composer.app`):

```
icon.icon/
├── icon.json          # recipe: background fill, groups/layers, glass, shadow, position
└── Assets/            # layer images referenced by icon.json (PNG/SVG)
```

`icon.json` sketch (real-world example):

```json
{
  "fill": { "linear-gradient": ["display-p3:0.09,0.03,0.06,1.0", "..."],
            "orientation": { "start": {"x": 0.5, "y": 1}, "stop": {"x": 0.5, "y": 0} } },
  "groups": [{ "layers": [{ "image-name": "logo.png", "glass": false,
                            "position": { "scale": 0.85, "translation-in-points": [0, 0] } }],
               "shadow": { "kind": "neutral", "opacity": 0.5 } }],
  "supported-platforms": { "circles": ["watchOS"], "squares": "shared" }
}
```

Don't author `icon.json` by hand beyond trivial tweaks — layout/glass parameters are
easiest to get right in the app. Wiring rules:

- File sits in the target folder; `ASSETCATALOG_COMPILER_APPICON_NAME` = its basename.
  With Xcode 16+ synchronized folder groups no pbxproj file reference is needed.
- Covers iOS/iPadOS/macOS/watchOS. **Not tvOS or visionOS** — those keep the
  brandassets/solidimagestack structures above, selected via the per-SDK
  `ASSETCATALOG_COMPILER_APPICON_NAME[sdk=...]` overrides. Both mechanisms coexist in
  one target (e.g. base name `icon` for the `.icon`, overrides for tv/vision).
- Pre-26 OS versions get a flattened rendering generated at build time; a same-named
  `.appiconset` in the catalog serves as an explicit legacy override when present.
- Verify by passing the `.icon` itself as an actool input (alongside the `.xcassets`
  path if there is one):

  ```bash
  xcrun actool --compile "$OUT" --platform iphonesimulator --target-device iphone \
    --minimum-deployment-target 17.0 --app-icon icon \
    --output-partial-info-plist "$OUT/partial.plist" path/to/icon.icon
  ```

  Success: `CFBundleIcons → CFBundlePrimaryIcon → CFBundleIconName = <basename>` plus
  flattened legacy PNGs (`icon60x60@2x.png`, …) in the output — those are the
  auto-generated pre-26 fallbacks.

## Build-setting wiring (single multiplatform target)

```
ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
"ASSETCATALOG_COMPILER_APPICON_NAME[sdk=appletvos*]" = "App Icon & Top Shelf Image";
"ASSETCATALOG_COMPILER_APPICON_NAME[sdk=appletvsimulator*]" = "App Icon & Top Shelf Image";
"ASSETCATALOG_COMPILER_APPICON_NAME[sdk=xros*]" = AppIconVision;
"ASSETCATALOG_COMPILER_APPICON_NAME[sdk=xrsimulator*]" = AppIconVision;
```

Add to every build configuration of the app target (Debug **and** Release). A safe
scripted edit that hits all configs at once:

```bash
perl -0pi -e 's/(ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;\n)/$1\t\t\t\t"ASSETCATALOG_COMPILER_APPICON_NAME[sdk=appletvos*]" = "App Icon & Top Shelf Image";\n\t\t\t\t"ASSETCATALOG_COMPILER_APPICON_NAME[sdk=appletvsimulator*]" = "App Icon & Top Shelf Image";\n\t\t\t\t"ASSETCATALOG_COMPILER_APPICON_NAME[sdk=xros*]" = AppIconVision;\n\t\t\t\t"ASSETCATALOG_COMPILER_APPICON_NAME[sdk=xrsimulator*]" = AppIconVision;\n/g' project.pbxproj
plutil -lint project.pbxproj
```

## actool verification table

`--target-device` is mandatory — omitting it makes actool exit 0 having compiled
nothing (empty partial plist, no Assets.car, no error message).

| Platform | `--platform` | `--target-device` | `--app-icon` |
|----------|--------------|-------------------|--------------|
| iOS | `iphonesimulator` | `iphone` | `AppIcon` |
| macOS | `macosx` | `mac` | `AppIcon` |
| watchOS | `watchsimulator` | `watch` | `AppIcon` |
| tvOS | `appletvsimulator` | `tv` | `App Icon & Top Shelf Image` |
| visionOS | `xrsimulator` | `vision` | `AppIconVision` |

```bash
for CHECK in "iphonesimulator iphone AppIcon" \
             "appletvsimulator tv App Icon & Top Shelf Image" \
             "xrsimulator vision AppIconVision"; do
  set -- $CHECK; PLATFORM=$1 DEVICE=$2; shift 2; ICON="$*"
  OUT=$(mktemp -d)
  xcrun actool --compile "$OUT" --platform "$PLATFORM" --target-device "$DEVICE" \
    --minimum-deployment-target 17.0 --app-icon "$ICON" \
    --output-partial-info-plist "$OUT/partial.plist" Assets.xcassets >/dev/null
  echo "== $PLATFORM"; plutil -p "$OUT/partial.plist"
done
```

Success looks like `CFBundleIcons → CFBundlePrimaryIcon = <icon name>` in the partial
plist (tvOS also gets `TVTopShelfImage` entries), and `xcrun assetutil --info
$OUT/Assets.car` lists the icon assets. An empty `{}` plist means the icon name or the
platform/device pair is wrong.
