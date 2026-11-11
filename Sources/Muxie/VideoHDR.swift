// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import Foundation

enum HDRBadge: String, Sendable, Codable, Equatable {
    case hdr10 = "HDR10"
    case hlg = "HLG"
    /// Only produced by versions up to 1.14.6 via a codec-private-length heuristic that misfired on
    /// ordinary HDR10 files. No longer assigned at import; kept so persisted queue items still decode.
    case hdr10Plus = "HDR10+"
    case dolbyVision = "DV"
}

enum VideoHDR {
  static func badge(transfer: Int?, codecPrivateHex: String?) -> HDRBadge? {
        // HDR10+ dynamic metadata (ST 2094-40) travels in-band per frame and is invisible to mkvmerge -J,
        // so it cannot be told from plain HDR10 at import; only the transfer characteristics are reliable.
        if dolbyVisionHeuristic(codecPrivateHex: codecPrivateHex) { return .dolbyVision }
        guard let transfer else { return nil }
        if transfer == 16 { return .hdr10 }
        if transfer == 18 { return .hlg }
        return nil
    }

    static func dolbyVisionProfile(codecPrivateHex: String?) -> Int? {
        guard let hex = codecPrivateHex?.lowercased() else { return nil }
        for magic in ["64766343", "64767643"] {
            var from = hex.startIndex
            while let r = hex.range(of: magic, range: from..<hex.endIndex) {
                let start = r.upperBound
                if let end = hex.index(start, offsetBy: 6, limitedBy: hex.endIndex), start != end {
                    let bytes = stride(from: 0, to: 6, by: 2).compactMap { i -> Int? in
                        let a = hex.index(start, offsetBy: i), b = hex.index(a, offsetBy: 2)
                        return Int(hex[a..<b], radix: 16)
                    }
                    if bytes.count == 3, bytes[0] >= 1, bytes[0] <= 2 { return bytes[2] >> 1 }
                }
                from = r.upperBound
            }
        }
        return nil
    }

    private static func dolbyVisionHeuristic(codecPrivateHex: String?) -> Bool {
        guard let hex = codecPrivateHex?.lowercased() else { return false }
        return hex.contains("64766343") || hex.contains("64767643")
    }

    static func compressExportWarning(badges: [HDRBadge], encoder: CompressEncoder, dolbyVisionProfiles: [Int] = []) -> String? {
        guard !badges.isEmpty else { return nil }
        var lines: [String] = []
        if badges.contains(.dolbyVision) {
            if dolbyVisionProfiles.contains(5) {
                lines.append("This video is Dolby Vision Profile 5, which has no HDR10 base layer. Compress would produce wrong (purple/green) colors; use Mux instead.")
            } else {
                lines.append("This video includes Dolby Vision. Compress keeps HDR10 picture data only; Dolby Vision dynamic metadata (RPU) is not preserved.")
            }
        }
        if badges.contains(.hdr10) || badges.contains(.hlg) {
            lines.append("HDR color is preserved when the encoder supports it.")
        }
        // Covers both .hdr10 (dynamic metadata is undetectable at import) and legacy .hdr10Plus badges.
        if badges.contains(.hdr10) || badges.contains(.hdr10Plus) {
            lines.append("This video may include HDR10+ dynamic metadata. Only static HDR10 is verified after export.")
        }
        if encoder == .hardware, badges.contains(.dolbyVision) {
            lines.append("Apple hardware encoding cannot pass through Dolby Vision profiles.")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n\n")
    }
}
