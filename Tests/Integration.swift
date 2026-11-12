// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import Foundation
import AppKit

final class ProgressWitness: @unchecked Sendable { let lock = NSLock(); private var seen = false; func mark() { lock.lock(); seen = true; lock.unlock() }; var value: Bool { lock.lock(); defer { lock.unlock() }; return seen } }

@main struct IntegrationTests {
    @MainActor static func main() async throws {
        let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
        guard let engine = Engine.executable else { fatalError("Bundled mkvmerge missing") }
        guard Engine.handbrakeExecutable != nil else { fatalError("Bundled HandBrakeCLI missing") }
        let fm = FileManager.default
        let run = fixture.appendingPathComponent("run-" + UUID().uuidString); try fm.createDirectory(at: run, withIntermediateDirectories: true)
        var results: [String] = []
        func check(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
            if !(try condition()) { throw MuxError.message("FAIL: " + name) }; results.append("PASS: " + name); print(results.last!)
        }
        let sourceFolder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/Muxie")
        let runtimeFiles = try fm.contentsOfDirectory(at: sourceFolder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        let runtimeText = try runtimeFiles.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
        // The track list must never scroll. The export queue popover (QueuePanel.swift) is a separate list and may.
        let trackScreenText = try runtimeFiles.filter { $0.lastPathComponent != "QueuePanel.swift" }.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
        try check(!runtimeText.unicodeScalars.contains(where: { (0x3400...0x9fff).contains($0.value) }) && !runtimeText.contains("chooseEngine") && !runtimeText.contains("enginePath") && !runtimeText.contains("sidebar"), "English-only runtime source, no sidebar or engine chooser")
        try check(!trackScreenText.contains("ScrollView") && !runtimeText.contains("glassProminent") && !runtimeText.contains("height * 0.70"), "No track scrolling, fractional clipping or saturated prominent buttons")
        let layoutSizes = (1...6).map { WorkspaceLayout.minimumContentHeight(rows: $0) }
        try check(zip(layoutSizes, layoutSizes.dropFirst()).allSatisfy { $1 - $0 == WorkspaceLayout.rowHeight + WorkspaceLayout.rowSpacing }, "Minimum height increases by exactly one complete row per track")
        let projectFolder = sourceFolder.deletingLastPathComponent().deletingLastPathComponent()
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: projectFolder.appendingPathComponent("Support/Info.plist")), format: nil) as? [String: Any] ?? [:]
        let feedURL = (plist["SUFeedURL"] as? String).flatMap(URL.init(string:))
        try check(feedURL?.scheme == "https" && (plist["SUPublicEDKey"] as? String)?.count == 44 && Int((plist["CFBundleVersion"] as? String) ?? "") != nil && plist["SUEnableAutomaticChecks"] as? Bool == false && plist["SUVerifyUpdateBeforeExtraction"] as? Bool == true, "Update settings: HTTPS feed, EdDSA public key, integer build, manual checks only, verify before extraction")
        try check(engine.path.hasSuffix("/bin/mkvmerge") && !engine.path.hasPrefix("/Applications/") && !engine.path.contains("/opt/homebrew"), "Bundled mkvmerge is preferred over any installed MKVToolNix")
        let video = fixture.appendingPathComponent("测试影片 sample.mp4")
        let original = try Data(contentsOf: video)
        let model = AppModel()
        await model.importFiles([video])
        try check(model.sources.count == 1 && model.tracks.count == 2, "MP4 import & video/audio identification")
        try check(model.enabled.map(\.kind) == ["video", "audio"] && model.selected == nil && model.canExport, "Opened video auto-checks its video and best audio with no focused row")
        try check(model.tracks.map { model.displayName(for: $0) } == ["Video", "Audio"] && model.tracks.allSatisfy { $0.name.isEmpty }, "Unnamed tracks use generic labels without writing metadata")
        for track in model.tracks { model.boolBinding(track.id, \.enabled).wrappedValue = true }
        let sizing = AppModel(); sizing.sources = model.sources; sizing.workspaceScreenHeight = 800
        var sizeChecks = true
        for count in 2...6 {
            sizing.tracks = (0..<count).map { index in var track = model.tracks[index % 2]; track.id = UUID(); return track }
            let before = sizing.minimumContentHeight
            sizing.queueJobs = [QueueJob(id: UUID(), sources: sizing.sources, tracks: [], mode: .mux, output: run.appendingPathComponent("layout-only.mkv"), state: .running(progress: 0.5), warning: nil)]
            sizeChecks = sizeChecks && sizing.pagedTracks.count == count && !sizing.reservesPagination && before == sizing.minimumContentHeight && before == WorkspaceLayout.minimumContentHeight(rows: count)
            sizing.queueJobs = []
        }
        try check(sizeChecks, "Two to six tracks fit without paging; export status never takes row space")
        sizing.tracks = (0..<24).map { index in var track = model.tracks[index % 2]; track.id = UUID(); return track }
        var pageIDs: [UUID] = []
        for page in 0..<sizing.pageCount { sizing.trackPage = page; pageIDs += sizing.pagedTracks.map(\.id) }
        try check(sizing.reservesPagination && Set(pageIDs).count == 24 && pageIDs.count == 24 && sizing.minimumContentHeight + WorkspaceLayout.chromeAllowance <= sizing.workspaceScreenHeight, "Screen-overflow uses complete non-scrolling pages without losing tracks")
        let remux = run.appendingPathComponent("MP4 转 MKV.mkv")
        await model.export(to: remux)
        try check(model.completed == remux && !model.showError, "MP4 to MKV export & track validation")
        await model.importFiles([fixture.appendingPathComponent("国语音轨.m4a"), fixture.appendingPathComponent("简体中文.srt"), fixture.appendingPathComponent("English.srt")])
        try check(model.sources.count == 4 && model.tracks.count == 5, "Add separate audio & SRT subtitles")
        let additionalIDs = Set(model.sources.dropFirst().map(\.id))
        try check(model.tracks.filter { additionalIDs.contains($0.sourceID) }.allSatisfy { !$0.enabled } && model.selected == nil, "Added audio and subtitle tracks also remain unchecked and unfocused")
        try check(model.tracks.filter { $0.kind == "audio" }.map { model.displayName(for: $0) } == ["Audio 1", "Audio 2"], "Audio numbering is per type, not container track ID")
        for track in model.tracks { model.boolBinding(track.id, \.enabled).wrappedValue = true }
        model.filter = "Audio"
        let audioFiltered = model.filtered.count == 2 && model.filtered.allSatisfy { $0.kind == "audio" }
        model.filter = "Subtitles"
        try check(audioFiltered && model.filtered.count == 2 && model.filtered.allSatisfy { $0.kind == "subtitles" }, "English audio and subtitle filters")
        model.filter = "All"
        for track in model.tracks {
            if track.kind == "audio" { model.binding(track.id, \.name).wrappedValue = track.sourceID == model.sources[0].id ? "English · Original" : "国语 ‘配音’ & Stereo"; model.binding(track.id, \.language).wrappedValue = track.sourceID == model.sources[0].id ? "en" : "zh" }
            if track.kind == "subtitles" { model.binding(track.id, \.name).wrappedValue = track.sourceID == model.sources[2].id ? "简体中文 / SRT" : "English"; model.binding(track.id, \.language).wrappedValue = track.sourceID == model.sources[2].id ? "zh-Hans" : "en" }
        }
        let chinese = model.tracks.first { $0.sourceID == model.sources[2].id }!
        model.boolBinding(chinese.id, \.isDefault).wrappedValue = true
        let merged = run.appendingPathComponent("多音轨 & 中文字幕.mkv")
        await model.export(to: merged)
        let probe = try Engine.identify(merged, engine: engine)
        try check(probe.tracks.count == 5 && probe.tracks.filter { $0.type == "audio" }.count == 2 && probe.tracks.filter { $0.type == "subtitles" }.count == 2, "Mux two selectable audio tracks & two subtitles")
        try check(probe.tracks[2].properties.track_name == "国语 ‘配音’ & Stereo" && probe.tracks[3].properties.track_name == "简体中文 / SRT" && probe.tracks[3].properties.language_ietf == "zh-Hans" && probe.tracks[3].properties.default_track == true, "Unicode names, language & default flag persisted")
        let englishSub = model.tracks.last!
        model.intBinding(englishSub.id, \.delayMs).wrappedValue = 750
        let delayed = run.appendingPathComponent("subtitle-delay.mkv")
        await model.export(to: delayed)
        let delayedPlan = ExportPlan(sources: model.sources, tracks: model.tracks.filter(\.enabled))
        try check(delayedPlan.arguments(output: delayed).contains("--sync") && delayedPlan.arguments(output: delayed).contains { $0.hasSuffix(":750") }, "Subtitle delay passes mkvmerge --sync")
        let originalAudio = model.tracks.first { $0.kind == "audio" }!
        model.boolBinding(originalAudio.id, \.enabled).wrappedValue = false
        let english = model.tracks.last!
        model.boolBinding(english.id, \.enabled).wrappedValue = false
        let reduced = run.appendingPathComponent("移除音轨和字幕.mkv")
        await model.export(to: reduced)
        let reducedProbe = try Engine.identify(reduced, engine: engine)
        try check(reducedProbe.tracks.count == 3 && reducedProbe.tracks.filter { $0.type == "audio" }.count == 1 && reducedProbe.tracks.filter { $0.type == "subtitles" }.count == 1, "Exclude unwanted audio & subtitle tracks")
        let before = try Data(contentsOf: reduced)
        await model.export(to: reduced)
        try check(model.showError && (try? Data(contentsOf: reduced)) == before, "Existing output is never overwritten")
        model.showError = false
        await model.export(to: video)
        try check(model.showError && (try? Data(contentsOf: video)) == original, "Source overwrite rejected & original untouched")
        let cancelled = RunningJob(); cancelled.cancel(); let cancelledURL = run.appendingPathComponent("cancelled.mkv")
        do { _ = try Engine.export(plan: ExportPlan(sources: model.sources, tracks: model.tracks), output: cancelledURL, engine: engine, job: cancelled, progress: { _ in }); throw MuxError.message("Cancellation ignored") } catch is CancellationError { }
        try check(!fm.fileExists(atPath: cancelledURL.path) && !(try fm.contentsOfDirectory(atPath: run.path)).contains(where: { $0.contains("partial") }), "Cancellation removes partial output")
        let secondary = AppModel(); await secondary.importFiles([merged]);
        let sourceTracks = secondary.tracks.filter { $0.kind != "video" }
        for track in sourceTracks { secondary.boolBinding(track.id, \.enabled).wrappedValue = false }
        for track in secondary.tracks where track.kind == "video" { secondary.boolBinding(track.id, \.enabled).wrappedValue = true }
        let silent = run.appendingPathComponent("仅视频.mkv"); await secondary.export(to: silent)
        let silentProbe = try Engine.identify(silent, engine: engine)
        try check(silentProbe.tracks.count == 1 && silentProbe.tracks[0].type == "video", "Remove all audio/subtitles from existing MKV")
        let bad = AppModel(); await bad.importFiles([fixture.appendingPathComponent("English.srt")])
        try check(bad.sources.isEmpty && bad.showError, "Subtitle cannot accidentally become primary movie")
        let activeCancel = RunningJob(); let witness = ProgressWitness(); let activeCancelURL = run.appendingPathComponent("active-cancel.mkv")
        do {
            _ = try Engine.export(plan: ExportPlan(sources: model.sources, tracks: model.tracks), output: activeCancelURL, engine: engine, job: activeCancel) { _ in witness.mark(); activeCancel.cancel() }
            throw MuxError.message("Active cancellation ignored")
        } catch is CancellationError { }
        try check(witness.value && !fm.fileExists(atPath: activeCancelURL.path), "GUI percent progress parsed & active cancellation honoured")
        let noVideo = model.tracks.filter { $0.kind == "video" }
        for track in noVideo { model.boolBinding(track.id, \.enabled).wrappedValue = false }
        try check(!model.canExport, "Export disabled when all video tracks excluded")
        try check((try Data(contentsOf: video)) == original, "Input bytes unchanged after all tests")
        // Fresh model: the checks above leave the video track unchecked on `model`.
        let compressModel = AppModel()
        await compressModel.importFiles([video, fixture.appendingPathComponent("English.srt")])
        for track in compressModel.tracks { compressModel.boolBinding(track.id, \.enabled).wrappedValue = true }
        try check(compressModel.compressEligible && compressModel.canExport, "Compress is available for an H.264 source")
        compressModel.exportMode = .compress
        let compressedURL = run.appendingPathComponent("H.265 compress.mkv")
        await compressModel.export(to: compressedURL)
        if !fm.fileExists(atPath: compressedURL.path) { throw MuxError.message("Compress failed: " + (compressModel.error ?? "no error reported")) }
        try check(fm.fileExists(atPath: compressedURL.path), "Compress produces an output file")
        let compressedProbe = try Engine.identify(compressedURL, engine: engine)
        let cv = compressedProbe.tracks.first { $0.type == "video" }!
        try check((cv.codec.uppercased().contains("HEVC") || cv.codec.uppercased().contains("H.265")) && (cv.properties.pixel_dimensions.flatMap { Int($0.split(separator: "x").last ?? "") } ?? 9999) <= 1080, "Compress: HEVC output within 1080p")
        try check(Engine.hevcBitDepth(fromCodecPrivate: cv.properties.codec_private_data) == 10, "Compress: HEVC 10-bit output")
        try check(compressedProbe.tracks.filter { $0.type == "audio" }.allSatisfy { $0.codec.uppercased().contains("AAC") }, "Compress: audio is AAC")
        try check(compressedProbe.tracks.filter { $0.type == "subtitles" }.count == 1, "Compress: subtitle track kept")
        try check(Engine.hevcBitDepth(fromCodecPrivate: "0102" + String(repeating: "00", count: 15) + "FAFA") == 10 && Engine.hevcBitDepth(fromCodecPrivate: "0101" + String(repeating: "00", count: 15) + "F8F8") == 8 && Engine.hevcBitDepth(fromCodecPrivate: nil) == nil && Engine.hevcBitDepth(fromCodecPrivate: "01") == nil, "HEVC bit depth is read from codec private data")
        // The file just produced is HEVC 10-bit <= 1080p, so compressing it again must not be offered.
        let again = AppModel()
        await again.importFiles([compressedURL])
        for track in again.tracks where track.kind == "video" { again.boolBinding(track.id, \.enabled).wrappedValue = true }
        again.refreshCompressEligibility()
        try check(!again.compressEligible, "Compress is not offered for HEVC 10-bit video at or below 1080p")
        // Every audio track unchecked: a video-only compressed output is valid, not a verification failure.
        let silentCompress = AppModel()
        await silentCompress.importFiles([video])
        for track in silentCompress.tracks { silentCompress.boolBinding(track.id, \.enabled).wrappedValue = track.kind == "video" }
        silentCompress.exportMode = .compress
        let silentCompressURL = run.appendingPathComponent("H.265 compress no audio.mkv")
        await silentCompress.export(to: silentCompressURL)
        if !fm.fileExists(atPath: silentCompressURL.path) { throw MuxError.message("Compress without audio failed: " + (silentCompress.error ?? "no error reported")) }
        try check(try Engine.identify(silentCompressURL, engine: engine).tracks.filter { $0.type == "audio" }.isEmpty, "Compress accepts a project with no audio tracks")
        // Black bars stay: HandBrake's default auto-crop would turn 1920x1080 into 1920x800.
        let letterboxModel = AppModel()
        await letterboxModel.importFiles([fixture.appendingPathComponent("letterbox.mkv")])
        for track in letterboxModel.tracks { letterboxModel.boolBinding(track.id, \.enabled).wrappedValue = true }
        letterboxModel.exportMode = .compress
        let letterboxURL = run.appendingPathComponent("letterbox compress.mkv")
        await letterboxModel.export(to: letterboxURL)
        if !fm.fileExists(atPath: letterboxURL.path) { throw MuxError.message("Letterbox compress failed: " + (letterboxModel.error ?? "no error reported")) }
        let letterboxDims = try Engine.identify(letterboxURL, engine: engine).tracks.first { $0.type == "video" }?.properties.pixel_dimensions
        try check(letterboxDims == "1920x1080", "Compress keeps black bars (no auto-crop), got \(letterboxDims ?? "nil")")
        // 4K HDR10 stays 4K HDR10: BT.2020 primaries, PQ transfer, MaxCLL.
        let hdrModel = AppModel()
        await hdrModel.importFiles([fixture.appendingPathComponent("hdr10-4k.mkv")])
        for track in hdrModel.tracks { hdrModel.boolBinding(track.id, \.enabled).wrappedValue = true }
        try check(hdrModel.tracks.first(where: { $0.kind == "video" })?.hdrBadge == .hdr10, "HDR10 badge on import")
        let dvP8 = "0000000000" + "64766343" + "010011" + "00"
        let dvP5 = "64767643" + "0100" + "0a" + "00"
        try check(VideoHDR.badge(transfer: nil, codecPrivateHex: dvP8) == .dolbyVision, "DV badge from dvcC")
        try check(VideoHDR.dolbyVisionProfile(codecPrivateHex: dvP8) == 8, "dvcC profile 8")
        try check(VideoHDR.dolbyVisionProfile(codecPrivateHex: dvP5) == 5, "dvvC profile 5")
        // HandBrake keeps Profile 5 and 8 as they are; only Profile 7 is changed (converted to 8.1), so only it warns.
        try check(VideoHDR.compressExportWarning(badges: [.dolbyVision], encoder: .software, dolbyVisionProfiles: [5]) == nil, "DV P5 needs no warning (HandBrake keeps it)")
        try check(VideoHDR.compressExportWarning(badges: [.dolbyVision], encoder: .hardware, dolbyVisionProfiles: [7])?.contains("Profile 7") == true, "DV P7 warning")
        try check(VideoHDR.compressExportWarning(badges: [.hdr10], encoder: .software) == nil, "Plain HDR10 needs no warning")
        // The container record mkvmerge -J does not report: Matroska BlockAdditionMapping, and an MP4 box.
        let mkvDV = Data([0x00, 0x41, 0xE7, 0x84] + Array("dvvC".utf8) + [0x41, 0xED, 0x98, 0x01, 0x00, 0x10, 0x1d] + Array(repeating: 0, count: 20))
        let mp4DV = Data([0x00, 0x00, 0x00, 0x20] + Array("dvcC".utf8) + [0x01, 0x00, 0x0a, 0x3f] + Array(repeating: 0, count: 20))
        try check(VideoHDR.dolbyVisionProfile(containerBytes: mkvDV) == 8, "DV profile 8 from a Matroska BlockAdditionMapping")
        try check(VideoHDR.dolbyVisionProfile(containerBytes: mp4DV) == 5, "DV profile 5 from an MP4 dvcC box")
        try check(VideoHDR.dolbyVisionProfile(fileURL: fixture.appendingPathComponent("hdr10-4k.mkv")) == nil, "No DV found in a plain HDR10 file")
        try check(hdrModel.compressEligible, "Compress is offered for a 4K HEVC source")
        hdrModel.exportMode = .compress
        let hdrURL = run.appendingPathComponent("hdr compress.mkv")
        await hdrModel.export(to: hdrURL)
        if !fm.fileExists(atPath: hdrURL.path) { throw MuxError.message("HDR compress failed: " + (hdrModel.error ?? "no error reported")) }
        let hdrProps = try Engine.identify(hdrURL, engine: engine).tracks.first { $0.type == "video" }?.properties
        try check(hdrProps?.pixel_dimensions == "3840x2160" && hdrProps?.color_primaries == 9 && hdrProps?.color_transfer_characteristics == 16 && hdrProps?.max_content_light == 1000, "Compress keeps 4K HDR10 (BT.2020, PQ, MaxCLL)")
        let compressCancelURL = run.appendingPathComponent("compress-cancelled.mkv")
        let compressJob = RunningJob()
        let compressWitness = ProgressWitness()
        do {
            _ = try Engine.exportCompressed(plan: ExportPlan(sources: compressModel.sources, tracks: compressModel.tracks), output: compressCancelURL, mkvmerge: engine, handbrake: Engine.handbrakeExecutable!, job: compressJob) { _ in compressWitness.mark(); compressJob.cancel() }
            throw MuxError.message("Compress cancellation ignored")
        } catch is CancellationError { }
        try check(compressWitness.value && !fm.fileExists(atPath: compressCancelURL.path), "Compress cancellation removes partial output")
        try check(CompressProfile(height: 1080).quality == 65 && CompressProfile(height: 2160).quality == 60 && CompressProfile(height: 2160).maxWidth == 3840, "Compress profile table")
        try check(ExportMode.mux.label == "Mux" && ExportMode.compress.label == "Compress", "Export mode labels Mux and Compress")
        try check(
            CompressSettings.audioBitrateKbps(channelCount: 1) == 96
                && CompressSettings.audioBitrateKbps(channelCount: 2) == 192
                && CompressSettings.audioBitrateKbps(channelCount: 6) == 384
                && CompressSettings.audioBitrateKbps(channelCount: 8) == 384,
            "Audio channel-count to bitrate table"
        )
        try check(CompressSettings.encodedChannelCount(sourceChannels: 8) == 6, "7.1 and above cap at 5.1 for AAC")
        let spaceSource = MediaSource(id: UUID(), url: video, container: "MP4", byteSize: 10_000_000)
        // The track must belong to this source and be checked; `model`'s tracks belong to another source and are unchecked here.
        let spaceTrack = MediaTrack(sourceID: spaceSource.id, trackID: 0, kind: "video", codec: "AVC", name: "", language: "und", isDefault: false, isForced: false, enabled: true, detail: "")
        let spacePlan = ExportPlan(sources: [spaceSource], tracks: [spaceTrack])
        try check(ExportSpace.requiredBytes(mode: .mux, plan: spacePlan) == 10_000_000, "Mux space estimate equals checked input bytes")
        try check(ExportSpace.requiredBytes(mode: .compress, plan: spacePlan) == 10_000_000 + 5_000_000 + 2_000_000, "Compress space estimate includes temp staging, remux and conservative output")
        let spaceMsg = ExportSpace.spaceErrorMessage(required: 40_000_000_000, available: 21_000_000_000)
        try check(spaceMsg.contains("40") && spaceMsg.contains("21") && spaceMsg.contains("free on this disk"), "Space failure message format")
        var sleepBegan = 0, sleepEnded = 0
        let defaultSleepProvider = IdleSleepActivity.provider
        IdleSleepActivity.provider = { _ in sleepBegan += 1; return { sleepEnded += 1 } }
        IdleSleepActivity.begin(); IdleSleepActivity.end()
        try check(sleepBegan == 1 && sleepEnded == 1, "Idle sleep activity begins once and ends on release")
        IdleSleepActivity.provider = defaultSleepProvider
        let registryDir = run.appendingPathComponent("app-support", isDirectory: true)
        try fm.createDirectory(at: registryDir, withIntermediateDirectories: true)
        setenv("MUXIE_APP_SUPPORT", registryDir.path, 1)
        let stalePartial = registryDir.appendingPathComponent(".muxie-remux-deadbeef.partial.mkv")
        try Data(repeating: 1, count: 32).write(to: stalePartial)
        TempFileRegistry.replaceAll([TempFileRecord(path: stalePartial.path, pid: 2_000_000_001)])
        TempFileRegistry.cleanupStale()
        try check(!fm.fileExists(atPath: stalePartial.path) && TempFileRegistry.load().isEmpty, "Stale temp registry entry removes matching partial when PID is dead")
        let livePartial = registryDir.appendingPathComponent(".muxie-compress-live.partial.mkv")
        try Data(repeating: 2, count: 16).write(to: livePartial)
        TempFileRegistry.replaceAll([TempFileRecord(path: livePartial.path, pid: ProcessInfo.processInfo.processIdentifier)])
        TempFileRegistry.cleanupStale()
        try check(fm.fileExists(atPath: livePartial.path) && TempFileRegistry.load().count == 1, "Live PID temp entry is not removed")
        let otherFile = registryDir.appendingPathComponent("not-managed.mkv")
        try Data("x".utf8).write(to: otherFile)
        TempFileRegistry.replaceAll([TempFileRecord(path: otherFile.path, pid: 2_000_000_002)])
        TempFileRegistry.cleanupStale()
        try check(fm.fileExists(atPath: otherFile.path), "Non-matching temp file name is never deleted")
        try? fm.removeItem(at: livePartial)
        try? fm.removeItem(at: otherFile)
        TempFileRegistry.replaceAll([])
        let dualAudioModel = AppModel()
        await dualAudioModel.importFiles([fixture.appendingPathComponent("dual-audio.mp4")])
        for track in dualAudioModel.tracks { dualAudioModel.boolBinding(track.id, \.enabled).wrappedValue = true }
        dualAudioModel.exportMode = .compress
        let dualOut = run.appendingPathComponent("dual-audio-compress.mkv")
        await dualAudioModel.export(to: dualOut)
        if !fm.fileExists(atPath: dualOut.path) { throw MuxError.message("Dual-audio compress failed: " + (dualAudioModel.error ?? "no error")) }
        let dualProbe = try Engine.identify(dualOut, engine: engine)
        let dualAudios = dualProbe.tracks.filter { $0.type == "audio" }.sorted { ($0.properties.audio_channels ?? 0) < ($1.properties.audio_channels ?? 0) }
        try check(dualAudios.count == 2 && dualAudios[0].properties.audio_channels == 2 && dualAudios[1].properties.audio_channels == 6,
            "Compress dual audio: AAC 2-channel and 6-channel tracks")
        try check(dualAudios.allSatisfy { $0.codec.uppercased().contains("AAC") }, "Compress dual audio: both tracks are AAC")
        // AAC sources are copied, not re-encoded: the packets of each output track equal the source's.
        func audioMD5(_ url: URL, _ index: Int) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FFMPEG"] ?? "/opt/homebrew/bin/ffmpeg")
            // -nostdin and a null stdin: ffmpeg otherwise reads the terminal and gets suspended.
            process.arguments = ["-nostdin", "-v", "error", "-i", url.path, "-map", "0:a:\(index)", "-c", "copy", "-f", "md5", "-"]
            let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice; process.standardInput = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let dualSource = fixture.appendingPathComponent("dual-audio.mp4")
        let md5Source0 = try audioMD5(dualSource, 0), md5Source1 = try audioMD5(dualSource, 1)
        try check(md5Source0.hasPrefix("MD5=") && md5Source0 == (try audioMD5(dualOut, 0)) && md5Source1 == (try audioMD5(dualOut, 1)), "AAC sources are copied bit for bit")
        // A non-AAC source (AC-3 5.1) is still re-encoded to AAC and keeps its six channels.
        let ac3Model = AppModel()
        await ac3Model.importFiles([fixture.appendingPathComponent("ac3-51.mkv")])
        for track in ac3Model.tracks { ac3Model.boolBinding(track.id, \.enabled).wrappedValue = true }
        ac3Model.exportMode = .compress
        let ac3Out = run.appendingPathComponent("ac3 compress.mkv")
        await ac3Model.export(to: ac3Out)
        if !fm.fileExists(atPath: ac3Out.path) { throw MuxError.message("AC-3 compress failed: " + (ac3Model.error ?? "no error reported")) }
        let ac3Audio = try Engine.identify(ac3Out, engine: engine).tracks.filter { $0.type == "audio" }
        try check(ac3Audio.count == 1 && ac3Audio[0].codec.uppercased().contains("AAC") && ac3Audio[0].properties.audio_channels == 6, "AC-3 5.1 source is re-encoded to AAC 5.1")
        // A delay on a re-encoded track must survive Compress (it is applied in the remux that feeds HandBrake).
        let delayModel = AppModel()
        await delayModel.importFiles([fixture.appendingPathComponent("ac3-51.mkv")])
        for track in delayModel.tracks { delayModel.boolBinding(track.id, \.enabled).wrappedValue = true }
        for track in delayModel.tracks where track.kind == "audio" { delayModel.intBinding(track.id, \.delayMs).wrappedValue = 1000 }
        delayModel.exportMode = .compress
        let delayOut = run.appendingPathComponent("ac3 delay compress.mkv")
        await delayModel.export(to: delayOut)
        let delayStart = try Engine.identify(delayOut, engine: engine).tracks.first { $0.type == "audio" }?.properties.minimum_timestamp ?? 0
        try check(abs(delayStart - 1_000_000_000) < 50_000_000, "Compress keeps a +1000 ms delay on a re-encoded audio track (got \(delayStart / 1_000_000) ms)")
        // Argument list: per-track encoders, mixdowns and bitrates in order; AAC above 5.1 is encoded (to 5.1), not copied.
        let hbArgs = Engine.handbrakeArguments(input: URL(fileURLWithPath: "/in.mkv"), output: URL(fileURLWithPath: "/out.mkv"), profile: CompressProfile(height: 1080), sourceAudioChannels: [2, 6, 8, 6], sourceAudioIsAAC: [true, false, false, true])
        func hbValue(_ flag: String) -> String? { hbArgs.firstIndex(of: flag).map { hbArgs[$0 + 1] } }
        try check(hbValue("--aencoder") == "copy:aac,av_aac,av_aac,copy:aac" && hbValue("--ab") == "192,384,384,384" && hbValue("--mixdown") == "stereo,none,5point1,none" && hbValue("--audio-fallback") == "av_aac", "Compress audio arguments: copy AAC, encode the rest, 7.1 at 384 kbps as 5.1")
        try check(hbArgs.contains("vt_h265_10bit") && hbArgs.contains("--subtitle") && hbValue("--subtitle") == "none" && !hbArgs.contains("--encopts") && hbValue("--encoder-preset") == "quality" && hbValue("--enable-hw-decoding") == "videotoolbox", "Compress video arguments use VideoToolbox H.265 10-bit with hardware decoding, without x265 options")
        let parsed = Engine.parseHandBrakeEncodingLine("Encoding: task 1 of 1, 12.50 % (120.5 fps, avg 118.2 fps, ETA 00h05m30s)")
        try check(parsed?.percent == 12.5 && parsed?.avgFPS == 118.2 && parsed?.etaSeconds == 330, "HandBrake encoding line parser")
        // HandBrake output is read as bytes: progress lines end in \r, arrive split anywhere, and only the newest one per chunk matters.
        func pct(_ line: String?) -> Double? { line.flatMap { Engine.parseHandBrakeEncodingLine($0)?.percent } }
        var scan = HandBrakeProgressScanner()
        try check(scan.feed(Data("Encoding: task 1 of 1, 10.00 % (5.0 fps, avg 5.0 fps, ETA 00h01m00s)".utf8)) == nil, "Progress scanner waits for the end of a line")
        try check(pct(scan.feed(Data("\rEncoding: task 1 of 1, 11.00 % (5.0 fps, avg 5.0 fps, ETA 00h01m00s)\r".utf8))) == 11, "Progress scanner returns the newest line of a chunk")
        try check(scan.feed(Data("Encoding: task 1 of 1, 12.".utf8)) == nil && pct(scan.feed(Data("50 % (5.0 fps, avg 5.0 fps, ETA 00h01m00s)\n".utf8))) == 12.5, "Progress scanner joins a line split between chunks")
        try check(scan.feed(Data("x265 [info]: frame I:1\nscan: done\n".utf8)) == nil, "Progress scanner ignores other output")
        _ = scan.feed(Data("Encoding: task 1 of 1, 99.00 % (5.0 fps, avg 5.0 fps, ETA 00h00m01s)".utf8))
        try check(pct(scan.finish()) == 99, "Progress scanner returns an unfinished last line at the end")
        let tail = LogTailBuffer(limit: 1_000)
        tail.append(Data(String(repeating: "a", count: 50_000).utf8)); tail.append(Data("女".utf8.prefix(1))); tail.append(Data("女".utf8.dropFirst())); tail.append(Data("性END".utf8))
        try check(tail.text.hasSuffix("女性END") && tail.text.utf8.count <= 1_000, "Log tail keeps the last bytes and a character split between chunks")
        let persisted = QueueJob.snapshot(sources: model.sources, tracks: model.tracks, mode: .mux, output: run.appendingPathComponent("persisted.mkv"))
        var store = PersistedQueue(jobs: [PersistedQueueJob(job: persisted, wasInterrupted: true)], hold: true, resumePending: true)
        let encodeData = try JSONEncoder().encode(store)
        store = try JSONDecoder().decode(PersistedQueue.self, from: encodeData)
        try check(store.jobs.first?.job.output.lastPathComponent == "persisted.mkv" && store.hold && store.resumePending, "Queue persistence roundtrip")
        let swArgs = Engine.handbrakeArguments(input: URL(fileURLWithPath: "/in.mkv"), output: URL(fileURLWithPath: "/out.mkv"), profile: CompressProfile(height: 2160), encoder: .software, sourceAudioChannels: [2], sourceAudioIsAAC: [true])
        func swValue(_ flag: String) -> String? { swArgs.firstIndex(of: flag).map { swArgs[$0 + 1] } }
        try check(swValue("--encoder") == "x265_10bit" && swValue("--encoder-preset") == "medium" && swValue("--quality") == "23" && swValue("--encopts") == "aq-mode=3:no-sao=1" && swValue("--encoder-profile") == "main10" && !swArgs.contains("--enable-hw-decoding"), "Software encoder uses x265 10-bit with the RF scale and software decoding")
        func enqueueEnabled(_ model: AppModel, output: URL) {
            for track in model.tracks { model.boolBinding(track.id, \.enabled).wrappedValue = true }
            model.enqueueExport(to: output)
        }
        let queueA = AppModel()
        let queueOut1 = run.appendingPathComponent("queue-mux-1.mkv")
        let queueOut2 = run.appendingPathComponent("queue-mux-2.mkv")
        await queueA.importFiles([video])
        enqueueEnabled(queueA, output: queueOut1)
        await queueA.importFiles([video])
        enqueueEnabled(queueA, output: queueOut2)
        await queueA.waitForQueueIdle()
        try check(fm.fileExists(atPath: queueOut1.path) && fm.fileExists(atPath: queueOut2.path), "Two queued Mux jobs finish in order with valid outputs")
        try check((try Data(contentsOf: video)) == original, "Inputs unchanged after queued mux exports")
        let modeQueue = AppModel()
        await modeQueue.importFiles([video, fixture.appendingPathComponent("English.srt")])
        for track in modeQueue.tracks { modeQueue.boolBinding(track.id, \.enabled).wrappedValue = true }
        modeQueue.exportMode = .compress
        modeQueue.enqueueExport(to: run.appendingPathComponent("queue-compress.mkv"))
        await modeQueue.importFiles([video])
        enqueueEnabled(modeQueue, output: run.appendingPathComponent("queue-after-compress.mkv"))
        await modeQueue.waitForQueueIdle()
        let compressedQueued = try Engine.identify(run.appendingPathComponent("queue-compress.mkv"), engine: engine)
        try check(compressedQueued.tracks.first { $0.type == "video" }!.codec.uppercased().contains("HEVC"), "Queued compress job uses Compress mode")
        let muxQueued = try Engine.identify(run.appendingPathComponent("queue-after-compress.mkv"), engine: engine)
        try check(muxQueued.tracks.first { $0.type == "video" }!.codec.uppercased().contains("AVC"), "Following queued job uses Mux mode")
        // A queued job keeps the encoder it was queued with, even if the toolbar toggle changes before it runs.
        let savedEncoder = CompressEncoder.current
        CompressEncoder.current = .software
        let encQueue = AppModel()
        await encQueue.importFiles([video])
        for track in encQueue.tracks { encQueue.boolBinding(track.id, \.enabled).wrappedValue = true }
        encQueue.exportMode = .compress
        let encOut = run.appendingPathComponent("queue-encoder-kept.mkv")
        encQueue.enqueueExport(to: encOut)
        CompressEncoder.current = .hardware
        await encQueue.waitForQueueIdle()
        CompressEncoder.current = savedEncoder
        let encBytes = try Data(contentsOf: encOut)
        // x265 writes its version banner ("x265 (build ...") into an SEI message; VideoToolbox output carries none.
        try check(encQueue.queueJobs.first?.encoder == .software && encBytes.range(of: Data("x265 (build".utf8)) != nil, "Queued compress job uses the encoder chosen at enqueue time")
        let failPath = run.appendingPathComponent("queue-fail.mkv")
        try Data("existing".utf8).write(to: failPath)
        let failQueue = AppModel()
        await failQueue.importFiles([video])
        enqueueEnabled(failQueue, output: failPath)
        await failQueue.importFiles([video])
        enqueueEnabled(failQueue, output: run.appendingPathComponent("queue-continue.mkv"))
        await failQueue.waitForQueueIdle()
        try check(failQueue.queueJobs.contains { if case .failed = $0.state { return true }; return false } && fm.fileExists(atPath: run.appendingPathComponent("queue-continue.mkv").path), "A failed queued job does not block the next job")
        let snap = AppModel()
        await snap.importFiles([video, fixture.appendingPathComponent("国语音轨.m4a")])
        for track in snap.tracks { snap.boolBinding(track.id, \.enabled).wrappedValue = true }
        let audioTrack = snap.tracks.first { $0.kind == "audio" }!
        snap.binding(audioTrack.id, \.name).wrappedValue = "Queued Snapshot"
        snap.enqueueExport(to: run.appendingPathComponent("queue-snap-1.mkv"))
        await snap.importFiles([video, fixture.appendingPathComponent("国语音轨.m4a")])
        for track in snap.tracks { snap.boolBinding(track.id, \.enabled).wrappedValue = true }
        let audioAgain = snap.tracks.first { $0.kind == "audio" }!
        snap.binding(audioAgain.id, \.name).wrappedValue = "After Enqueue Edit"
        snap.enqueueExport(to: run.appendingPathComponent("queue-snap-2.mkv"))
        await snap.waitForQueueIdle()
        let snap1 = try Engine.identify(run.appendingPathComponent("queue-snap-1.mkv"), engine: engine)
        try check(snap1.tracks.first { $0.type == "audio" }?.properties.track_name == "Queued Snapshot", "Queued job keeps track plan from enqueue time")
        let dup = AppModel()
        await dup.importFiles([video])
        let dupPath = run.appendingPathComponent("queue-dup.mkv")
        enqueueEnabled(dup, output: dupPath)
        await dup.importFiles([video])
        enqueueEnabled(dup, output: dupPath)
        try check(dup.showError && dup.queueJobs.filter { $0.output == dupPath && $0.isPending }.count <= 1, "Duplicate queued output path is refused")
        let removeQueued = AppModel()
        await removeQueued.importFiles([video])
        enqueueEnabled(removeQueued, output: run.appendingPathComponent("queue-remove-a.mkv"))
        await removeQueued.importFiles([video])
        enqueueEnabled(removeQueued, output: run.appendingPathComponent("queue-remove-b.mkv"))
        if let queued = removeQueued.queueJobs.first(where: { $0.output.lastPathComponent == "queue-remove-b.mkv" && $0.state == .queued }) {
            removeQueued.removeQueueJob(queued.id)
        }
        await removeQueued.waitForQueueIdle()
        try check(fm.fileExists(atPath: run.appendingPathComponent("queue-remove-a.mkv").path) && !fm.fileExists(atPath: run.appendingPathComponent("queue-remove-b.mkv").path), "Removing a queued job prevents it from running")
        // Blu-ray main title keeps its audio. mkvmerge lists only the video track when it is given a playlist, so the
        // clips named by the main playlist are used instead (a real disc: 1 video, TrueHD, AC-3 and 3 PGS in 00000.m2ts).
        func mpls(_ items: [(String, Int, Int)], padTo: Int = 0) -> Data {
            func be32(_ v: Int) -> [UInt8] { [UInt8((v >> 24) & 255), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)] }
            func be16(_ v: Int) -> [UInt8] { [UInt8((v >> 8) & 255), UInt8(v & 255)] }
            var d = Data("MPLS0200".utf8)
            d.append(contentsOf: be32(40)); d.append(Data(repeating: 0, count: 28))
            d.append(contentsOf: be32(0)); d.append(contentsOf: be16(0)); d.append(contentsOf: be16(items.count)); d.append(contentsOf: be16(0))
            for (clip, inTime, outTime) in items {
                d.append(contentsOf: be16(20)); d.append(Data(clip.utf8)); d.append(Data("M2TS".utf8)); d.append(contentsOf: [0, 1, 0])
                d.append(contentsOf: be32(inTime)); d.append(contentsOf: be32(outTime))
            }
            if padTo > d.count { d.append(Data(repeating: 0, count: padTo - d.count)) }
            return d
        }
        let discRoot = fixture.appendingPathComponent("bdmv-audio-fixture")
        let discPlaylists = discRoot.appendingPathComponent("BDMV/PLAYLIST", isDirectory: true)
        let discStreams = discRoot.appendingPathComponent("BDMV/STREAM", isDirectory: true)
        try fm.createDirectory(at: discPlaylists, withIntermediateDirectories: true)
        try fm.createDirectory(at: discStreams, withIntermediateDirectories: true)
        for n in 0...1 { try fm.copyItem(at: fixture.appendingPathComponent("clip\(n).m2ts"), to: discStreams.appendingPathComponent("0000\(n).m2ts")) }
        // Main title: two clips, 4 s, a tiny file. Decoy: one clip, 1 s, padded to a bigger file.
        try mpls([("00000", 0, 90_000), ("00001", 0, 90_000)]).write(to: discPlaylists.appendingPathComponent("00001.mpls"))
        try mpls([("00001", 0, 45_000)], padTo: 4096).write(to: discPlaylists.appendingPathComponent("00002.mpls"))
        try check(BluRayISO.parsePlayItems(try Data(contentsOf: discPlaylists.appendingPathComponent("00001.mpls"))) == [BluRayISO.PlayItem(clip: "00000", seconds: 2), BluRayISO.PlayItem(clip: "00001", seconds: 2)], "Playlist parser reads clip names and running time")
        let discClips = try BluRayISO.mainClips(under: discRoot)
        try check(discClips.map(\.lastPathComponent) == ["00000.m2ts", "00001.m2ts"], "Blu-ray main title is the longest-running playlist, not the biggest file")
        let discProbe = try Engine.identify(discClips[0], engine: engine)
        try check(discProbe.tracks.contains { $0.type == "video" } && discProbe.tracks.contains { $0.type == "audio" }, "Blu-ray main title clip lists its audio track")
        let discSourceID = UUID()
        let discSource = MediaSource(id: discSourceID, url: discClips[0], container: "MPEG-TS", byteSize: 1_000_000, appendedParts: Array(discClips.dropFirst()))
        let discTracks = discProbe.tracks.filter { ["video", "audio"].contains($0.type) }.map { MediaTrack(sourceID: discSourceID, trackID: $0.id, kind: $0.type, codec: $0.codec, name: "", language: "und", isDefault: false, isForced: false, enabled: true, detail: "") }
        let discOut = run.appendingPathComponent("blu-ray main title.mkv")
        _ = try Engine.export(plan: ExportPlan(sources: [discSource], tracks: discTracks), output: discOut, engine: engine, job: RunningJob()) { _ in }
        let discOutProbe = try Engine.identify(discOut, engine: engine)
        let discSeconds = Double(discOutProbe.container.properties?.duration ?? 0) / 1_000_000_000
        try check(discOutProbe.tracks.contains { $0.type == "audio" } && discSeconds > 3.0, "Blu-ray main title export appends all clips and keeps audio (\(discSeconds) s)")
        let bdmvRoot = fixture.appendingPathComponent("bdmv-title-fixture")
        let playlistDir = bdmvRoot.appendingPathComponent("BDMV/PLAYLIST", isDirectory: true)
        let streamDir = bdmvRoot.appendingPathComponent("BDMV/STREAM", isDirectory: true)
        try fm.createDirectory(at: playlistDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: streamDir, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 120).write(to: playlistDir.appendingPathComponent("00000.mpls"))
        try Data(repeating: 0, count: 8400).write(to: playlistDir.appendingPathComponent("00800.mpls"))
        let mainTitle = try BluRayISO.longestPlaylist(under: bdmvRoot)
        try check(mainTitle?.lastPathComponent == "00800.mpls", "Blu-ray main title picks the largest PLAYLIST mpls (mount/remux path: owner manual)")
        print("\n\(results.count) checks passed. Outputs: \(run.path)")
        try (results.joined(separator: "\n") + "\n\nOutputs: " + run.path + "\n").write(to: fixture.appendingPathComponent("test-report.txt"), atomically: true, encoding: .utf8)
    }
}
