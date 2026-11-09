// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.
//
// Cuts the knot out of IconSource.png (user-supplied artwork on a white background) and writes
// Knot.png: RGBA, cropped to the artwork, background and the three openings transparent.
// Requires macOS 14+ with Vision subject lifting, which needs the Neural Engine (it does not run in
// a restricted sandbox). The artwork itself is not redrawn: only its alpha channel is derived.
//
// Usage: swift CutoutKnot.swift IconSource.png Knot.png [--debug]

import AppKit
import CoreImage
import Vision

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: CutoutKnot.swift in.png out.png [--debug]"); exit(1) }
let debug = args.contains("--debug")
let inURL = URL(fileURLWithPath: args[1]), outURL = URL(fileURLWithPath: args[2])

// 1. Subject mask from Vision.
let handler = VNImageRequestHandler(url: inURL, options: [:])
let request = VNGenerateForegroundInstanceMaskRequest()
try handler.perform([request])
guard let observation = request.results?.first else { print("no subject found"); exit(2) }
let maskBuffer = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
let source = CIImage(contentsOf: inURL)!
let ctx = CIContext()
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let width = Int(source.extent.width), height = Int(source.extent.height)

// RGBA8 straight alpha for the source, and an 8-bit mask.
var rgba = [UInt8](repeating: 0, count: width * height * 4)
ctx.render(source, toBitmap: &rgba, rowBytes: width * 4, bounds: source.extent, format: .RGBA8, colorSpace: space)
var alpha = [UInt8](repeating: 0, count: width * height)
ctx.render(CIImage(cvPixelBuffer: maskBuffer), toBitmap: &alpha, rowBytes: width, bounds: source.extent, format: .R8, colorSpace: nil)
// CoreImage bitmaps are bottom-up relative to the buffer layout used above for both, so they agree.

@inline(__always) func idx(_ x: Int, _ y: Int) -> Int { y * width + x }

// 2. Openings: neutral near-white regions that the subject mask kept (e.g. the small gap at the top).
//    Glass highlights are tinted, so they do not match; only large neutral areas are removed.
func isNeutralWhite(_ i: Int) -> Bool {
    let r = Int(rgba[i * 4]), g = Int(rgba[i * 4 + 1]), b = Int(rgba[i * 4 + 2])
    return min(r, g, b) >= 246 && max(r, g, b) - min(r, g, b) <= 5
}
// Background colour = per-channel median of the image border (the artwork sits on a flat near-white).
var border: [[Int]] = [[], [], []]
for x in 0..<width { for y in [0, height - 1] { for c in 0..<3 { border[c].append(Int(rgba[idx(x, y) * 4 + c])) } } }
for y in 0..<height { for x in [0, width - 1] { for c in 0..<3 { border[c].append(Int(rgba[idx(x, y) * 4 + c])) } } }
let background = border.map { $0.sorted()[$0.count / 2] }
func isBackgroundColour(_ i: Int) -> Bool {
    (0..<3).allSatisfy { abs(Int(rgba[i * 4 + $0]) - background[$0]) <= 1 }
}
print("background colour: \(background)")
var visited = [Bool](repeating: false, count: width * height)
var removed = 0
for start in 0..<(width * height) where alpha[start] > 8 && isNeutralWhite(start) && !visited[start] {
    var stack = [start], component: [Int] = []
    visited[start] = true
    while let p = stack.popLast() {
        component.append(p)
        let x = p % width, y = p / width
        for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
            let nx = x + dx, ny = y + dy
            guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
            let q = idx(nx, ny)
            if !visited[q], alpha[q] > 8, isNeutralWhite(q) { visited[q] = true; stack.append(q) }
        } }
    }
    // A genuine opening shows the flat background colour; a highlight is a smooth gradient. Measured on this
    // artwork: the opening scores 0.86, the brightest highlights at most 0.73, so 0.8 separates them.
    let flat = Double(component.filter(isBackgroundColour).count) / Double(component.count)
    if debug && component.count >= 200 { print("neutral-white component: \(component.count) px at \(component[0] % width),\(component[0] / width), flat background fraction \(String(format: "%.2f", flat))") }
    if component.count >= 1500 && flat >= 0.8 { for p in component { alpha[p] = 0 }; removed += component.count }
}
print("openings made transparent: \(removed) px")

// 3. Clean the edge. Shrink the mask by one pixel, soften it, and replace edge colours with the nearest
//    interior colour so none of the white background survives as a halo.
func minFilter(_ a: [UInt8]) -> [UInt8] {
    var o = a
    for y in 0..<height { for x in 0..<width {
        var m = a[idx(x, y)]
        for dy in -1...1 { for dx in -1...1 {
            let nx = min(max(x + dx, 0), width - 1), ny = min(max(y + dy, 0), height - 1)
            m = min(m, a[idx(nx, ny)])
        } }
        o[idx(x, y)] = m
    } }
    return o
}
func boxBlur(_ a: [UInt8]) -> [UInt8] {
    var o = a
    for y in 0..<height { for x in 0..<width {
        var s = 0
        for dy in -1...1 { for dx in -1...1 {
            let nx = min(max(x + dx, 0), width - 1), ny = min(max(y + dy, 0), height - 1)
            s += Int(a[idx(nx, ny)])
        } }
        o[idx(x, y)] = UInt8(s / 9)
    } }
    return o
}
let solid = (0..<2).reduce(alpha.map { $0 > 127 ? UInt8(255) : UInt8(0) }) { acc, _ in minFilter(acc) }  // 2 px inside
let softAlpha = boxBlur(minFilter(alpha.map { $0 > 127 ? UInt8(255) : UInt8(0) }))

// Nearest interior colour by breadth-first growth from the solid area.
var colour = rgba
var done = [Bool](repeating: false, count: width * height)
var frontier: [Int] = []
for i in 0..<(width * height) where solid[i] == 255 { done[i] = true; frontier.append(i) }
for _ in 0..<5 {
    var next: [Int] = []
    for p in frontier {
        let x = p % width, y = p / width
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let nx = x + dx, ny = y + dy
            guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
            let q = idx(nx, ny)
            if !done[q] { done[q] = true; for c in 0..<3 { colour[q * 4 + c] = colour[p * 4 + c] }; next.append(q) }
        }
    }
    frontier = next
}

// 4. Assemble, crop to the artwork with a small margin, and write.
var minX = width, minY = height, maxX = 0, maxY = 0
for y in 0..<height { for x in 0..<width where softAlpha[idx(x, y)] > 0 {
    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
} }
let margin = 12
minX = max(0, minX - margin); minY = max(0, minY - margin); maxX = min(width - 1, maxX + margin); maxY = min(height - 1, maxY + margin)
let cw = maxX - minX + 1, ch = maxY - minY + 1
var out = [UInt8](repeating: 0, count: cw * ch * 4)
for y in 0..<ch { for x in 0..<cw {
    let s = idx(minX + x, minY + y), d = (y * cw + x) * 4
    let a = Int(softAlpha[s])
    // Premultiply for the bitmap rep.
    for c in 0..<3 { out[d + c] = UInt8(Int(colour[s * 4 + c]) * a / 255) }
    out[d + 3] = UInt8(a)
} }
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cw, pixelsHigh: ch, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bitmapFormat: [], bytesPerRow: cw * 4, bitsPerPixel: 32)!
// Copy row by row: the bitmap may pad each row, so use its real stride rather than assuming width * 4.
for y in 0..<ch {
    out.withUnsafeBufferPointer { src in
        memcpy(rep.bitmapData! + y * rep.bytesPerRow, src.baseAddress! + y * cw * 4, cw * 4)
    }
}
let png = rep.representation(using: .png, properties: [:])!
try png.write(to: outURL)
print("wrote \(outURL.lastPathComponent): \(cw)x\(ch)")
