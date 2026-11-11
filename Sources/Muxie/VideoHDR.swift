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

    /// Dolby Vision profile from the container's configuration record, which `mkvmerge -J` does not report:
    /// Matroska keeps it in a BlockAdditionMapping (type dvcC/dvvC/dvwC), MP4 in a box of the same name.
    /// Reads the first and last 16 MB (MP4 files may keep `moov` at the end). Nil when there is none.
    static func dolbyVisionProfile(fileURL: URL) -> Int? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        let window = 16 << 20
        if let head = try? handle.read(upToCount: window), let profile = dolbyVisionProfile(containerBytes: head) { return profile }
        if let size = try? handle.seekToEnd(), size > UInt64(window) {
            try? handle.seek(toOffset: size - UInt64(window))
            if let tail = try? handle.read(upToCount: window), let profile = dolbyVisionProfile(containerBytes: tail) { return profile }
        }
        return nil
    }

    /// Finds a DOVIDecoderConfigurationRecord (version major, minor, then profile in the top 7 bits) after a dvcC/dvvC/dvwC tag.
    static func dolbyVisionProfile(containerBytes data: Data) -> Int? {
        let b = [UInt8](data)
        var i = 3
        while i + 4 <= b.count {
            defer { i += 1 }
            guard b[i] == 0x64, b[i + 1] == 0x76, b[i + 2] == 0x63 || b[i + 2] == 0x76 || b[i + 2] == 0x77, b[i + 3] == 0x43 else { continue }
            var p = i + 4
            // Matroska: BlockAddIDType (0x41E7, 4-byte uint) is followed by BlockAddIDExtraData (0x41ED, size, record).
            if b[i - 3] == 0x41, b[i - 2] == 0xE7, b[i - 1] == 0x84 {
                var q = p
                let limit = min(b.count - 2, p + 48)
                while q < limit, !(b[q] == 0x41 && b[q + 1] == 0xED) { q += 1 }
                guard q < limit else { continue }
                q += 2
                guard q < b.count else { continue }
                var length = 1
                var mask: UInt8 = 0x80
                while length <= 8, b[q] & mask == 0 { length += 1; mask >>= 1 }
                p = q + length
            }
            guard p + 3 <= b.count, (1...3).contains(b[p]) else { continue }
            let profile = Int(b[p + 2] >> 1)
            if [4, 5, 7, 8, 9, 10].contains(profile) { return profile }
        }
        return nil
    }

    /// HandBrake 1.11.2 passes HDR10+ and Dolby Vision (profiles 5, 7, 8, 10) through both H.265 10-bit encoders by default,
    /// so only the cases that change the stream are worth a warning.
    static func compressExportWarning(badges: [HDRBadge], encoder: CompressEncoder, dolbyVisionProfiles: [Int] = []) -> String? {
        var lines: [String] = []
        if dolbyVisionProfiles.contains(7) {
            lines.append("This video is Dolby Vision Profile 7 (UHD Blu-ray). Compress converts it to Profile 8.1 and drops the enhancement layer.")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n\n")
    }
}
