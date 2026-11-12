// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import Foundation

/// mkvmerge reads text subtitles as UTF-8 unless told otherwise; Chinese subtitles are often GBK/GB18030 or Big5.
enum SubtitleCharset {
    static let textExtensions: Set<String> = ["srt", "ass", "ssa", "vtt", "sub", "txt"]
    static let gb18030 = String.Encoding(rawValue: 0x8000_0632)
    static let big5 = String.Encoding(rawValue: 0x8000_0A03)
    /// Very common Chinese characters, in the simplified and the traditional forms that GB18030 and Big5 text decode to.
    private static let simplifiedCommon: Set<UInt32> = [0x7684, 0x4E00, 0x662F, 0x4E0D, 0x4E86, 0x6211, 0x4F60, 0x5728, 0x4ED6, 0x8FD9, 0x4E2A, 0x4EEC, 0x6765, 0x8BF4, 0x4E48, 0x6CA1, 0x6709, 0x5417, 0x5230, 0x5C31]
    private static let traditionalCommon: Set<UInt32> = [0x7684, 0x4E00, 0x662F, 0x4E0D, 0x4E86, 0x6211, 0x4F60, 0x5728, 0x4ED6, 0x9019, 0x500B, 0x5011, 0x4F86, 0x8AAA, 0x9EBC, 0x6C92, 0x6709, 0x55CE, 0x5230, 0x5C31]

    /// The mkvmerge character set for a text subtitle file, or nil when it is UTF-8/UTF-16 or not a text subtitle.
    static func detect(fileURL: URL) -> String? {
        guard textExtensions.contains(fileURL.pathExtension.lowercased()),
              let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return nil }
        return detect(data)
    }

    static func detect(_ data: Data) -> String? {
        let head = [UInt8](data.prefix(3))
        if head.starts(with: [0xEF, 0xBB, 0xBF]) || head.starts(with: [0xFF, 0xFE]) || head.starts(with: [0xFE, 0xFF]) { return nil }
        if String(data: data, encoding: .utf8) != nil { return nil }
        let gbScore = score(String(data: data, encoding: gb18030), common: simplifiedCommon)
        let big5Score = score(String(data: data, encoding: big5), common: traditionalCommon)
        if gbScore == 0 && big5Score == 0 { return "WINDOWS-1252" }
        return big5Score > gbScore ? "BIG5" : "GB18030"
    }

    private static func score(_ text: String?, common: Set<UInt32>) -> Int {
        guard let text else { return 0 }
        return text.unicodeScalars.reduce(0) { $0 + (common.contains($1.value) ? 1 : 0) }
    }
}
