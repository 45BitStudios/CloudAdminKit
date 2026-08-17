#!/usr/bin/env swift
// generate_icons.swift — build Apple app-icon asset-catalog structures from master art.
//
// Usage:
//   swift generate_icons.swift --master <1024x1024.png> --out <path/to/Assets.xcassets> \
//     [--platforms ios,macos,watchos,tvos,visionos]   default: all five
//     [--icon-name AppIcon]                           appiconset base name
//     [--ios-dark <png>] [--ios-tinted <png>]         optional iOS appearance variants (1024)
//     [--tv-icon <5:3 png>]                           dedicated tvOS icon art (else derived from master)
//     [--tv-store <1280x768 png>]                     dedicated tvOS App Store art (else falls back)
//     [--topshelf <wide png>]                         dedicated Top Shelf art (else falls back)
//
// Writes into the .xcassets directory:
//   ios/macos/watchos -> <icon-name>.appiconset (single catalog, per-platform entries)
//   tvos              -> "App Icon & Top Shelf Image.brandassets" (layered imagestacks + Top Shelf)
//   visionos          -> "<icon-name>Vision.solidimagestack"
//
// Art that doesn't match a target aspect ratio is scaled to fit and the background is
// extended by stretching the outermost pixel rows/columns — seamless for icons with a
// gradient or solid background. Layered stacks get the full art as the Back layer and a
// transparent Front layer (replace with real layers in Icon Composer for true parallax).

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - CLI parsing

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + msg + "\n").utf8))
    exit(1)
}

var opts: [String: String] = [:]
var argv = Array(CommandLine.arguments.dropFirst())
var i = 0
while i < argv.count {
    guard argv[i].hasPrefix("--"), i + 1 < argv.count else { fail("bad argument: \(argv[i])") }
    opts[String(argv[i].dropFirst(2))] = argv[i + 1]
    i += 2
}

guard let masterPath = opts["master"] else { fail("--master <1024x1024.png> is required") }
guard let outPath = opts["out"] else { fail("--out <path/to/Assets.xcassets> is required") }
let platforms = Set((opts["platforms"] ?? "ios,macos,watchos,tvos,visionos")
    .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
let iconName = opts["icon-name"] ?? "AppIcon"
let outURL = URL(fileURLWithPath: outPath)
let fm = FileManager.default

// MARK: - Image helpers

func loadImage(_ path: String) -> CGImage {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fail("cannot read image: \(path)") }
    return img
}

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    guard let ctx = CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fail("cannot create \(w)x\(h) context") }
    return ctx
}

func writePNG(_ image: CGImage, _ url: URL) {
    try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fail("cannot write \(url.path)") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fail("failed to finalize \(url.path)") }
    print("wrote \(url.path)")
}

func transparent(_ w: Int, _ h: Int) -> CGImage { makeContext(w, h).makeImage()! }

/// Scale to fit the target box; fill any padding by stretching the art's outermost
/// pixel rows/columns so a gradient or solid background continues seamlessly.
func fitExtend(_ image: CGImage, _ w: Int, _ h: Int) -> CGImage {
    let srcW = CGFloat(image.width), srcH = CGFloat(image.height)
    let fit = min(CGFloat(w) / srcW, CGFloat(h) / srcH)
    let fitW = srcW * fit, fitH = srcH * fit
    let padX = (CGFloat(w) - fitW) / 2, padY = (CGFloat(h) - fitH) / 2

    let ctx = makeContext(w, h)
    ctx.interpolationQuality = .high
    if padX > 0.5 {
        let left = image.cropping(to: CGRect(x: 0, y: 0, width: 1, height: srcH))!
        let right = image.cropping(to: CGRect(x: srcW - 1, y: 0, width: 1, height: srcH))!
        ctx.draw(left, in: CGRect(x: 0, y: padY, width: padX + 1, height: fitH))
        ctx.draw(right, in: CGRect(x: CGFloat(w) - padX - 1, y: padY, width: padX + 1, height: fitH))
    }
    if padY > 0.5 {
        // CGImage row 0 is the TOP of the picture; CGContext y=0 is the BOTTOM.
        let top = image.cropping(to: CGRect(x: 0, y: 0, width: srcW, height: 1))!
        let bottom = image.cropping(to: CGRect(x: 0, y: srcH - 1, width: srcW, height: 1))!
        ctx.draw(top, in: CGRect(x: padX, y: CGFloat(h) - padY - 1, width: fitW, height: padY + 1))
        ctx.draw(bottom, in: CGRect(x: padX, y: 0, width: fitW, height: padY + 1))
    }
    ctx.draw(image, in: CGRect(x: padX, y: padY, width: fitW, height: fitH))
    return ctx.makeImage()!
}

// MARK: - Contents.json helpers

let xcodeInfo: [String: Any] = ["author": "xcode", "version": 1]

func writeJSON(_ dict: [String: Any], _ url: URL) {
    try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
    else { fail("cannot encode JSON for \(url.path)") }
    try! data.write(to: url)
    print("wrote \(url.path)")
}

// MARK: - Load sources

let master = loadImage(masterPath)
guard master.width == master.height else { fail("--master must be square (got \(master.width)x\(master.height))") }
let tvIconArt = opts["tv-icon"].map(loadImage) ?? master
let tvStoreArt = opts["tv-store"].map(loadImage) ?? tvIconArt
let topShelfArt = opts["topshelf"].map(loadImage) ?? tvStoreArt

// MARK: - iOS / macOS / watchOS -> one appiconset

if !platforms.isDisjoint(with: ["ios", "macos", "watchos"]) {
    let setDir = outURL.appendingPathComponent("\(iconName).appiconset")
    var images: [[String: Any]] = []

    if platforms.contains("ios") {
        writePNG(fitExtend(master, 1024, 1024), setDir.appendingPathComponent("\(iconName)-1024.png"))
        images.append(["filename": "\(iconName)-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"])
        for (flag, appearance) in [("ios-dark", "dark"), ("ios-tinted", "tinted")] {
            guard let path = opts[flag] else { continue }
            let name = "\(iconName)-1024-\(appearance).png"
            writePNG(fitExtend(loadImage(path), 1024, 1024), setDir.appendingPathComponent(name))
            images.append([
                "appearances": [["appearance": "luminosity", "value": appearance]],
                "filename": name, "idiom": "universal", "platform": "ios", "size": "1024x1024",
            ])
        }
    }
    if platforms.contains("macos") {
        for pt in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let suffix = scale == 2 ? "@2x" : ""
                let name = "mac-\(pt)\(suffix).png"
                writePNG(fitExtend(master, pt * scale, pt * scale), setDir.appendingPathComponent(name))
                images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(pt)x\(pt)"])
            }
        }
    }
    if platforms.contains("watchos") {
        let name = "\(iconName)-watch-1024.png"
        writePNG(fitExtend(master, 1024, 1024), setDir.appendingPathComponent(name))
        images.append(["filename": name, "idiom": "universal", "platform": "watchos", "size": "1024x1024"])
    }
    writeJSON(["images": images, "info": xcodeInfo], setDir.appendingPathComponent("Contents.json"))
}

// MARK: - tvOS -> brandassets (layered imagestacks + Top Shelf)

if platforms.contains("tvos") {
    let brand = outURL.appendingPathComponent("App Icon & Top Shelf Image.brandassets")

    func writeStack(_ stackName: String, art: CGImage, w: Int, h: Int) {
        let stack = brand.appendingPathComponent("\(stackName).imagestack")
        writeJSON(
            ["layers": [["filename": "Front.imagestacklayer"], ["filename": "Back.imagestacklayer"]], "info": xcodeInfo],
            stack.appendingPathComponent("Contents.json"))
        for (layer, oneX, twoX) in [
            ("Front", transparent(w, h), transparent(w * 2, h * 2)),
            ("Back", fitExtend(art, w, h), fitExtend(art, w * 2, h * 2)),
        ] {
            let layerDir = stack.appendingPathComponent("\(layer).imagestacklayer")
            writeJSON(["info": xcodeInfo], layerDir.appendingPathComponent("Contents.json"))
            let imageset = layerDir.appendingPathComponent("Content.imageset")
            let base = layer.lowercased()
            writePNG(oneX, imageset.appendingPathComponent("\(base).png"))
            writePNG(twoX, imageset.appendingPathComponent("\(base)@2x.png"))
            writeJSON([
                "images": [
                    ["filename": "\(base).png", "idiom": "tv", "scale": "1x"],
                    ["filename": "\(base)@2x.png", "idiom": "tv", "scale": "2x"],
                ],
                "info": xcodeInfo,
            ], imageset.appendingPathComponent("Contents.json"))
        }
    }

    func writeTopShelf(_ setName: String, art: CGImage, w: Int, h: Int, base: String) {
        let imageset = brand.appendingPathComponent("\(setName).imageset")
        writePNG(fitExtend(art, w, h), imageset.appendingPathComponent("\(base).png"))
        writePNG(fitExtend(art, w * 2, h * 2), imageset.appendingPathComponent("\(base)@2x.png"))
        writeJSON([
            "images": [
                ["filename": "\(base).png", "idiom": "tv", "scale": "1x"],
                ["filename": "\(base)@2x.png", "idiom": "tv", "scale": "2x"],
            ],
            "info": xcodeInfo,
        ], imageset.appendingPathComponent("Contents.json"))
    }

    writeStack("App Icon", art: tvIconArt, w: 400, h: 240)
    writeStack("App Icon - App Store", art: tvStoreArt, w: 1280, h: 768)
    writeTopShelf("Top Shelf Image", art: topShelfArt, w: 1920, h: 720, base: "topshelf")
    writeTopShelf("Top Shelf Image Wide", art: topShelfArt, w: 2320, h: 720, base: "topshelf-wide")
    writeJSON([
        "assets": [
            ["filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"],
            ["filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"],
            ["filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"],
            ["filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"],
        ],
        "info": xcodeInfo,
    ], brand.appendingPathComponent("Contents.json"))
}

// MARK: - visionOS -> solidimagestack

if platforms.contains("visionos") {
    let stack = outURL.appendingPathComponent("\(iconName)Vision.solidimagestack")
    writeJSON(
        ["layers": [["filename": "Front.solidimagestacklayer"], ["filename": "Back.solidimagestacklayer"]], "info": xcodeInfo],
        stack.appendingPathComponent("Contents.json"))
    for (layer, image) in [("Front", transparent(1024, 1024)), ("Back", fitExtend(master, 1024, 1024))] {
        let layerDir = stack.appendingPathComponent("\(layer).solidimagestacklayer")
        writeJSON(["info": xcodeInfo], layerDir.appendingPathComponent("Contents.json"))
        let imageset = layerDir.appendingPathComponent("Content.imageset")
        let name = "vision-\(layer.lowercased()).png"
        writePNG(image, imageset.appendingPathComponent(name))
        writeJSON([
            "images": [["filename": name, "idiom": "vision", "scale": "2x"]],
            "info": xcodeInfo,
        ], imageset.appendingPathComponent("Contents.json"))
    }
}

print("""

Done. Next steps (see SKILL.md):
1. Wire build settings — a single multiplatform target needs per-SDK overrides:
     ASSETCATALOG_COMPILER_APPICON_NAME = \(iconName);
     "ASSETCATALOG_COMPILER_APPICON_NAME[sdk=appletvos*]" = "App Icon & Top Shelf Image";
     "ASSETCATALOG_COMPILER_APPICON_NAME[sdk=appletvsimulator*]" = "App Icon & Top Shelf Image";
     "ASSETCATALOG_COMPILER_APPICON_NAME[sdk=xros*]" = \(iconName)Vision;
     "ASSETCATALOG_COMPILER_APPICON_NAME[sdk=xrsimulator*]" = \(iconName)Vision;
2. Verify with actool per platform (remember --target-device).
""")
