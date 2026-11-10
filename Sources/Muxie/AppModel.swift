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
    @Published var filter = "All"
    @Published var trackPage = 0
    @Published var workspaceScreenHeight: CGFloat = 900
    var job: RunningJob?
    var active: MediaTrack? { tracks.first { $0.id == selected } }
    var enabled: [MediaTrack] { tracks.filter(\.enabled) }
    var busy: Bool { importing || exporting }
    var canExport: Bool { !busy && Engine.executable != nil && enabled.contains { $0.kind == "video" } }
    var totalBytes: Int64 { sources.reduce(0) { $0 + $1.byteSize } }
    var filtered: [MediaTrack] { tracks.filter { filter == "All" || $0.filterName == filter } }
    var tracksPerPage: Int {
        let capacity = WorkspaceLayout.pageCapacity(screenHeight: workspaceScreenHeight)
        return tracks.count > capacity ? WorkspaceLayout.pageCapacity(screenHeight: workspaceScreenHeight, pagination: true) : capacity
    }
    var reservesPagination: Bool { tracks.count > tracksPerPage }
    var reservedTrackRows: Int { max(1, min(tracks.count, tracksPerPage)) }
    var pageCount: Int { max(1, Int(ceil(Double(filtered.count) / Double(tracksPerPage)))) }
    var currentTrackPage: Int { min(max(0, trackPage), pageCount - 1) }
    var pagedTracks: [MediaTrack] { Array(filtered.dropFirst(currentTrackPage * tracksPerPage).prefix(tracksPerPage)) }
    var minimumTrackSectionHeight: CGFloat { WorkspaceLayout.trackSectionHeight(rows: reservedTrackRows, pagination: reservesPagination) }
    var minimumContentHeight: CGFloat { sources.isEmpty ? 280 : WorkspaceLayout.minimumContentHeight(rows: reservedTrackRows, pagination: reservesPagination) }
    func displayName(for track: MediaTrack) -> String {
        if !track.name.isEmpty { return track.name }
        let peers = tracks.filter { $0.kind == track.kind }
        guard peers.count > 1, let index = peers.firstIndex(where: { $0.id == track.id }) else { return track.kindName }
        return "\(track.kindName) \(index + 1)"
    }
    func fail(_ text: String) { error = text; showError = true }
    func openFiles(additional: Bool = false) {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = additional
        panel.title = additional ? "Add Tracks" : "Open Video"
        panel.prompt = additional ? "Add" : "Open"
        if let source = sources.first { panel.directoryURL = source.url.deletingLastPathComponent() }
        panel.allowedContentTypes = ["mkv", "mp4", "m4v", "mov", "avi", "webm", "mka", "mks", "srt", "ass", "ssa", "vtt", "sup", "ac3", "eac3", "dts", "aac", "m4a", "mp3", "flac", "wav", "ogg", "opus"].compactMap { UTType(filenameExtension: $0) }
        panel.begin { [weak self] result in if result == .OK { Task { @MainActor in await self?.importFiles(panel.urls) } } }
    }
    func importFiles(_ urls: [URL]) async {
        guard !busy, !urls.isEmpty else { return }
        guard let engine = Engine.executable else { fail("The bundled mkvmerge is missing. Reinstall Muxie."); return }
        importing = true; completed = nil; warning = nil
        var failures: [String] = []
        for url in urls {
            guard url.isFileURL else { continue }
            let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
            if sources.contains(where: { $0.url.standardizedFileURL.resolvingSymlinksInPath() == canonical }) { continue }
            do {
                let probe = try await Task.detached(priority: .userInitiated) { try Engine.identify(url, engine: engine) }.value
                let supported = probe.tracks.filter { ["video", "audio", "subtitles"].contains($0.type) }
                guard !supported.isEmpty else { throw MuxError.message("\(url.lastPathComponent) contains no supported tracks.") }
                let isPrimary = sources.isEmpty
                if isPrimary && !supported.contains(where: { $0.type == "video" }) { throw MuxError.message("Open a video before adding audio or subtitles.") }
                let sourceID = UUID()
                let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                sources.append(MediaSource(id: sourceID, url: url, container: probe.container.type ?? url.pathExtension.uppercased(), byteSize: Int64(bytes)))
                var added: [MediaTrack] = []
                for t in supported {
                    let detail: String
                    if let dimensions = t.properties.pixel_dimensions { detail = dimensions.replacingOccurrences(of: "x", with: " × ") }
                    else if let channels = t.properties.audio_channels { detail = "\(channels) ch" }
                    else { detail = "" }
                    added.append(MediaTrack(sourceID: sourceID, trackID: t.id, kind: t.type, codec: t.codec, name: t.properties.track_name ?? "", language: t.properties.language_ietf ?? t.properties.language ?? "und", isDefault: isPrimary ? (t.properties.default_track ?? false) : false, isForced: t.properties.forced_track ?? false, enabled: false, detail: detail))
                }
                tracks += added
            } catch { failures.append(error.localizedDescription) }
        }
        importing = false
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
    func reset() { guard !busy else { return }; sources = []; tracks = []; selected = nil; completed = nil; warning = nil; filter = "All"; trackPage = 0 }
    func exportPanel() {
        guard canExport, let source = sources.first else { return }
        let panel = NSSavePanel(); panel.title = "Export MKV"; panel.prompt = "Export"; panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "mkv") ?? .data]
        panel.nameFieldStringValue = source.url.deletingPathExtension().lastPathComponent + "-muxie.mkv"
        panel.directoryURL = source.url.deletingLastPathComponent()
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
    func reveal() { if let url = completed { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
}

final class ExportActivity { static let shared = ExportActivity(); var active = false; var terminating = false; var cancel: (() -> Void)? }
