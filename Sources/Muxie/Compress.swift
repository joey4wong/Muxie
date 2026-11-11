// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import Foundation

/// Which H.265 encoder Compress uses. Chosen in the toolbar; the default is the Apple hardware encoder.
enum CompressEncoder: String, CaseIterable, Identifiable, Codable, Sendable {
    case hardware, software
    var id: String { rawValue }
    static let defaultsKey = "compressEncoder"
    static var current: CompressEncoder {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(CompressEncoder.init(rawValue:)) ?? .software }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
    var label: String { self == .hardware ? "Hardware (Apple VideoToolbox)" : "Software (x265)" }
    var technology: String { self == .hardware ? "H.265 hardware acceleration (Apple)" : "x265 software encoding" }
    var shortLabel: String { self == .hardware ? "Fast" : "Best" }
    var detail: String {
        self == .hardware
            ? "Much faster, cooler and quieter. Files come out larger than x265 at similar quality."
            : "Slow, but the smallest files and the best detail and film grain."
    }
    var handbrakeEncoder: String { self == .hardware ? "vt_h265_10bit" : "x265_10bit" }
}

enum CompressProfile {
    case hd, uhd
    init(height: Int) { self = height > 1080 ? .uhd : .hd }
    /// HandBrake VideoToolbox quality (0–100, higher is better); tuned by the owner after real-file tests.
    var quality: Int { self == .uhd ? 60 : 65 }
    /// x265 constant quality (RF, lower is better).
    var rf: Int { self == .uhd ? 23 : 21 }
    var maxWidth: Int { self == .uhd ? 3840 : 1920 }
    var maxHeight: Int { self == .uhd ? 2160 : 1080 }
}

enum CompressSettings {
    static let encoder = CompressEncoder.hardware.handbrakeEncoder
    static let x265Preset = "medium"
    // No tune: HandBrake's "None" means the option is omitted. Passing the word "none" makes x265 reject the preset.
    static let x265ExtraOptions = "aq-mode=3:no-sao=1"
    /// The VideoToolbox encoder offers `speed` and `quality`; quality is the better picture per bit.
    static let encoderPreset = "quality"
    /// Included when HandBrake lists main10 for vt_h265_10bit (`HandBrakeCLI --encoder-profile-list vt_h265_10bit`).
    static let encoderProfile = "main10"
    /// HandBrake av_aac is treated as unable to carry 7.1; sources above 6 channels encode as 5.1 (owner to verify 7point1 on HandBrake 1.11.2).
    static let maxAACChannels = 6

    static func audioBitrateKbps(channelCount: Int) -> Int {
        switch channelCount {
        case 1: return 96
        case 2: return 192
        default: return 384   // 3 to 6 channels; 7.1 sources are encoded as 5.1 and use the same rate
        }
    }

    static func encodedChannelCount(sourceChannels: Int) -> Int {
        min(max(sourceChannels, 1), maxAACChannels)
    }

    static func handbrakeMixdown(sourceChannels: Int) -> String {
        if sourceChannels > maxAACChannels { return "5point1" }
        let channels = encodedChannelCount(sourceChannels: sourceChannels)
        switch channels {
        case 1: return "mono"
        case 2: return "stereo"
        default: return "none"
        }
    }
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

    /// AAC sources with at most 5.1 channels are copied untouched (no generation loss, no encode time).
    static func audioIsCopied(channels: Int, isAAC: Bool) -> Bool { isAAC && channels <= CompressSettings.maxAACChannels }

    static func handbrakeArguments(input: URL, output: URL, profile: CompressProfile, encoder: CompressEncoder = .hardware, sourceAudioChannels: [Int], sourceAudioIsAAC: [Bool] = []) -> [String] {
        var args = [
            "--input", input.path,
            "--output", output.path,
            "--format", "av_mkv",
            "--encoder", encoder.handbrakeEncoder,
            "--encoder-profile", CompressSettings.encoderProfile,
        ]
        if encoder == .hardware {
            args += ["--encoder-preset", CompressSettings.encoderPreset, "--quality", String(profile.quality)]
        } else {
            args += ["--encoder-preset", CompressSettings.x265Preset, "--encopts", CompressSettings.x265ExtraOptions, "--quality", String(profile.rf)]
        }
        args += [
            "--maxWidth", String(profile.maxWidth),
            "--maxHeight", String(profile.maxHeight),
            "--cfr",
            "--crop-mode", "none",
            "--subtitle", "none",
        ]
        if sourceAudioChannels.isEmpty {
            args += ["--audio", "none"]
        } else {
            args.append("--all-audio")
        }
        if !sourceAudioChannels.isEmpty {
            let bitrates = sourceAudioChannels.map { String(CompressSettings.audioBitrateKbps(channelCount: $0)) }.joined(separator: ",")
            let mixdowns = sourceAudioChannels.map { CompressSettings.handbrakeMixdown(sourceChannels: $0) }.joined(separator: ",")
            // One entry per audio track, in order. A copied track ignores its mixdown and bitrate entries.
            let encoders = sourceAudioChannels.enumerated().map { index, channels in
                audioIsCopied(channels: channels, isAAC: index < sourceAudioIsAAC.count && sourceAudioIsAAC[index]) ? "copy:aac" : "av_aac"
            }.joined(separator: ",")
            // The fallback matters: HandBrake's default fallback for a track that cannot be copied is AC-3.
            args += ["--aencoder", encoders, "--audio-fallback", "av_aac", "--mixdown", mixdowns, "--ab", bitrates]
        }
        return args
    }

    static func exportCompressed(plan: ExportPlan, output: URL, mkvmerge: URL, handbrake: URL, job: RunningJob, encoder: CompressEncoder = CompressEncoder.current, progress: @escaping @Sendable (JobProgress) -> Void) throws -> String? {
        let fm = FileManager.default
        let target = output.standardizedFileURL.resolvingSymlinksInPath()
        guard !plan.sources.contains(where: { $0.url.standardizedFileURL.resolvingSymlinksInPath() == target }) else {
            throw MuxError.message("The output cannot be a source file. Choose a different name.")
        }
        guard !fm.fileExists(atPath: output.path) else { throw MuxError.message("The output already exists. Choose a different name.") }
        let destination = output.deletingLastPathComponent()
        try ExportSpace.verifySpace(mode: .compress, plan: plan, destination: destination)
        let tag = String(UUID().uuidString.prefix(6))
        let base = output.deletingPathExtension().lastPathComponent
        let remuxStaging = destination.appendingPathComponent("Muxie temp - \(base) (remux \(tag)).partial.mkv")
        let encodeStaging = destination.appendingPathComponent("Muxie temp - \(base) (encode \(tag)).partial.mkv")
        let finalStaging = destination.appendingPathComponent("Muxie temp - \(base) (finalize \(tag)).partial.mkv")
        for url in [remuxStaging, encodeStaging, finalStaging] { TempFileRegistry.register(url) }
        defer {
            for url in [remuxStaging, encodeStaging, finalStaging] {
                TempFileRegistry.unregister(url)
                try? fm.removeItem(at: url)
            }
        }
        guard plan.orderedTracks.contains(where: { $0.kind == "video" }) else {
            throw MuxError.message("Compress needs at least one enabled video track.")
        }
        let hbInputArgs = plan.handbrakeInputArguments(output: remuxStaging)
        let remuxResult = try job.run(engine: mkvmerge, arguments: hbInputArgs) { update in
            var scaled = update
            scaled.value *= 0.10
            scaled.phase = .prepare
            progress(scaled)
        }
        guard remuxResult.0 <= 1 else { throw MuxError.message(String(decoding: remuxResult.1, as: UTF8.self)) }
        if job.cancelled { throw CancellationError() }
        let remuxProbe = try identify(remuxStaging, engine: mkvmerge, job: job)
        let sourceHeight = remuxProbe.tracks.first(where: { $0.type == "video" })?.properties.pixel_dimensions.flatMap { Int($0.split(separator: "x").last ?? "") }
            ?? plan.tracks.first(where: { $0.kind == "video" })?.pixelHeight ?? 1080
        let hdrSource = plan.tracks.first(where: { $0.kind == "video" && $0.enabled })?.colorTransfer
        let sourceAudioTracks = remuxProbe.tracks.filter { $0.type == "audio" }
        let sourceAudioChannels = sourceAudioTracks.map { $0.properties.audio_channels ?? 2 }
        let sourceAudioIsAAC = sourceAudioTracks.map { $0.codec.uppercased().contains("AAC") }
        let profile = CompressProfile(height: sourceHeight)
        let hbArgs = handbrakeArguments(input: remuxStaging, output: encodeStaging, profile: profile, encoder: encoder, sourceAudioChannels: sourceAudioChannels, sourceAudioIsAAC: sourceAudioIsAAC)
        let hbResult = try job.runHandBrake(engine: handbrake, arguments: hbArgs) { update in
            var scaled = update
            scaled.value = 0.10 + update.value * 0.82
            scaled.phase = .encode
            progress(scaled)
        }
        let hbLog = hbResult.1
        if let encoderError = Self.handBrakeMissingEncoderMessage(in: hbLog, encoder: encoder) {
            throw MuxError.message(encoderError)
        }
        guard hbResult.0 == 0 else { throw MuxError.message(hbLog) }
        if job.cancelled { throw CancellationError() }
        guard fm.fileExists(atPath: encodeStaging.path) else {
            let tail = hbLog.components(separatedBy: .newlines).suffix(6).joined(separator: "\n")
            throw MuxError.message("HandBrake did not produce an output file.\n" + tail)
        }
        let encodedProbe = try identify(encodeStaging, engine: mkvmerge, job: job)
        guard let video = encodedProbe.tracks.first(where: { $0.type == "video" }) else {
            throw MuxError.message("Compressed output has no video track.")
        }
        let vcodec = video.codec.uppercased()
        guard vcodec.contains("HEVC") || vcodec.contains("H.265") else {
            throw MuxError.message("Compressed output video codec verification failed.")
        }
        guard hevcBitDepth(fromCodecPrivate: video.properties.codec_private_data) == 10 else {
            throw MuxError.message("Compressed output is not 10-bit.")
        }
        if let dims = video.properties.pixel_dimensions, let height = Int(dims.split(separator: "x").last ?? ""), height > profile.maxHeight {
            throw MuxError.message("Compressed output exceeds the target resolution.")
        }
        let audioTracks = encodedProbe.tracks.filter { $0.type == "audio" }
        let wantedEncodeAudio = plan.orderedTracks.filter { $0.kind == "audio" && plan.audioNeedsEncode($0) }.count
        guard (wantedEncodeAudio == 0 || !audioTracks.isEmpty), audioTracks.allSatisfy({ $0.codec.uppercased().contains("AAC") }) else {
            throw MuxError.message("Compressed output audio codec verification failed.")
        }
        if !sourceAudioChannels.isEmpty {
            guard audioTracks.count == sourceAudioChannels.count else {
                throw MuxError.message("Compressed output audio channel layout verification failed.")
            }
            for (actual, source) in zip(audioTracks, sourceAudioChannels) {
                let expected = CompressSettings.encodedChannelCount(sourceChannels: source)
                guard (actual.properties.audio_channels ?? 0) == expected else {
                    throw MuxError.message("Compressed output audio channel layout verification failed.")
                }
            }
        }
        if let transfer = hdrSource, transfer == 16 || transfer == 18,
           video.properties.color_transfer_characteristics != transfer {
            throw MuxError.message("Compressed output lost the HDR transfer characteristics.")
        }
        let finalizeArgs = plan.compressFinalizeArguments(output: finalStaging, encodedURL: encodeStaging, encodedProbe: encodedProbe)
        let finalizeResult = try job.run(engine: mkvmerge, arguments: finalizeArgs) { update in
            var scaled = update
            scaled.value = 0.92 + update.value * 0.08
            scaled.phase = .finalize
            progress(scaled)
        }
        guard finalizeResult.0 <= 1 else { throw MuxError.message(String(decoding: finalizeResult.1, as: UTF8.self)) }
        if job.cancelled { throw CancellationError() }
        let probe = try identify(finalStaging, engine: mkvmerge, job: job)
        let expected = plan.orderedTracks
        guard probe.tracks.count == expected.count else {
            throw MuxError.message("Output track count verification failed. No output was saved.")
        }
        for (actual, wanted) in zip(probe.tracks, expected) {
            let typeOK = actual.type == wanted.kind
            let nameOK = (actual.properties.track_name ?? "") == wanted.name
            let defaultOK = (actual.properties.default_track ?? false) == wanted.isDefault
            let forcedOK = (actual.properties.forced_track ?? false) == wanted.isForced
            let codecOK = wanted.kind != "video" ? (actual.codec == wanted.codec || wanted.kind == "audio" && actual.codec.uppercased().contains("AAC")) : actual.codec.uppercased().contains("HEVC")
            guard typeOK && nameOK && defaultOK && forcedOK && codecOK else {
                throw MuxError.message("Output track verification failed. No output was saved.")
            }
        }
        if job.cancelled { throw CancellationError() }
        try job.commit { try fm.moveItem(at: finalStaging, to: output) }
        return nil
    }

    static func parseHandBrakeEncodingLine(_ line: String) -> (percent: Double, fps: Double?, avgFPS: Double?, etaSeconds: TimeInterval?)? {
        guard line.contains("Encoding:"), line.contains("%") else { return nil }
        guard let percentMatch = line.range(of: #"(\d+(?:\.\d+)?)\s*%"#, options: .regularExpression) else { return nil }
        let percentToken = String(line[percentMatch]).replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        guard let percent = Double(percentToken) else { return nil }
        let fps = line.range(of: #"\((\d+(?:\.\d+)?)\s*fps"#, options: .regularExpression).flatMap { range -> Double? in
            let token = String(line[range]).replacingOccurrences(of: "(", with: "").replacingOccurrences(of: "fps", with: "").trimmingCharacters(in: .whitespaces)
            return Double(token)
        }
        let avgFPS = line.range(of: #"avg\s+(\d+(?:\.\d+)?)\s*fps"#, options: .regularExpression).flatMap { range -> Double? in
            let token = String(line[range]).replacingOccurrences(of: "avg", with: "").replacingOccurrences(of: "fps", with: "").trimmingCharacters(in: .whitespaces)
            return Double(token)
        }
        let etaSeconds: TimeInterval? = line.range(of: #"ETA\s+(\d{2})h(\d{2})m(\d{2})s"#, options: .regularExpression).flatMap { range -> TimeInterval? in
            let token = String(line[range]).replacingOccurrences(of: "ETA", with: "").trimmingCharacters(in: .whitespaces)
            let parts = token.split(separator: Character("h")).flatMap { $0.split(separator: Character("m")) }
            guard parts.count >= 3,
                  let h = Int(parts[0].filter(\.isNumber)),
                  let m = Int(parts[1].filter(\.isNumber)),
                  let s = Int(String(parts[2]).filter(\.isNumber)) else { return nil }
            return TimeInterval(h * 3600 + m * 60 + s)
        }
        return (percent, fps, avgFPS, etaSeconds)
    }

    /// One-line error when HandBrake does not offer the VideoToolbox H.265 10-bit encoder.
    static func handBrakeMissingEncoderMessage(in log: String, encoder: CompressEncoder = .hardware) -> String? {
        let upper = log.uppercased()
        guard upper.contains("INVALID VIDEO ENCODER") || upper.contains("UNKNOWN ENCODER") else { return nil }
        return "HandBrake does not support the \(encoder.label) H.265 10-bit encoder (\(encoder.handbrakeEncoder))."
    }
}

private final class LogTailBuffer: @unchecked Sendable {
    private let limit: Int
    private var storage = ""
    private let lock = NSLock()
    init(limit: Int = 65_536) { self.limit = limit }
    func append(_ text: String) {
        lock.lock()
        storage += text
        if storage.count > limit { storage = String(storage.suffix(limit)) }
        lock.unlock()
    }
    var text: String { lock.lock(); defer { lock.unlock() }; return storage }
}

extension RunningJob {
    func runHandBrake(engine: URL, arguments: [String], progress: @escaping @Sendable (JobProgress) -> Void) throws -> (Int32, String) {
        let p = Process()
        p.executableURL = engine
        p.arguments = arguments
        let errPipe = Pipe()
        p.standardOutput = FileHandle.nullDevice
        p.standardError = errPipe
        p.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "en_US.UTF-8"
        p.environment = environment
        lock.lock()
        if wasCancelled { lock.unlock(); throw CancellationError() }
        do { try p.run(); process = p; if isPaused { kill(p.processIdentifier, SIGSTOP) }; lock.unlock() } catch { lock.unlock(); throw error }
        let log = LogTailBuffer()
        var errPending = ""
        let readGroup = DispatchGroup()
        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            while true {
                let data = errPipe.fileHandleForReading.availableData
                if data.isEmpty { break }
                let chunk = String(decoding: data, as: UTF8.self)
                log.append(chunk)
                errPending += chunk
                let lines = errPending.components(separatedBy: .newlines)
                errPending = lines.last ?? ""
                for line in lines.dropLast() {
                    if let parsed = Engine.parseHandBrakeEncodingLine(line) {
                        var update = JobProgress.fraction(min(1, max(0, parsed.percent / 100)))
                        update.phase = .encode
                        update.fps = parsed.avgFPS ?? parsed.fps
                        update.etaSeconds = parsed.etaSeconds
                        progress(update)
                    }
                }
            }
            if let parsed = Engine.parseHandBrakeEncodingLine(errPending) {
                var update = JobProgress.fraction(min(1, max(0, parsed.percent / 100)))
                update.phase = .encode
                update.fps = parsed.avgFPS ?? parsed.fps
                update.etaSeconds = parsed.etaSeconds
                progress(update)
            }
            readGroup.leave()
        }
        p.waitUntilExit()
        readGroup.wait()
        lock.lock()
        process = nil
        let cancelled = wasCancelled
        lock.unlock()
        if cancelled { throw CancellationError() }
        return (p.terminationStatus, log.text)
    }
}
