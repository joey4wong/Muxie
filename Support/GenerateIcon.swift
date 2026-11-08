// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.
// The license/copyright above covers this conversion script, not the supplied image.
// IconSource.png is user-supplied artwork; no image ownership is asserted here.
// Run: swift /path/to/Support/GenerateIcon.swift
// Requires macOS with Swift CLI tools. Reads IconSource.png next to this script;
// writes only AppIcon.png and AppIcon.icns there. No drawing or image generation.
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct IconError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
let directory = URL(fileURLWithPath: #filePath).standardizedFileURL.deletingLastPathComponent()
let sourceURL = directory.appendingPathComponent("IconSource.png")
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
func bitmap(_ size: Int) throws -> CGContext {
    guard let context = CGContext(data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: size * 4, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw IconError("Cannot create \(size)-pixel bitmap")
    }
    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    return context
}
func pngData(_ image: CGImage) throws -> Data {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data,
        UTType.png.identifier as CFString, 1, nil) else {
        throw IconError("Cannot create PNG destination")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw IconError("PNG encoding failed") }
    return data as Data
}
func decodedPNG(_ data: Data, expectedSize: Int) throws -> CGImage {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0,
            [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
        image.width == expectedSize, image.height == expectedSize else {
        throw IconError("PNG cannot decode at expected size \(expectedSize)")
    }
    return image
}
func bigEndianLength(_ length: Int) -> Data {
    var value = UInt32(length).bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}

guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0,
        [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
    throw IconError("Cannot decode IconSource.png")
}
let canvas = try bitmap(1024)
// A white rounded-square macOS tile, 64 px transparent margin on every side.
// Fit the FULL source inside the 896 px tile, preserving its aspect ratio.
// Its existing white border supplies all internal spacing: no extra inset,
// no crop, recoloring, new decoration, or reconstruction of the glass knot.
let tile = CGRect(x: 64, y: 64, width: 896, height: 896)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 200, cornerHeight: 200, transform: nil)
let scale = min(tile.width / CGFloat(artwork.width), tile.height / CGFloat(artwork.height))
let artworkRect = CGRect(
    x: tile.midX - CGFloat(artwork.width) * scale / 2,
    y: tile.midY - CGFloat(artwork.height) * scale / 2,
    width: CGFloat(artwork.width) * scale, height: CGFloat(artwork.height) * scale)
canvas.saveGState()
canvas.addPath(tilePath)
canvas.clip()
canvas.setFillColor(CGColor(colorSpace: colorSpace, components: [1, 1, 1, 1])!)
canvas.fill(tile)
canvas.draw(artwork, in: artworkRect)
canvas.restoreGState()
guard let icon = canvas.makeImage() else { throw IconError("Cannot render icon") }
let masterPNG = try pngData(icon)
_ = try decodedPNG(masterPNG, expectedSize: 1024)

// Standard macOS 1x/2x representations. Encode directly in memory so the
// converter creates no iconset folders or intermediate files in Support.
let representations: [(String, Int, String)] = [
    ("icp4", 16, "16x16"), ("ic11", 32, "16x16@2x"),
    ("icp5", 32, "32x32"), ("ic12", 64, "32x32@2x"),
    ("ic07", 128, "128x128"), ("ic13", 256, "128x128@2x"),
    ("ic08", 256, "256x256"), ("ic14", 512, "256x256@2x"),
    ("ic09", 512, "512x512"), ("ic10", 1024, "512x512@2x")
]
var chunks = Data()
for (type, size, label) in representations {
    let png: Data
    if size == 1024 {
        png = masterPNG
    } else {
        let reduced = try bitmap(size)
        reduced.draw(icon, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let image = reduced.makeImage() else { throw IconError("Cannot resize \(label)") }
        png = try pngData(image)
    }
    _ = try decodedPNG(png, expectedSize: size)
    chunks.append(Data(type.utf8))
    chunks.append(bigEndianLength(png.count + 8))
    chunks.append(png)
    print("Verified \(type): \(label) (\(size) x \(size))")
}
var family = Data("icns".utf8)
family.append(bigEndianLength(chunks.count + 8))
family.append(chunks)
guard let decodedFamily = CGImageSourceCreateWithData(family as CFData, nil),
      let appKitImage = NSImage(data: family), appKitImage.isValid else {
    throw IconError("ICNS family cannot decode")
}
let decodedCount = CGImageSourceGetCount(decodedFamily)
for index in 0..<decodedCount {
    guard CGImageSourceCreateImageAtIndex(decodedFamily, index,
        [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) != nil else {
        throw IconError("ICNS representation \(index) cannot decode")
    }
}
try masterPNG.write(to: directory.appendingPathComponent("AppIcon.png"), options: .atomic)
try family.write(to: directory.appendingPathComponent("AppIcon.icns"), options: .atomic)
print("Source: \(artwork.width) x \(artwork.height); full-image fit, scale \(scale)")
print("Created AppIcon.png (1024 x 1024) and AppIcon.icns (10 verified PNG chunks; \(decodedCount) ImageIO representations)")
