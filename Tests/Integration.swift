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
        try check(!runtimeText.unicodeScalars.contains(where: { (0x3400...0x9fff).contains($0.value) }) && !runtimeText.contains("chooseEngine") && !runtimeText.contains("enginePath") && !runtimeText.contains("sidebar"), "English-only runtime source, no sidebar or engine chooser")
        try check(!runtimeText.contains("ScrollView") && !runtimeText.contains("glassProminent") && !runtimeText.contains("height * 0.70"), "No track scrolling, fractional clipping or saturated prominent buttons")
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
        try check(model.enabled.isEmpty && model.selected == nil && !model.canExport, "Imported tracks are unchecked with no focused row")
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
        try check(compressedProbe.tracks.filter { $0.type == "audio" }.allSatisfy { $0.codec.uppercased().contains("AAC") }, "Compress: audio is AAC")
        try check(compressedProbe.tracks.filter { $0.type == "subtitles" }.count == 1, "Compress: subtitle track kept")
        try check(Engine.hevcBitDepth(fromCodecPrivate: "0102" + String(repeating: "00", count: 15) + "FAFA") == 10 && Engine.hevcBitDepth(fromCodecPrivate: "0101" + String(repeating: "00", count: 15) + "F8F8") == 8 && Engine.hevcBitDepth(fromCodecPrivate: nil) == nil && Engine.hevcBitDepth(fromCodecPrivate: "01") == nil, "HEVC bit depth is read from codec private data")
        // The file just produced is HEVC 10-bit <= 1080p, so compressing it again must not be offered.
        let again = AppModel()
        await again.importFiles([compressedURL])
        for track in again.tracks where track.kind == "video" { again.boolBinding(track.id, \.enabled).wrappedValue = true }
        await again.refreshCompressEligibility()
        try check(!again.compressEligible, "Compress is not offered for HEVC 10-bit video at or below 1080p")
        // Every audio track unchecked: a video-only compressed output is valid, not a verification failure.
        let silentCompress = AppModel()
        await silentCompress.importFiles([video])
        for track in silentCompress.tracks where track.kind == "video" { silentCompress.boolBinding(track.id, \.enabled).wrappedValue = true }
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
        try check(CompressProfile(height: 1080).rf == 21 && CompressProfile(height: 2160).rf == 23 && CompressProfile(height: 2160).maxWidth == 3840, "Compress profile table")
        try check(ExportMode.mux.label == "Mux" && ExportMode.compress.label == "Compress", "Export mode labels Mux and Compress")
        try check(
            CompressSettings.audioBitrateKbps(channelCount: 1) == 96
                && CompressSettings.audioBitrateKbps(channelCount: 2) == 192
                && CompressSettings.audioBitrateKbps(channelCount: 6) == 384
                && CompressSettings.audioBitrateKbps(channelCount: 8) == 512,
            "Audio channel-count to bitrate table"
        )
        try check(CompressSettings.encodedChannelCount(sourceChannels: 8) == 6, "7.1 and above cap at 5.1 for AAC")
        let spaceSource = MediaSource(id: UUID(), url: video, container: "MP4", byteSize: 10_000_000)
        let spacePlan = ExportPlan(sources: [spaceSource], tracks: model.tracks.filter(\.enabled))
        try check(ExportSpace.requiredBytes(mode: .mux, plan: spacePlan) == 10_000_000, "Mux space estimate equals checked input bytes")
        try check(ExportSpace.requiredBytes(mode: .compress, plan: spacePlan) == 10_000_000 + 5_000_000, "Compress space estimate includes temp remux and conservative output")
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
