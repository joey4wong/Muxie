// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import Foundation

enum MuxError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}
struct Probe: Decodable {
    struct Container: Decodable {
        struct Properties: Decodable { var duration: Int64? }
        var recognized: Bool; var supported: Bool; var type: String?; var properties: Properties?
    }
    struct Track: Decodable {
        struct Properties: Decodable {
            var track_name: String?; var language: String?; var language_ietf: String?
            var default_track: Bool?; var forced_track: Bool?
            var pixel_dimensions: String?; var audio_channels: Int?; var audio_sampling_frequency: Double?
            var codec_private_data: String?
            var color_primaries: Int?; var color_transfer_characteristics: Int?; var max_content_light: Int?
        }
        var id: Int; var type: String; var codec: String; var properties: Properties
    }
    var container: Container; var tracks: [Track]; var errors: [String]?
}
struct MediaTrack: Identifiable, Equatable, Sendable {
    var id = UUID(); var sourceID: UUID; var trackID: Int; var kind: String; var codec: String
    var name: String; var language: String; var isDefault: Bool; var isForced: Bool; var enabled: Bool
    var detail: String
    var symbol: String { kind == "video" ? "film" : kind == "audio" ? "waveform" : "captions.bubble" }
    var kindName: String { kind == "video" ? "Video" : kind == "audio" ? "Audio" : "Subtitle" }
    var filterName: String { kind == "subtitles" ? "Subtitles" : kindName }
}
struct MediaSource: Identifiable, Equatable, Sendable {
    var id: UUID; var url: URL; var originURL: URL? = nil; var container: String; var byteSize: Int64
    /// Further files of the same source, appended after `url` (the extra clips of a Blu-ray main title).
    var appendedParts: [URL] = []
    var displayURL: URL { originURL ?? url }
}
struct ExportPlan: Sendable {
    var sources: [MediaSource]; var tracks: [MediaTrack]
    var orderedTracks: [MediaTrack] { sources.flatMap { source in tracks.filter { $0.sourceID == source.id && $0.enabled } } }
    func arguments(output: URL) -> [String] {
        var args = ["--ui-language", "en_US", "--gui-mode", "-o", output.path]
        var order: [String] = []; var fileIndex = 0
        for source in sources {
            let keep = tracks.filter { $0.sourceID == source.id && $0.enabled }
            guard !keep.isEmpty || source.id == sources.first?.id else { continue }
            for (kind, select, none) in [("video", "--video-tracks", "--no-video"), ("audio", "--audio-tracks", "--no-audio"), ("subtitles", "--subtitle-tracks", "--no-subtitles")] {
                let ids = keep.filter { $0.kind == kind }.map { String($0.trackID) }
                if ids.isEmpty { args.append(none) } else { args += [select, ids.joined(separator: ",")] }
            }
            // Preserve primary metadata even when all of its tracks are excluded.
            // Keep subtitle font attachments from additional Matroska sources.
            if source.id != sources.first?.id {
                args += ["--no-chapters", "--no-global-tags"]
                if !keep.contains(where: { $0.kind == "subtitles" }) { args.append("--no-attachments") }
            }
            for track in keep {
                args += ["--track-name", "\(track.trackID):\(track.name)", "--language", "\(track.trackID):\(track.language.isEmpty ? "und" : track.language)", "--default-track-flag", "\(track.trackID):\(track.isDefault ? "yes" : "no")", "--forced-display-flag", "\(track.trackID):\(track.isForced ? "yes" : "no")"]
                order.append("\(fileIndex):\(track.trackID)")
            }
            args.append(source.url.path)
            for part in source.appendedParts { args += ["+", part.path] }
            fileIndex += 1
        }
        args += ["--track-order", order.joined(separator: ",")]
        return args
    }
}
final class RunningJob: @unchecked Sendable {
    // Internal (not private): RunningJob.runHandBrake lives in Compress.swift and shares this state.
    let lock = NSLock(); var process: Process?; var wasCancelled = false; private var committed = false
    /// Pause stops the running tool (SIGSTOP); a tool launched while paused is stopped right after it starts.
    var isPaused = false
    func pause() { lock.lock(); defer { lock.unlock() }; isPaused = true; if let p = process, p.isRunning { kill(p.processIdentifier, SIGSTOP) } }
    func resume() { lock.lock(); defer { lock.unlock() }; isPaused = false; if let p = process, p.isRunning { kill(p.processIdentifier, SIGCONT) } }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        guard !committed else { return }
        wasCancelled = true
        if let p = process, p.isRunning {
            p.terminate()
            // A stopped process only sees SIGTERM once it continues.
            if isPaused { kill(p.processIdentifier, SIGCONT) }
        }
    }
    func commit(_ action: () throws -> Void) throws {
        lock.lock(); defer { lock.unlock() }
        if wasCancelled { throw CancellationError() }
        try action(); committed = true
    }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return wasCancelled }
    func run(engine: URL, arguments: [String], progress: @escaping @Sendable (Double) -> Void = { _ in }) throws -> (Int32, Data) {
        let p = Process(); p.executableURL = engine; p.arguments = arguments
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe; p.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment; environment["LC_ALL"] = "en_US.UTF-8"; p.environment = environment
        // Serialize launch with cancellation so a cancelled job cannot launch later.
        lock.lock()
        if wasCancelled { lock.unlock(); throw CancellationError() }
        do { try p.run(); process = p; if isPaused { kill(p.processIdentifier, SIGSTOP) }; lock.unlock() } catch { lock.unlock(); throw error }
        var all = Data(); var pending = ""
        while true {
            let data = pipe.fileHandleForReading.availableData
            if data.isEmpty { break }
            all.append(data); pending += String(decoding: data, as: UTF8.self)
            let lines = pending.components(separatedBy: .newlines); pending = lines.last ?? ""
            for line in lines.dropLast() {
                if line.hasPrefix("#GUI#progress "), let n = Double(line.dropFirst(14).trimmingCharacters(in: CharacterSet(charactersIn: " %\r\n"))) { progress(min(1, max(0, n / 100))) }
            }
        }
        if pending.hasPrefix("#GUI#progress "), let n = Double(pending.dropFirst(14).trimmingCharacters(in: CharacterSet(charactersIn: " %\r\n"))) { progress(min(1, max(0, n / 100))) }
        p.waitUntilExit(); lock.lock(); process = nil; let cancelled = wasCancelled; lock.unlock()
        if cancelled { throw CancellationError() }; return (p.terminationStatus, all)
    }
}
enum Engine {
    static var candidates: [URL] {
        var paths: [String] = []
        if let root = ProcessInfo.processInfo.environment["MUXIE_BIN_DIR"] { paths.append((root as NSString).appendingPathComponent("mkvmerge")) }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("bin/mkvmerge").path { paths.append(bundled) }
        paths += ["/Applications/MKVToolNix.app/Contents/MacOS/mkvmerge", NSHomeDirectory() + "/Applications/MKVToolNix.app/Contents/MacOS/mkvmerge", "/opt/homebrew/bin/mkvmerge", "/usr/local/bin/mkvmerge"]
        return paths.map { URL(fileURLWithPath: $0) }
    }
    static var executable: URL? { candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) } }
    static func identify(_ url: URL, engine: URL, job: RunningJob = RunningJob()) throws -> Probe {
        let result = try job.run(engine: engine, arguments: ["--ui-language", "en_US", "-J", url.path])
        guard result.0 <= 1 else { throw MuxError.message("Cannot read \(url.lastPathComponent):\n" + String(decoding: result.1, as: UTF8.self)) }
        let probe = try JSONDecoder().decode(Probe.self, from: result.1)
        guard probe.container.recognized && probe.container.supported else { throw MuxError.message("Unsupported file: \(url.lastPathComponent)") }
        return probe
    }
    static func export(plan: ExportPlan, output: URL, engine: URL, job: RunningJob, progress: @escaping @Sendable (Double) -> Void) throws -> String? {
        let fm = FileManager.default
        let target = output.standardizedFileURL.resolvingSymlinksInPath()
        guard !plan.sources.contains(where: { $0.url.standardizedFileURL.resolvingSymlinksInPath() == target }) else { throw MuxError.message("The output cannot be a source file. Choose a different name.") }
        guard !fm.fileExists(atPath: output.path) else { throw MuxError.message("The output already exists. Choose a different name.") }
        let destination = output.deletingLastPathComponent()
        try ExportSpace.verifySpace(mode: .mux, plan: plan, destination: destination)
        let staging = output.deletingLastPathComponent().appendingPathComponent(".muxie-\(UUID().uuidString).partial.mkv")
        TempFileRegistry.register(staging)
        defer {
            TempFileRegistry.unregister(staging)
            try? fm.removeItem(at: staging)
        }
        let result = try job.run(engine: engine, arguments: plan.arguments(output: staging), progress: progress)
        guard result.0 <= 1 else { throw MuxError.message(String(decoding: result.1, as: UTF8.self)) }
        if job.cancelled { throw CancellationError() }
        let probe = try identify(staging, engine: engine, job: job)
        let expected = plan.orderedTracks
        guard probe.tracks.count == expected.count else { throw MuxError.message("Output track count verification failed. No output was saved.") }
        for (actual, wanted) in zip(probe.tracks, expected) {
            guard actual.type == wanted.kind && actual.codec == wanted.codec && (actual.properties.track_name ?? "") == wanted.name && (actual.properties.default_track ?? false) == wanted.isDefault && (actual.properties.forced_track ?? false) == wanted.isForced else { throw MuxError.message("Output track verification failed. No output was saved.") }
        }
        if job.cancelled { throw CancellationError() }
        try job.commit { try fm.moveItem(at: staging, to: output) }
        return result.0 == 1 ? String(decoding: result.1, as: UTF8.self) : nil
    }
}
