// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor final class AppModel: ObservableObject {
    @Published var sources: [MediaSource] = []
    @Published var tracks: [MediaTrack] = []
    @Published var selected: UUID?
    @Published var importing = false
    @Published var exporting = false
    @Published var progress: Double = 0
    @Published var completed: URL?
    @Published var warning: String?
    @Published var error: String?
    @Published var showError = false
    @Published var showAbout = false
    @Published var filter = "全部"
    @Published var enginePath = Engine.executable?.path
    var job: RunningJob?
    var active: MediaTrack? { tracks.first { $0.id == selected } }
    var enabled: [MediaTrack] { tracks.filter(\.enabled) }
    var busy: Bool { importing || exporting }
    var canExport: Bool { !busy && enginePath != nil && enabled.contains { $0.kind == "video" } }
    var totalBytes: Int64 { sources.reduce(0) { $0 + $1.byteSize } }
    var filtered: [MediaTrack] { tracks.filter { filter == "全部" || $0.kindName == filter } }
    func fail(_ text: String) { error = text; showError = true }
    func openFiles(additional: Bool = false) {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = additional
        panel.message = additional ? "选择要加入的音频、字幕，或含有所需轨道的影片" : "选择一个 MP4 或 MKV 影片，开始整理轨道"
        panel.allowedContentTypes = ["mkv", "mp4", "m4v", "mov", "avi", "webm", "mka", "mks", "srt", "ass", "ssa", "vtt", "sup", "ac3", "eac3", "dts", "aac", "m4a", "mp3", "flac", "wav", "ogg", "opus"].compactMap { UTType(filenameExtension: $0) }
        panel.begin { [weak self] result in if result == .OK { Task { @MainActor in await self?.importFiles(panel.urls) } } }
    }
    func importFiles(_ urls: [URL]) async {
        guard !busy, !urls.isEmpty else { return }
        guard let engine = Engine.executable else { fail("未找到 MKVToolNix。请安装 MKVToolNix，或在关于面板中选择 mkvmerge。"); return }
        importing = true; completed = nil; warning = nil
        var failures: [String] = []
        for url in urls {
            guard url.isFileURL else { continue }
            let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
            if sources.contains(where: { $0.url.standardizedFileURL.resolvingSymlinksInPath() == canonical }) { continue }
            do {
                let probe = try await Task.detached(priority: .userInitiated) { try Engine.identify(url, engine: engine) }.value
                let supported = probe.tracks.filter { ["video", "audio", "subtitles"].contains($0.type) }
                guard !supported.isEmpty else { throw MuxError.message("\(url.lastPathComponent) 没有可用的视频、音频或字幕轨道。") }
                let isPrimary = sources.isEmpty
                if isPrimary && !supported.contains(where: { $0.type == "video" }) { throw MuxError.message("请先添加主影片，再加入音轨或字幕。") }
                let sourceID = UUID()
                let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                sources.append(MediaSource(id: sourceID, url: url, container: probe.container.type ?? url.pathExtension.uppercased(), byteSize: Int64(bytes)))
                var added: [MediaTrack] = []
                for t in supported {
                    let detail: String
                    if let dimensions = t.properties.pixel_dimensions { detail = dimensions.replacingOccurrences(of: "x", with: " × ") }
                    else if let channels = t.properties.audio_channels { detail = "\(channels) 声道" }
                    else { detail = t.type == "subtitles" ? "可切换字幕" : "" }
                    added.append(MediaTrack(sourceID: sourceID, trackID: t.id, kind: t.type, codec: t.codec, name: t.properties.track_name ?? "", language: t.properties.language_ietf ?? t.properties.language ?? "und", isDefault: isPrimary ? (t.properties.default_track ?? false) : false, isForced: t.properties.forced_track ?? false, enabled: isPrimary || t.type != "video", detail: detail))
                }
                tracks += added
                if selected == nil { selected = added.first { $0.kind == "audio" }?.id ?? added.first?.id }
                if !isPrimary { selected = added.first { $0.enabled }?.id ?? selected }
            } catch { failures.append(error.localizedDescription) }
        }
        importing = false; enginePath = engine.path
        if !failures.isEmpty { fail(failures.joined(separator: "\n\n")) }
    }
    func binding(_ id: UUID, _ keyPath: WritableKeyPath<MediaTrack, String>) -> Binding<String> {
        Binding(get: { self.tracks.first { $0.id == id }?[keyPath: keyPath] ?? "" }, set: { value in
            if let i = self.tracks.firstIndex(where: { $0.id == id }) { self.tracks[i][keyPath: keyPath] = value; self.completed = nil }
        })
    }
    func boolBinding(_ id: UUID, _ keyPath: WritableKeyPath<MediaTrack, Bool>) -> Binding<Bool> {
        Binding(get: { self.tracks.first { $0.id == id }?[keyPath: keyPath] ?? false }, set: { value in
            guard let i = self.tracks.firstIndex(where: { $0.id == id }) else { return }
            if keyPath == \.isDefault && value {
                let kind = self.tracks[i].kind
                for index in self.tracks.indices where self.tracks[index].kind == kind { self.tracks[index].isDefault = false }
            }
            self.tracks[i][keyPath: keyPath] = value; self.completed = nil
        })
    }
    func removeSource(_ source: MediaSource) {
        guard !busy, source.id != sources.first?.id else { return }
        tracks.removeAll { $0.sourceID == source.id }; sources.removeAll { $0.id == source.id }
        if !tracks.contains(where: { $0.id == selected }) { selected = tracks.first?.id }; completed = nil
    }
    func reset() { guard !busy else { return }; sources = []; tracks = []; selected = nil; completed = nil; warning = nil; filter = "全部" }
    func exportPanel() {
        guard canExport, let source = sources.first else { return }
        let panel = NSSavePanel(); panel.title = "导出 MKV"; panel.prompt = "导出"; panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "mkv") ?? .data]
        panel.nameFieldStringValue = source.url.deletingPathExtension().lastPathComponent + "-muxie.mkv"
        panel.directoryURL = source.url.deletingLastPathComponent()
        panel.message = "无损重新封装，不重新编码。为保护原文件，请使用新的文件名。"
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            Task { @MainActor in await self?.export(to: url) }
        }
    }
    func export(to output: URL) async {
        guard canExport, let engine = Engine.executable else { return }
        exporting = true; progress = 0; completed = nil; warning = nil
        let plan = ExportPlan(sources: sources, tracks: tracks); let running = RunningJob(); job = running
        ExportActivity.shared.active = true; ExportActivity.shared.cancel = { running.cancel() }
        defer {
            ExportActivity.shared.active = false; ExportActivity.shared.cancel = nil
            if ExportActivity.shared.terminating { NSApp.reply(toApplicationShouldTerminate: true) }
        }
        do {
            let warnings = try await Task.detached(priority: .userInitiated) { [weak self] in
                try Engine.export(plan: plan, output: output, engine: engine, job: running) { [weak self] value in
                    Task { @MainActor in self?.progress = value }
                }
            }.value
            progress = 1; completed = output; warning = warnings
        } catch is CancellationError { progress = 0 }
        catch { fail(error.localizedDescription) }
        exporting = false; job = nil
    }
    func chooseEngine() {
        let panel = NSOpenPanel(); panel.message = "选择 MKVToolNix 的 mkvmerge 可执行文件"; panel.canChooseDirectories = false
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            guard FileManager.default.isExecutableFile(atPath: url.path) else { self?.fail("请选择可执行的 mkvmerge 文件。"); return }
            UserDefaults.standard.set(url.path, forKey: "enginePath"); self?.enginePath = Engine.executable?.path
        }
    }
    func reveal() { if let url = completed { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
}

final class ExportActivity { static let shared = ExportActivity(); var active = false; var terminating = false; var cancel: (() -> Void)? }
