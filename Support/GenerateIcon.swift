// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

// Muxie icon artwork. Run from this directory with:
// TMPDIR="$PWD/.tmp" swift -module-cache-path "$PWD/.module-cache" GenerateIcon.swift
// All generated files remain alongside this script. Requires macOS / Xcode CLI tools.
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: #filePath).standardizedFileURL.deletingLastPathComponent()
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}
let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                    bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setAllowsAntialiasing(true)
ctx.setShouldAntialias(true)
func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}
func fillGradient(_ path: CGPath, _ colors: [CGColor], _ start: CGPoint, _ end: CGPoint) {
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}
func stroke(_ path: CGPath, _ c: CGColor, _ width: CGFloat) {
    ctx.addPath(path); ctx.setStrokeColor(c); ctx.setLineWidth(width); ctx.strokePath()
}

// Native-style rounded tile, with transparent breathing room for the macOS Dock.
let tile = rounded(CGRect(x: 80, y: 80, width: 864, height: 864), 190)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 24, color: color(0.015, 0.02, 0.08, 0.32))
ctx.addPath(tile); ctx.setFillColor(color(0.065, 0.065, 0.20)); ctx.fillPath()
ctx.restoreGState()
fillGradient(tile, [color(0.22, 0.25, 0.54), color(0.105, 0.105, 0.32), color(0.035, 0.045, 0.16)],
             CGPoint(x: 130, y: 960), CGPoint(x: 880, y: 80))
ctx.saveGState()
ctx.addPath(tile); ctx.clip()
let bloom = CGGradient(colorsSpace: space,
    colors: [color(0.37, 0.43, 0.99, 0.29), color(0.13, 0.20, 0.72, 0)] as CFArray,
    locations: [0, 1])!
ctx.drawRadialGradient(bloom, startCenter: CGPoint(x: 230, y: 850), startRadius: 0,
                       endCenter: CGPoint(x: 230, y: 850), endRadius: 710, options: [])
ctx.restoreGState()
stroke(rounded(CGRect(x: 81.5, y: 81.5, width: 861, height: 861), 188.5), color(0.72, 0.78, 1, 0.22), 3)

// Three luminous glass tracks, deliberately unequal in length.
func glassTrack(y: CGFloat, width: CGFloat, top: CGColor, bottom: CGColor) {
    let r = CGRect(x: 236, y: y, width: width, height: 66)
    let p = rounded(r, 33)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -9), blur: 17, color: color(0.015, 0.03, 0.12, 0.48))
    ctx.addPath(p); ctx.setFillColor(bottom); ctx.fillPath()
    ctx.restoreGState()
    fillGradient(p, [top, bottom], CGPoint(x: 236, y: y + 66), CGPoint(x: 260, y: y))
    stroke(rounded(r.insetBy(dx: 1, dy: 1), 32), color(0.91, 0.98, 1, 0.6), 2)
    let shine = CGMutablePath()
    shine.move(to: CGPoint(x: 269, y: y + 55)); shine.addLine(to: CGPoint(x: 236 + width - 33, y: y + 55))
    ctx.saveGState(); ctx.setLineCap(.round); stroke(shine, color(1, 1, 1, 0.55), 3); ctx.restoreGState()
}
glassTrack(y: 660, width: 552, top: color(0.78, 0.98, 1), bottom: color(0.27, 0.69, 0.94))
glassTrack(y: 482, width: 424, top: color(0.87, 0.91, 1), bottom: color(0.48, 0.60, 0.93))
glassTrack(y: 304, width: 296, top: color(0.88, 0.84, 1), bottom: color(0.62, 0.50, 0.88))

// A compact glass play control balances the staggered tracks, without letters.
let playPlate = rounded(CGRect(x: 638, y: 264, width: 166, height: 166), 55)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 18, color: color(0.01, 0.02, 0.10, 0.4))
ctx.addPath(playPlate); ctx.setFillColor(color(0.24, 0.34, 0.67)); ctx.fillPath()
ctx.restoreGState()
fillGradient(playPlate, [color(0.53, 0.64, 0.91, 0.72), color(0.23, 0.32, 0.62, 0.7)],
             CGPoint(x: 638, y: 430), CGPoint(x: 804, y: 264))
stroke(rounded(CGRect(x: 639.5, y: 265.5, width: 163, height: 163), 53.5), color(0.87, 0.94, 1, 0.47), 3)
let play = CGMutablePath()
play.move(to: CGPoint(x: 701, y: 305))
play.addQuadCurve(to: CGPoint(x: 690, y: 312), control: CGPoint(x: 690, y: 298))
play.addLine(to: CGPoint(x: 690, y: 382))
play.addQuadCurve(to: CGPoint(x: 701, y: 389), control: CGPoint(x: 690, y: 396))
play.addLine(to: CGPoint(x: 757, y: 354))
play.addQuadCurve(to: CGPoint(x: 757, y: 340), control: CGPoint(x: 769, y: 347))
play.closeSubpath()
fillGradient(play, [color(1, 1, 1), color(0.77, 0.94, 1)], CGPoint(x: 700, y: 390), CGPoint(x: 740, y: 300))

let image = ctx.makeImage()!
func writePNG(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "MuxieIcon", code: 1)
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "MuxieIcon", code: 2) }
}
try writePNG(image, to: output.appendingPathComponent("AppIcon.png"))
let iconset = output.appendingPathComponent(".AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = base * scale
        let reduced = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        reduced.interpolationQuality = .high
        reduced.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try writePNG(reduced.makeImage()!, to: iconset.appendingPathComponent(name))
    }
}
// Write the documented ICNS family container directly, with PNG-backed representations.
func bigEndianLength(_ length: Int) -> Data {
    var value = UInt32(length).bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}
let representations: [(String, String)] = [
    ("icp4", "icon_16x16.png"), ("ic11", "icon_16x16@2x.png"),
    ("icp5", "icon_32x32.png"), ("ic12", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"), ("ic13", "icon_128x128@2x.png"),
    ("ic08", "icon_256x256.png"), ("ic14", "icon_256x256@2x.png"),
    ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png")
]
var chunks = Data()
for (type, file) in representations {
    let png = try Data(contentsOf: iconset.appendingPathComponent(file))
    chunks.append(Data(type.utf8)); chunks.append(bigEndianLength(png.count + 8)); chunks.append(png)
}
var family = Data("icns".utf8)
family.append(bigEndianLength(chunks.count + 8)); family.append(chunks)
let icnsURL = output.appendingPathComponent("AppIcon.icns")
try family.write(to: icnsURL)
guard let decoded = CGImageSourceCreateWithURL(icnsURL as CFURL, nil), CGImageSourceGetCount(decoded) >= 7,
      let decodedImage = NSImage(contentsOf: icnsURL), decodedImage.isValid else {
    throw NSError(domain: "MuxieIconVerification", code: 1)
}
print("Verified ICNS: \(CGImageSourceGetCount(decoded)) decoded representations")
try FileManager.default.removeItem(at: iconset)
print("Created AppIcon.png (1024 × 1024) and AppIcon.icns")
