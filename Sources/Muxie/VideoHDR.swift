// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import Foundation

enum HDRBadge: String, Sendable, Codable, Equatable {
    case hdr10 = "HDR10"
    case hlg = "HLG"
    case hdr10Plus = "HDR10+"
    case dolbyVision = "DV"
}

enum VideoHDR {
  static func badge(transfer: Int?, codecPrivateHex: String?) -> HDRBadge? {
        if dolbyVisionHeuristic(codecPrivateHex: codecPrivateHex) { return .dolbyVision }
        guard let transfer else { return nil }
        if transfer == 16 { return hdr10PlusHeuristic(codecPrivateHex: codecPrivateHex) ? .hdr10Plus : .hdr10 }
        if transfer == 18 { return .hlg }
        return nil
    }

    /// mkvmerge sometimes carries Dolby Vision side data in codec private hex; HandBrake scan refines this when needed.
    private static func dolbyVisionHeuristic(codecPrivateHex: String?) -> Bool {
        guard let codecPrivateHex else { return false }
        let upper = codecPrivateHex.uppercased()
        return upper.contains("64767663") || upper.contains("DOVI")
    }

    private static func hdr10PlusHeuristic(codecPrivateHex: String?) -> Bool {
        guard let codecPrivateHex else { return false }
        return codecPrivateHex.count > 120
    }

    static func compressExportWarning(badges: [HDRBadge], encoder: CompressEncoder) -> String? {
        guard !badges.isEmpty else { return nil }
        var lines: [String] = []
        if badges.contains(.dolbyVision) {
            lines.append("This video includes Dolby Vision. Compress keeps HDR10 picture data only; Dolby Vision dynamic metadata is not preserved.")
        }
        if badges.contains(.hdr10Plus) {
            lines.append("This video may include HDR10+ dynamic metadata. Only static HDR10 is verified after export.")
        }
        if badges.contains(.hdr10) || badges.contains(.hlg) {
            lines.append("HDR color is preserved when the encoder supports it.")
        }
        if encoder == .hardware, badges.contains(.dolbyVision) {
            lines.append("Apple hardware encoding cannot pass through Dolby Vision profiles.")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n\n")
    }
}
