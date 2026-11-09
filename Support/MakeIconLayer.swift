// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.
//
// Places Knot.png, centred and scaled, on a transparent 1024 x 1024 canvas: the foreground layer of
// AppIcon.icon. Pure resampling; the artwork is not redrawn.
// Usage: swift MakeIconLayer.swift Knot.png AppIcon.icon/Assets/Knot.png [widthFraction]

import AppKit

let args = CommandLine.arguments
guard args.count >= 3, let knot = NSImage(contentsOf: URL(fileURLWithPath: args[1])) else { print("usage: MakeIconLayer.swift in.png out.png [fraction]"); exit(1) }
let fraction = args.count > 3 ? Double(args[3]) ?? 0.76 : 0.76
let canvas = 1024.0
let width = canvas * fraction, height = width * knot.size.height / knot.size.width
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB, bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
knot.draw(in: NSRect(x: (canvas - width) / 2, y: (canvas - height) / 2, width: width, height: height), from: .zero, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2]): knot \(Int(width)) x \(Int(height)) on 1024 canvas")
