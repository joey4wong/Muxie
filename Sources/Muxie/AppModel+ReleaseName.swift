// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import Foundation

extension AppModel {
    /// Standard release name for films that are compressed (Compress mode) or already HEVC 10-bit 1080p or below:
    /// Title.Year.1080p.BluRay.x265.10bit.AAC-Joey.mkv (4K in place of 1080p for UHD). Nil if no year can be found in the file name.
    func sceneName(from baseName: String) -> String? {
        guard exportMode == .compress else { return nil }
        let cleaned = baseName.replacingOccurrences(of: "-compressed", with: "").replacingOccurrences(of: "-muxie", with: "")
        let words = cleaned.split(whereSeparator: { " ._()[]".contains($0) }).map(String.init)
        guard let yearIndex = words.lastIndex(where: { $0.count == 4 && $0.hasPrefix("19") || $0.count == 4 && $0.hasPrefix("20") }),
              words[yearIndex].allSatisfy(\.isNumber), yearIndex > 0 else { return nil }
        let bad = CharacterSet(charactersIn: "/:\\*?\"<>|,'\u{2019}!")
        let title = words[..<yearIndex].map { String($0.unicodeScalars.filter { !bad.contains($0) }) }.filter { !$0.isEmpty }.joined(separator: ".")
        guard !title.isEmpty else { return nil }
        let height = tracks.first(where: { $0.kind == "video" && $0.enabled })?.detail.split(separator: "\u{00D7}").last.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 1080
        let res = height > 1080 ? "4K" : height <= 576 ? "\(height)p" : "1080p"
        let codec = CompressEncoder.current == .hardware ? "HEVC" : "x265"
        let fromISO = sources.first?.originURL?.pathExtension.lowercased() == "iso"
        let fromDVD = sources.first.flatMap { isoMounts[$0.id]?.isDVD } ?? false
        let sourceTag = releaseSourceTag(baseName: cleaned, fromISO: fromISO, fromDVD: fromDVD)
        let hdrTag: String? = {
            guard let badge = tracks.first(where: { $0.kind == "video" && $0.enabled })?.hdrBadge else { return nil }
            switch badge {
            case .dolbyVision: return "DV"
            case .hdr10Plus, .hdr10: return "HDR"
            case .hlg: return "HLG"
            }
        }()
        let hasAudio = tracks.contains { $0.enabled && $0.kind == "audio" }
        var parts = [title, words[yearIndex], res]
        if let sourceTag { parts.append(sourceTag) }
        if let hdrTag { parts.append(hdrTag) }
        parts += [codec, "10bit"]
        if hasAudio { parts.append("AAC") }
        parts.append("Joey")
        return parts.joined(separator: ".") + ".mkv"
    }
    private func releaseSourceTag(baseName: String, fromISO: Bool, fromDVD: Bool) -> String? {
        if fromISO { return fromDVD ? "DVD" : "BluRay" }
        let upper = baseName.uppercased()
        if upper.contains("WEB-DL") || upper.contains("WEBDL") { return "WEB-DL" }
        if upper.contains("WEBRIP") { return "WEBRip" }
        if upper.contains("HDTV") { return "HDTV" }
        if upper.contains("BLURAY") || upper.contains("BLU-RAY") { return "BluRay" }
        return nil
    }
}
