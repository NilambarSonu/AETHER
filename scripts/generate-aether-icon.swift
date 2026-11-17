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

guard let walletImg = NSImage(contentsOf: cardURL),
      let cgWallet = walletImg.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("ERROR: Failed to load CGImage from \(cardURL.path)")
    exit(1)
}

print("==> 1. Rendering 1024x1024 Master Liquid Glass Squircle Icon (aether.png)...")

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
// Top: display-p3 0.18431, 0.14118, 0.24314
// Bottom: display-p3 0.08627, 0.09020, 0.13725
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
let walletScale: CGFloat = 0.84
let walletSide = size * walletScale
let walletRect = CGRect(
    x: (size - walletSide) / 2,
    y: (size - walletSide) / 2,
    width: walletSide,
    height: walletSide
)
ctx.draw(cgWallet, in: walletRect)

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

print("==> 2. Rendering 512x512 Glyph Mark for AETHER.icon/Assets/mark.png...")

// Render ONLY the 3D wallet glyph mark on transparent canvas for AETHER.icon
// (DropletIconRenderer will composite the fill-specializations gradient behind it!)
let markSize: CGFloat = 512
let markRep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(markSize),
    pixelsHigh: Int(markSize),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
let markCtx = NSGraphicsContext(bitmapImageRep: markRep)!.cgContext
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: markRep)
NSGraphicsContext.current!.imageInterpolation = .high

markCtx.clear(CGRect(x: 0, y: 0, width: markSize, height: markSize))
let markSide = markSize * 0.86
let markRect = CGRect(
    x: (markSize - markSide) / 2,
    y: (markSize - markSide) / 2,
    width: markSide,
    height: markSide
)
markCtx.draw(cgWallet, in: markRect)
NSGraphicsContext.restoreGraphicsState()

let markPNG = markRep.representation(using: .png, properties: [:])!
try! markPNG.write(to: targetMarkPNG)
print("  ✓ Wrote 512x512 transparent 3D wallet mark to \(targetMarkPNG.path)")

// Write icon.json WITH official fill-specializations gradient and mark layer
let iconJSON = """
{
  "fill-specializations" : [
    {
      "value" : {
        "linear-gradient" : [
          "display-p3:0.18431,0.14118,0.24314,1.00000",
          "display-p3:0.08627,0.09020,0.13725,1.00000"
        ]
      }
    },
    {
      "appearance" : "dark",
      "value" : {
        "linear-gradient" : [
          "display-p3:0.18431,0.14118,0.24314,1.00000",
          "display-p3:0.08627,0.09020,0.13725,1.00000"
        ]
      }
    }
  ],
  "groups" : [
    {
      "layers" : [
        {
          "hidden" : false,
          "image-name" : "mark.png",
          "name" : "placeholder",
          "position" : {
            "scale" : 0.86,
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
print("  ✓ Wrote icon.json with liquid glass fill-specializations to \(targetIconJSON.path)")

print("==> 3. Rendering Apple Standard macOS AppIcon for AETHER.icns...")

// Apple macOS Big Sur+ app icon standard:
// Canvas: 1024x1024
// Squircle: 824x824 inset centered (100pt margins)
// Continuous squircle radius: 824 * 0.2237 = 184.329pt
// Smooth drop shadow: offset (0, -12), blur 24, alpha 0.36
// Outside: 100% transparent.
let icnsMasterRep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 1024,
    pixelsHigh: 1024,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
let icnsCtx = NSGraphicsContext(bitmapImageRep: icnsMasterRep)!.cgContext
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: icnsMasterRep)
NSGraphicsContext.current!.imageInterpolation = .high

icnsCtx.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))

let squircleSide: CGFloat = 824
let squircleOrigin: CGFloat = (1024 - squircleSide) / 2 // 100pt
let squircleRect = CGRect(x: squircleOrigin, y: squircleOrigin, width: squircleSide, height: squircleSide)
let squircleRadius: CGFloat = squircleSide * 0.2237 // ~184.3pt
let icnsPath = CGPath(roundedRect: squircleRect, cornerWidth: squircleRadius, cornerHeight: squircleRadius, transform: nil)

// Draw Apple standard drop shadow
icnsCtx.saveGState()
let shadowColor = CGColor(colorSpace: colorSpace, components: [0.0, 0.0, 0.0, 0.38])!
icnsCtx.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: shadowColor)
icnsCtx.addPath(icnsPath)
icnsCtx.setFillColor(CGColor(colorSpace: colorSpace, components: [0.086, 0.090, 0.137, 1.0])!)
icnsCtx.fillPath()
icnsCtx.restoreGState()

// Clip to squircle for gradient, stroke, and wallet
icnsCtx.saveGState()
icnsCtx.addPath(icnsPath)
icnsCtx.clip()

// Gradient fill
icnsCtx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: squircleOrigin + squircleSide), end: CGPoint(x: 512, y: squircleOrigin), options: [])

// Inner specular rim
let icnsStrokeRect = squircleRect.insetBy(dx: 1.0, dy: 1.0)
let icnsStrokePath = CGPath(roundedRect: icnsStrokeRect, cornerWidth: squircleRadius - 1.0, cornerHeight: squircleRadius - 1.0, transform: nil)
icnsCtx.saveGState()
icnsCtx.addPath(icnsStrokePath)
icnsCtx.setLineWidth(2.0)
icnsCtx.replacePathWithStrokedPath()
icnsCtx.clip()
icnsCtx.drawLinearGradient(strokeGrad, start: CGPoint(x: 512, y: squircleOrigin + squircleSide), end: CGPoint(x: 512, y: squircleOrigin), options: [])
icnsCtx.restoreGState()

// Draw 3D wallet card centered inside squircle at 84% scale
let icnsWalletSide = squircleSide * 0.84
let icnsWalletRect = CGRect(
    x: squircleOrigin + (squircleSide - icnsWalletSide) / 2,
    y: squircleOrigin + (squircleSide - icnsWalletSide) / 2,
    width: icnsWalletSide,
    height: icnsWalletSide
)
icnsCtx.draw(cgWallet, in: icnsWalletRect)

icnsCtx.restoreGState()
NSGraphicsContext.restoreGraphicsState()

let icnsMasterPNG = icnsMasterRep.representation(using: .png, properties: [:])!
let icnsMasterImg = NSImage(data: icnsMasterPNG)!

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
    icnsMasterImg.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
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
    print("  ✓ Compiled official Apple-standard AETHER.icns to \(targetICNS.path)")
} else {
    print("  WARNING: iconutil exited with code \(iconutil.terminationStatus)")
}

try? FileManager.default.removeItem(at: iconsetDir)
print("==> AETHER squircle icon preparation complete.")
