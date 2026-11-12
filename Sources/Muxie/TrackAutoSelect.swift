// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import Foundation

/// Checks the tracks of a newly opened video: the first video, the best audio, one English and one Chinese subtitle.
enum TrackAutoSelect {
    static func apply(_ tracks: inout [MediaTrack]) {
        if let video = tracks.firstIndex(where: { $0.kind == "video" }) { tracks[video].enabled = true }
        if let audio = bestAudio(in: tracks) {
            tracks[audio].enabled = true
            for index in tracks.indices where tracks[index].kind == "audio" { tracks[index].isDefault = index == audio }
        }
        for language in ["en", "zh"] {
            if let subtitle = bestSubtitle(in: tracks, language: language) { tracks[subtitle].enabled = true }
        }
    }

    /// Higher is better: lossless first, then the richer lossy formats.
    static func audioCodecRank(_ codec: String) -> Int {
        let c = codec.uppercased()
        if c.contains("TRUEHD") || c.contains("MLP") { return c.contains("ATMOS") ? 100 : 95 }
        if c.contains("DTS-HD MASTER") || c.contains("DTS-HD MA") || c.contains("DTS:X") || c.contains("DTS-X") { return 90 }
        if c.contains("FLAC") || c.contains("PCM") || c.contains("ALAC") || c.contains("WAVPACK") { return 85 }
        if c.contains("DTS-HD") { return 70 }
        if c.contains("E-AC-3") || c.contains("EAC3") || c.contains("E-AC3") { return 60 }
        if c.contains("DTS") { return 55 }
        if c.contains("AC-3") || c.contains("AC3") { return 50 }
        if c.contains("AAC") { return 40 }
        if c.contains("OPUS") { return 38 }
        if c.contains("VORBIS") { return 30 }
        if c.contains("MP3") || c.contains("MPEG") { return 20 }
        return 10
    }

    static func bestAudio(in tracks: [MediaTrack]) -> Int? {
        let audio = tracks.indices.filter { tracks[$0].kind == "audio" }
        let main = audio.filter { !isSecondary(tracks[$0]) }
        let pool = main.isEmpty ? audio : main
        return pool.max { lhs, rhs in
            let l = tracks[lhs], r = tracks[rhs]
            let lKey = (audioCodecRank(l.codec), l.audioChannels ?? 0, l.isDefault ? 1 : 0, -lhs)
            let rKey = (audioCodecRank(r.codec), r.audioChannels ?? 0, r.isDefault ? 1 : 0, -rhs)
            return lKey < rKey
        }
    }

    static func bestSubtitle(in tracks: [MediaTrack], language: String) -> Int? {
        let candidates = tracks.indices.filter { tracks[$0].kind == "subtitles" && LanguageTag.base(tracks[$0].language) == language && !isSecondary(tracks[$0]) }
        return candidates.max { lhs, rhs in
            let lKey = (subtitleScore(tracks[lhs]), -lhs), rKey = (subtitleScore(tracks[rhs]), -rhs)
            return lKey < rKey
        }
    }

    private static func subtitleScore(_ track: MediaTrack) -> Int {
        let name = track.name.lowercased()
        var score = 0
        if !track.isForced && !name.contains("forced") { score += 8 }
        if !["sdh", "hearing", "cc"].contains(where: { name.contains($0) }) { score += 4 }
        if LanguageTag.base(track.language) == "zh" {
            let tag = track.language.lowercased()
            let simplified = tag.contains("hans") || tag.hasSuffix("-cn") || tag.hasSuffix("-sg") || ["simplified", "chs", "gb", "\u{7B80}"].contains(where: { name.contains($0) })
            let traditional = tag.contains("hant") || tag.hasSuffix("-tw") || tag.hasSuffix("-hk") || ["traditional", "cht", "big5", "\u{7E41}"].contains(where: { name.contains($0) })
            if simplified { score += 2 } else if !traditional { score += 1 }
        }
        return score
    }

    private static func isSecondary(_ track: MediaTrack) -> Bool {
        let name = track.name.lowercased()
        return ["commentary", "comment", "director", "descriptive", "audio description", "\u{8BC4}\u{8BBA}", "\u{89E3}\u{8BF4}"].contains { name.contains($0) }
    }
}
