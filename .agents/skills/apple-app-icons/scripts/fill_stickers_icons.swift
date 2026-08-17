// Fills the iMessage App Icon.stickersiconset with opaque PNGs derived from the
// square master: aspect-fit centered on a black canvas (matches the art's bg).
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let master = CommandLine.arguments[1]
let outDir = CommandLine.arguments[2]

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: master) as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("cannot read master") }

// Pad with the master's top-left pixel color so letterboxing blends into the art's bg.
let cornerColor: CGColor = {
    guard let ctx1 = CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return CGColor(red: 0, green: 0, blue: 0, alpha: 1) }
    // Drawing the full image into 1x1 with the top-left pixel: crop 1x1 from origin instead.
    guard let corner = img.cropping(to: CGRect(x: 0, y: 0, width: 1, height: 1)) else {
        return CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    }
    ctx1.draw(corner, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    guard let px = ctx1.data?.assumingMemoryBound(to: UInt8.self) else {
        return CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    }
    return CGColor(
        red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1
    )
}()

// (filename, pixelW, pixelH, contents entry fields)
let slots: [(String, Int, Int, String)] = [
    ("iphone-29@2x.png", 58, 58, #"{"idiom":"iphone","scale":"2x","size":"29x29","filename":"iphone-29@2x.png"}"#),
    ("iphone-29@3x.png", 87, 87, #"{"idiom":"iphone","scale":"3x","size":"29x29","filename":"iphone-29@3x.png"}"#),
    ("iphone-60x45@2x.png", 120, 90, #"{"idiom":"iphone","scale":"2x","size":"60x45","filename":"iphone-60x45@2x.png"}"#),
    ("iphone-60x45@3x.png", 180, 135, #"{"idiom":"iphone","scale":"3x","size":"60x45","filename":"iphone-60x45@3x.png"}"#),
    ("ipad-29@2x.png", 58, 58, #"{"idiom":"ipad","scale":"2x","size":"29x29","filename":"ipad-29@2x.png"}"#),
    ("ipad-67x50@2x.png", 134, 100, #"{"idiom":"ipad","scale":"2x","size":"67x50","filename":"ipad-67x50@2x.png"}"#),
    ("ipad-74x55@2x.png", 148, 110, #"{"idiom":"ipad","scale":"2x","size":"74x55","filename":"ipad-74x55@2x.png"}"#),
    ("marketing-1024.png", 1024, 1024, #"{"idiom":"ios-marketing","scale":"1x","size":"1024x1024","filename":"marketing-1024.png"}"#),
    ("universal-27x20@2x.png", 54, 40, #"{"idiom":"universal","platform":"ios","scale":"2x","size":"27x20","filename":"universal-27x20@2x.png"}"#),
    ("universal-27x20@3x.png", 81, 60, #"{"idiom":"universal","platform":"ios","scale":"3x","size":"27x20","filename":"universal-27x20@3x.png"}"#),
    ("universal-32x24@2x.png", 64, 48, #"{"idiom":"universal","platform":"ios","scale":"2x","size":"32x24","filename":"universal-32x24@2x.png"}"#),
    ("universal-32x24@3x.png", 96, 72, #"{"idiom":"universal","platform":"ios","scale":"3x","size":"32x24","filename":"universal-32x24@3x.png"}"#),
    ("marketing-1024x768.png", 1024, 768, #"{"idiom":"ios-marketing","platform":"ios","scale":"1x","size":"1024x768","filename":"marketing-1024x768.png"}"#),
]

for (name, w, h, _) in slots {
    guard let ctx = CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue // opaque — App Store requires no alpha
    ) else { fatalError("ctx \(name)") }
    ctx.setFillColor(cornerColor)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let scale = min(CGFloat(w) / CGFloat(img.width), CGFloat(h) / CGFloat(img.height))
    let dw = CGFloat(img.width) * scale, dh = CGFloat(img.height) * scale
    ctx.interpolationQuality = .high
    ctx.draw(img, in: CGRect(x: (CGFloat(w) - dw) / 2, y: (CGFloat(h) - dh) / 2, width: dw, height: dh))
    guard let out = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(
              URL(fileURLWithPath: "\(outDir)/\(name)") as CFURL, UTType.png.identifier as CFString, 1, nil
          ) else { fatalError("write \(name)") }
    CGImageDestinationAddImage(dest, out, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(name) \(w)x\(h)")
}

let contents = """
{
  "images" : [
\(slots.map { "    " + $0.3 }.joined(separator: ",\n"))
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try! contents.write(toFile: "\(outDir)/Contents.json", atomically: true, encoding: .utf8)
print("wrote Contents.json")
