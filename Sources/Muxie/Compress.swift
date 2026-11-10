// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import Foundation

enum ExportMode: String, CaseIterable, Identifiable {
    case remux, compress
    var id: String { rawValue }
}

enum CompressProfile {
    case hd, uhd
    init(height: Int) { self = height > 1080 ? .uhd : .hd }
    var rf: Int { self == .uhd ? 23 : 21 }
    var maxWidth: Int { self == .uhd ? 3840 : 1920 }
    var maxHeight: Int { self == .uhd ? 2160 : 1080 }
}

enum CompressSettings {
    static let encoder = "x265_10bit"
    static let encoderPreset = "medium"
    static let encoderProfile = "main10"
    static let encoderTune = "none"
    static let extraOptions = "aq-mode=3:no-sao=1"
    static let audioBitrate = 192
}

extension Engine {
    static var handbrakeCandidates: [URL] {
        var paths: [String] = []
        if let root = ProcessInfo.processInfo.environment["MUXIE_BIN_DIR"] { paths.append((root as NSString).appendingPathComponent("HandBrakeCLI")) }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("bin/HandBrakeCLI").path { paths.append(bundled) }
        paths += ["/usr/local/bin/HandBrakeCLI", "/opt/homebrew/bin/HandBrakeCLI"]
        return paths.map { URL(fileURLWithPath: $0) }
    }
    static var handbrakeExecutable: URL? { handbrakeCandidates.first { FileManager.default.isExecutableFile(atPath: $0.path) } }

    static func videoAlreadyHEVC1080p(_ tracks: [MediaTrack], sources: [MediaSource], engine: URL) throws -> Bool {
        guard let video = tracks.first(where: { $0.kind == "video" && $0.enabled }),
              let source = sources.first(where: { $0.id == video.sourceID }) else { return false }
        let probe = try identify(source.url, engine: engine)
        guard let vt = probe.tracks.first(where: { $0.id == video.trackID && $0.type == "video" }) else { return false }
        let codec = vt.codec.uppercased()
        guard codec.contains("HEVC") || codec.contains("H.265") else { return false }
        // mkvmerge names the codec "HEVC/H.265/MPEG-H" without a bit depth; the depth is in the hvcC record (codec_private_data).
        guard hevcBitDepth(fromCodecPrivate: vt.properties.codec_private_data) == 10 else { return false }
        guard let dims = vt.properties.pixel_dimensions, let height = Int(dims.split(separator: "x").last ?? "") else { return false }
        return height <= 1080
    }

    /// Luma bit depth from an HEVCDecoderConfigurationRecord given as hex (as mkvmerge prints it), or nil if it cannot be read.
    static func hevcBitDepth(fromCodecPrivate hex: String?) -> Int? {
        guard let hex else { return nil }
        let chars = Array(hex)
        var bytes: [UInt8] = []
        var i = 0
        while i + 1 < chars.count, bytes.count < 19 {
            guard let byte = UInt8(String(chars[i...i + 1]), radix: 16) else { return nil }
            bytes.append(byte); i += 2
        }
        guard bytes.count >= 19, bytes[0] == 1 else { return nil }
        return Int(bytes[17] & 7) + 8
    }

    static func handbrakeArguments(input: URL, output: URL, profile: CompressProfile) -> [String] {
        [
            "--input", input.path,
            "--output", output.path,
            "--format", "av_mkv",
            "--encoder", CompressSettings.encoder,
            "--encoder-preset", CompressSettings.encoderPreset,
            "--encoder-tune", CompressSettings.encoderTune,
            "--encoder-profile", CompressSettings.encoderProfile,
            "--encopts", CompressSettings.extraOptions,
            "--quality", String(profile.rf),
            "--maxWidth", String(profile.maxWidth),
            "--maxHeight", String(profile.maxHeight),
            "--cfr",
            "--all-audio",
            "--aencoder", "av_aac",
            "--mixdown", "stereo",
            "--ab", String(CompressSettings.audioBitrate),
            "--subtitle", "none",
        ]
    }

    static func exportCompressed(plan: ExportPlan, output: URL, mkvmerge: URL, handbrake: URL, job: RunningJob, progress: @escaping @Sendable (Double) -> Void) throws -> String? {
        let fm = FileManager.default
        let target = output.standardizedFileURL.resolvingSymlinksInPath()
        guard !plan.sources.contains(where: { $0.url.standardizedFileURL.resolvingSymlinksInPath() == target }) else {
            throw MuxError.message("The output cannot be a source file. Choose a different name.")
        }
        guard !fm.fileExists(atPath: output.path) else { throw MuxError.message("The output already exists. Choose a different name.") }
        let destination = output.deletingLastPathComponent()
        let fsAttrs = try fm.attributesOfFileSystem(forPath: destination.path)
        let freeBytes = (fsAttrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        let inputBytes = plan.sources.reduce(Int64(0)) { max($0, $1.byteSize) }
        guard freeBytes > inputBytes * 2 else {
            throw MuxError.message("Not enough free space on the destination disk. Need at least \(BluRayISO.bytesDescription(inputBytes * 2)).")
        }
        let remuxStaging = destination.appendingPathComponent(".muxie-remux-\(UUID().uuidString).partial.mkv")
        let encodeStaging = destination.appendingPathComponent(".muxie-compress-\(UUID().uuidString).partial.mkv")
        defer {
            try? fm.removeItem(at: remuxStaging)
            try? fm.removeItem(at: encodeStaging)
        }
        let remuxResult = try job.run(engine: mkvmerge, arguments: plan.arguments(output: remuxStaging)) { value in
            progress(value * 0.12)
        }
        guard remuxResult.0 <= 1 else { throw MuxError.message(String(decoding: remuxResult.1, as: UTF8.self)) }
        if job.cancelled { throw CancellationError() }
        let remuxProbe = try identify(remuxStaging, engine: mkvmerge, job: job)
        let sourceHeight = remuxProbe.tracks.first(where: { $0.type == "video" })?.properties.pixel_dimensions.flatMap { Int($0.split(separator: "x").last ?? "") } ?? 1080
        let profile = CompressProfile(height: sourceHeight)
        let hbArgs = handbrakeArguments(input: remuxStaging, output: encodeStaging, profile: profile)
        let hbResult = try job.runHandBrake(engine: handbrake, arguments: hbArgs) { value in
            progress(0.12 + value * 0.88)
        }
        guard hbResult.0 == 0 else { throw MuxError.message(String(decoding: hbResult.1, as: UTF8.self)) }
        if job.cancelled { throw CancellationError() }
        // HandBrakeCLI exits 0 even for an unknown option or a failed scan, so success is only trusted when the file exists.
        guard fm.fileExists(atPath: encodeStaging.path) else {
            let tail = String(decoding: hbResult.1, as: UTF8.self).components(separatedBy: .newlines).suffix(6).joined(separator: "\n")
            throw MuxError.message("HandBrake did not produce an output file.\n" + tail)
        }
        let probe = try identify(encodeStaging, engine: mkvmerge, job: job)
        guard let video = probe.tracks.first(where: { $0.type == "video" }) else {
            throw MuxError.message("Compressed output has no video track.")
        }
        let vcodec = video.codec.uppercased()
        guard vcodec.contains("HEVC") || vcodec.contains("H.265") else {
            throw MuxError.message("Compressed output video codec verification failed.")
        }
        if let dims = video.properties.pixel_dimensions, let height = Int(dims.split(separator: "x").last ?? ""), height > profile.maxHeight {
            throw MuxError.message("Compressed output exceeds the target resolution.")
        }
        let audioTracks = probe.tracks.filter { $0.type == "audio" }
        // A project may have every audio track unchecked; then a video-only output is correct.
        let wantedAudio = plan.orderedTracks.filter { $0.kind == "audio" }.count
        guard (wantedAudio == 0 || !audioTracks.isEmpty), audioTracks.allSatisfy({ $0.codec.uppercased().contains("AAC") }) else {
            throw MuxError.message("Compressed output audio codec verification failed.")
        }
        guard !probe.tracks.contains(where: { $0.type == "subtitles" }) else { throw MuxError.message("Compressed output still contains subtitles.") }
        if job.cancelled { throw CancellationError() }
        try job.commit { try fm.moveItem(at: encodeStaging, to: output) }
        return nil
    }
}

extension RunningJob {
    func runHandBrake(engine: URL, arguments: [String], progress: @escaping @Sendable (Double) -> Void) throws -> (Int32, Data) {
        let p = Process()
        p.executableURL = engine
        p.arguments = arguments
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "en_US.UTF-8"
        p.environment = environment
        lock.lock()
        if wasCancelled { lock.unlock(); throw CancellationError() }
        do { try p.run(); process = p; lock.unlock() } catch { lock.unlock(); throw error }
        var all = Data()
        var pending = ""
        while true {
            let data = pipe.fileHandleForReading.availableData
            if data.isEmpty { break }
            all.append(data)
            pending += String(decoding: data, as: UTF8.self)
            let lines = pending.components(separatedBy: .newlines)
            pending = lines.last ?? ""
            for line in lines.dropLast() {
                if let value = Self.handBrakePercent(in: line) { progress(min(1, max(0, value / 100))) }
            }
        }
        if let value = Self.handBrakePercent(in: pending) { progress(min(1, max(0, value / 100))) }
        p.waitUntilExit()
        lock.lock()
        process = nil
        let cancelled = wasCancelled
        lock.unlock()
        if cancelled { throw CancellationError() }
        return (p.terminationStatus, all)
    }

    private static func handBrakePercent(in line: String) -> Double? {
        guard let match = line.range(of: #"(\d+(?:\.\d+)?)\s*%"#, options: .regularExpression) else { return nil }
        let token = String(line[match]).replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        return Double(token)
    }
}
