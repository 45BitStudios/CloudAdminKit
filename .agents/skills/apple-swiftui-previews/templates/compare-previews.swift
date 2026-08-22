#!/usr/bin/env swift
import AppKit
import Foundation

/// Pixel-diff two directories of PNGs (previous vs current).
///
/// Writes `<stem>-diff.png` (changed pixels in magenta) and
/// `<stem>-compare.png` (previous | current | diff) into the output directory.

struct Arguments {
    var previous: URL
    var current: URL
    var output: URL
}

func parseArguments() -> Arguments {
    let args = CommandLine.arguments
    func value(for flag: String) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else {
            return nil
        }
        return args[index + 1]
    }
    guard let previous = value(for: "--previous"),
          let current = value(for: "--current"),
          let output = value(for: "--output")
    else {
        fputs(
            "usage: compare-previews.swift --previous <dir> --current <dir> --output <dir>\n",
            stderr
        )
        exit(2)
    }
    return Arguments(
        previous: URL(fileURLWithPath: previous, isDirectory: true),
        current: URL(fileURLWithPath: current, isDirectory: true),
        output: URL(fileURLWithPath: output, isDirectory: true)
    )
}

func pngs(in directory: URL) -> [String: URL] {
    let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: nil
    )
    var map: [String: URL] = [:]
    while let file = enumerator?.nextObject() as? URL {
        guard file.pathExtension.lowercased() == "png" else { continue }
        let key = file.path.replacingOccurrences(of: directory.path + "/", with: "")
        map[key] = file
    }
    return map
}

func rasterize(_ url: URL, width: Int? = nil, height: Int? = nil) -> (width: Int, height: Int, pixels: [UInt8])? {
    guard let image = NSImage(contentsOf: url) else { return nil }
    var proposed = CGRect(origin: .zero, size: image.size)
    guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
        return nil
    }
    let width = width ?? cgImage.width
    let height = height ?? cgImage.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    context.interpolationQuality = .none
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return (width, height, pixels)
}

func image(from pixels: [UInt8], width: Int, height: Int) -> NSImage? {
    var pixels = pixels
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let cgImage = context.makeImage() else {
        return nil
    }
    return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
}

func pngData(from image: NSImage) -> Data? {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff)
    else {
        return nil
    }
    return bitmap.representation(using: .png, properties: [:])
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let data = pngData(from: image) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url, options: .atomic)
}

func sideBySide(_ images: [NSImage], gutter: Int = 8, background: NSColor = .black) -> NSImage? {
    let widths = images.map { Int($0.size.width) }
    let heights = images.map { Int($0.size.height) }
    let width = widths.reduce(0, +) + gutter * max(images.count - 1, 0)
    let height = heights.max() ?? 0
    guard width > 0, height > 0 else { return nil }
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    background.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
    var x = 0
    for (index, panel) in images.enumerated() {
        let panelWidth = Int(panel.size.width)
        let panelHeight = Int(panel.size.height)
        let y = (height - panelHeight) / 2
        panel.draw(
            in: NSRect(x: x, y: y, width: panelWidth, height: panelHeight),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        x += panelWidth
        if index < images.count - 1 {
            x += gutter
        }
    }
    image.unlockFocus()
    return image
}

struct Row {
    var name: String
    var status: String
    var changedPixels: Int
    var percent: Double
}

let arguments = parseArguments()
try FileManager.default.createDirectory(at: arguments.output, withIntermediateDirectories: true)

let previousPNGs = pngs(in: arguments.previous)
let currentPNGs = pngs(in: arguments.current)
var rows: [Row] = []

for name in currentPNGs.keys.sorted() {
    guard let currentURL = currentPNGs[name] else { continue }
    guard let previousURL = previousPNGs[name] else {
        rows.append(Row(name: name, status: "new", changedPixels: 0, percent: 0))
        continue
    }
    if FileManager.default.contentsEqual(atPath: previousURL.path, andPath: currentURL.path) {
        rows.append(Row(name: name, status: "same", changedPixels: 0, percent: 0))
        continue
    }
    guard let currentRaster = rasterize(currentURL) else {
        rows.append(Row(name: name, status: "error", changedPixels: 0, percent: 0))
        continue
    }
    guard let previousRaster = rasterize(
        previousURL,
        width: currentRaster.width,
        height: currentRaster.height
    ) else {
        rows.append(Row(name: name, status: "error", changedPixels: 0, percent: 0))
        continue
    }
    var diffPixels = currentRaster.pixels
    var changed = 0
    let count = min(currentRaster.pixels.count, previousRaster.pixels.count)
    var index = 0
    while index < count {
        let cr = currentRaster.pixels[index]
        let cg = currentRaster.pixels[index + 1]
        let cb = currentRaster.pixels[index + 2]
        let ca = currentRaster.pixels[index + 3]
        let pr = previousRaster.pixels[index]
        let pg = previousRaster.pixels[index + 1]
        let pb = previousRaster.pixels[index + 2]
        let pa = previousRaster.pixels[index + 3]
        if cr != pr || cg != pg || cb != pb || ca != pa {
            changed += 1
            diffPixels[index] = 255
            diffPixels[index + 1] = 0
            diffPixels[index + 2] = 180
            diffPixels[index + 3] = 255
        }
        index += 4
    }
    let total = currentRaster.width * currentRaster.height
    let percent = total == 0 ? 0 : (Double(changed) / Double(total)) * 100
    let relative = (name as NSString).deletingPathExtension
    let folder = (relative as NSString).deletingLastPathComponent
    let stem = (relative as NSString).lastPathComponent
    let destDir = folder.isEmpty ? arguments.output : arguments.output.appending(path: folder)
    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
    if let previousImage = image(
        from: previousRaster.pixels,
        width: previousRaster.width,
        height: previousRaster.height
    ),
        let currentImage = image(
            from: currentRaster.pixels,
            width: currentRaster.width,
            height: currentRaster.height
        ),
        let diffImage = image(
            from: diffPixels,
            width: currentRaster.width,
            height: currentRaster.height
        )
    {
        try writePNG(diffImage, to: destDir.appending(path: "\(stem)-diff.png"))
        if let compare = sideBySide([previousImage, currentImage, diffImage]) {
            try writePNG(compare, to: destDir.appending(path: "\(stem)-compare.png"))
        }
    }
    rows.append(Row(name: name, status: "changed", changedPixels: changed, percent: percent))
}

for name in previousPNGs.keys.sorted() where currentPNGs[name] == nil {
    rows.append(Row(name: name, status: "removed", changedPixels: 0, percent: 0))
}

var summary = ""
func line(_ text: String) {
    summary += text + "\n"
    print(text)
}

line("compare-previews: \(rows.count) screens")
for row in rows {
    switch row.status {
    case "same":
        line("  same     \(row.name)")
    case "new":
        line("  new      \(row.name)")
    case "removed":
        line("  removed  \(row.name)")
    case "changed":
        line(String(format: "  changed  %@  %d px  %.2f%%", row.name, row.changedPixels, row.percent))
    default:
        line("  \(row.status)  \(row.name)")
    }
}
let changed = rows.filter { $0.status == "changed" }.count
let newCount = rows.filter { $0.status == "new" }.count
let removed = rows.filter { $0.status == "removed" }.count
let same = rows.filter { $0.status == "same" }.count
line("changed=\(changed) new=\(newCount) removed=\(removed) same=\(same)")
try summary.write(
    to: arguments.output.appending(path: "summary.txt"),
    atomically: true,
    encoding: .utf8
)
