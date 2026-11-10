// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import Foundation
import AppKit

final class ProgressWitness: @unchecked Sendable { let lock = NSLock(); private var seen = false; func mark() { lock.lock(); seen = true; lock.unlock() }; var value: Bool { lock.lock(); defer { lock.unlock() }; return seen } }

@main struct IntegrationTests {
    @MainActor static func main() async throws {
        let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
        guard let engine = Engine.executable else { fatalError("Bundled mkvmerge missing") }
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
            sizing.completed = run.appendingPathComponent("layout-only.mkv"); sizing.exporting = true
            sizeChecks = sizeChecks && sizing.pagedTracks.count == count && !sizing.reservesPagination && before == sizing.minimumContentHeight && before == WorkspaceLayout.minimumContentHeight(rows: count)
            sizing.completed = nil; sizing.exporting = false
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
