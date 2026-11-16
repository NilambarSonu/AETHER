// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AppKit
import CoreGraphics
import Foundation

// Resolves repo root relative to this script
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let rootURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()

let assetsDir = rootURL.appendingPathComponent("Droplet/Assets")
let iconDir = rootURL.appendingPathComponent("Droplet/.droppykit/AETHER.icon")
let iconAssetsDir = iconDir.appendingPathComponent("Assets")

let cardURL = assetsDir.appendingPathComponent("aether-card.png")
let targetAetherPNG = assetsDir.appendingPathComponent("aether.png")
let targetMarkPNG = iconAssetsDir.appendingPathComponent("mark.png")
let targetIconJSON = iconDir.appendingPathComponent("icon.json")
let targetICNS = rootURL.appendingPathComponent("Droplet/.droppykit/AETHER.icns")

guard FileManager.default.fileExists(atPath: cardURL.path) else {
    print("ERROR: Missing raw card asset at \(cardURL.path)")
    exit(1)
}

print("==> Rendering 1024x1024 Master Liquid Glass Squircle Icon for AETHER...")

let size: CGFloat = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size),
    pixelsHigh: Int(size),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// 1. Clear background to 100% transparency
ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))

// 2. Build full-bleed Apple standard continuous squircle path
let rect = CGRect(x: 0, y: 0, width: size, height: size)
let radius: CGFloat = size * 0.2237 // ~229.07pt continuous corner radius
let squirclePath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()
ctx.addPath(squirclePath)
ctx.clip()

// 3. Draw gradient background matching Settings header squircle:
// Top: display-p3 0.17255, 0.14510, 0.22745 (~ sRGB 0.184, 0.141, 0.243)
// Bottom: display-p3 0.08627, 0.09020, 0.13333 (~ sRGB 0.086, 0.090, 0.137)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let topComponents: [CGFloat] = [0.184, 0.141, 0.243, 1.0]
let bottomComponents: [CGFloat] = [0.086, 0.090, 0.137, 1.0]
let colors = [
    CGColor(colorSpace: colorSpace, components: topComponents)!,
    CGColor(colorSpace: colorSpace, components: bottomComponents)!
] as CFArray
let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: size/2, y: size), end: CGPoint(x: size/2, y: 0), options: [])

// 4. Subtle inner stroke / glass specular edge
let strokeRect = rect.insetBy(dx: 1.0, dy: 1.0)
let strokePath = CGPath(roundedRect: strokeRect, cornerWidth: radius - 1.0, cornerHeight: radius - 1.0, transform: nil)
let strokeColors = [
    CGColor(colorSpace: colorSpace, components: [1.0, 1.0, 1.0, 0.24])!,
    CGColor(colorSpace: colorSpace, components: [1.0, 1.0, 1.0, 0.06])!
] as CFArray
let strokeGrad = CGGradient(colorsSpace: colorSpace, colors: strokeColors, locations: [0.0, 1.0])!
ctx.saveGState()
ctx.addPath(strokePath)
ctx.setLineWidth(2.0)
ctx.replacePathWithStrokedPath()
ctx.clip()
ctx.drawLinearGradient(strokeGrad, start: CGPoint(x: size/2, y: size), end: CGPoint(x: size/2, y: 0), options: [])
ctx.restoreGState()

// 5. Draw 3D wallet card centered at 84% scale
if let walletImg = NSImage(contentsOf: cardURL),
   let cgWallet = walletImg.cgImage(forProposedRect: nil, context: nil, hints: nil) {
    let walletScale: CGFloat = 0.84
    let walletSide = size * walletScale
    let walletRect = CGRect(
        x: (size - walletSide) / 2,
        y: (size - walletSide) / 2,
        width: walletSide,
        height: walletSide
    )
    ctx.draw(cgWallet, in: walletRect)
}

ctx.restoreGState()
NSGraphicsContext.restoreGraphicsState()

guard let masterPNG = rep.representation(using: .png, properties: [:]) else {
    print("ERROR: Failed to encode master PNG")
    exit(1)
}

// Write master squircle to Droplet/Assets/aether.png
try! masterPNG.write(to: targetAetherPNG)
print("  ✓ Wrote 1024x1024 squircle to \(targetAetherPNG.path)")

// Prepare .droppykit/AETHER.icon directory
try? FileManager.default.removeItem(at: iconDir)
try! FileManager.default.createDirectory(at: iconAssetsDir, withIntermediateDirectories: true)

// Downsample to 512x512 for mark.png
let masterImg = NSImage(data: masterPNG)!
let rep512 = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 512,
    pixelsHigh: 512,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep512)
NSGraphicsContext.current!.imageInterpolation = .high
masterImg.draw(in: NSRect(x: 0, y: 0, width: 512, height: 512))
NSGraphicsContext.restoreGraphicsState()

let png512 = rep512.representation(using: .png, properties: [:])!
try! png512.write(to: targetMarkPNG)
print("  ✓ Wrote 512x512 squircle mark to \(targetMarkPNG.path)")

// Write icon.json with fill-specializations: [] so DropletIconRenderer leaves outer canvas transparent
let iconJSON = """
{
  "fill-specializations" : [ ],
  "groups" : [
    {
      "layers" : [
        {
          "hidden" : false,
          "image-name" : "mark.png",
          "name" : "placeholder",
          "position" : {
            "scale" : 1.0,
            "translation-in-points" : [ 0, 0 ]
          }
        }
      ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.45 },
      "translucency" : { "enabled" : true, "value" : 0.45 }
    }
  ],
  "supported-platforms" : {
    "circles" : [ "watchOS" ],
    "squares" : "shared"
  }
}
"""
try! iconJSON.write(to: targetIconJSON, atomically: true, encoding: .utf8)
print("  ✓ Wrote icon.json to \(targetIconJSON.path)")

// Generate official macOS AETHER.icns via iconutil
let iconsetDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AETHER.iconset")
try? FileManager.default.removeItem(at: iconsetDir)
try! FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let iconSizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (px, name) in iconSizes {
    let outURL = iconsetDir.appendingPathComponent(name)
    let sRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sRep)
    NSGraphicsContext.current!.imageInterpolation = .high
    masterImg.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    let sPNG = sRep.representation(using: .png, properties: [:])!
    try! sPNG.write(to: outURL)
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetDir.path, "-o", targetICNS.path]
try! iconutil.run()
iconutil.waitUntilExit()

if iconutil.terminationStatus == 0 {
    print("  ✓ Compiled official AETHER.icns to \(targetICNS.path)")
} else {
    print("  WARNING: iconutil exited with code \(iconutil.terminationStatus)")
}

try? FileManager.default.removeItem(at: iconsetDir)
print("==> AETHER squircle icon preparation complete.")
