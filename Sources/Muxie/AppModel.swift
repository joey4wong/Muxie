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
    @Published var progress: Double = 0
    @Published var completed: URL?
    @Published var warning: String?
    @Published var error: String?
    @Published var showError = false
    @Published var showAbout = false
    @Published var showQueue = false
    @Published var filter = "All"
    @Published var trackPage = 0
    @Published var workspaceScreenHeight: CGFloat = 900
    @Published var exportMode: ExportMode = .mux
    @Published var compressEligible = true
    @Published var queueJobs: [QueueJob] = []
    @Published var queueResumePending = false
    @Published var compressQuality = CompressQuality()
    var job: RunningJob?
    var persistQueueTask: Task<Void, Never>?
    var sessionNotifications = Set<UUID>()
    var isoMounts: [UUID: BluRayMount] = [:]
    /// Per queue job (a paused job keeps its disc mounted while another job runs), then per source.
    var queueISOMounts: [UUID: [UUID: BluRayMount]] = [:]
    var queueRunning: [UUID: RunningJob] = [:]
    var activeQueueTasks = 0
    /// Set when the user pauses: the queue waits for Resume or Run Now instead of starting the next job.
    var queueHoldFlag = false
    var queueSleeping = false
    /// Compress profile of the checked video, for showing the default quality values.
    var compressProfile: CompressProfile {
        CompressProfile(height: tracks.first(where: { $0.kind == "video" && $0.enabled })?.pixelHeight ?? 1080)
    }
    var active: MediaTrack? { tracks.first { $0.id == selected } }
    var enabled: [MediaTrack] { tracks.filter(\.enabled) }
    var busy: Bool { importing || queueHasPendingExport }
    var queueHasPendingExport: Bool { queueJobs.contains { $0.isPending } }
    var queueBadgeCount: Int { queueJobs.filter { $0.isPending }.count }
    var runningQueueJob: QueueJob? { queueJobs.first { $0.isRunning } }
    var queueActivityActive: Bool { runningQueueJob != nil }
    var canExport: Bool {
        guard !importing, Engine.executable != nil, enabled.contains(where: { $0.kind == "video" }) else { return false }
        if exportMode == .compress { return compressEligible && Engine.handbrakeExecutable != nil }
        return true
    }
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
        guard !importing else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = additional
        panel.title = additional ? "Add Tracks" : "Open Video"
        panel.prompt = additional ? "Add" : "Open"
        if let source = sources.first { panel.directoryURL = source.displayURL.deletingLastPathComponent() }
        panel.allowedContentTypes = (["iso"] + ["mkv", "mp4", "m4v", "mov", "avi", "webm", "mka", "mks", "srt", "ass", "ssa", "vtt", "sup", "ac3", "eac3", "dts", "aac", "m4a", "mp3", "flac", "wav", "ogg", "opus"]).compactMap { UTType(filenameExtension: $0) }
        panel.begin { [weak self] result in if result == .OK { Task { @MainActor in await self?.importFiles(panel.urls) } } }
    }
    func importFiles(_ urls: [URL]) async {
        guard !importing, !urls.isEmpty else { return }
        guard let engine = Engine.executable else { fail("The bundled mkvmerge is missing. Reinstall Muxie."); return }
        importing = true; completed = nil; warning = nil
        var failures: [String] = []
        for url in urls {
            guard url.isFileURL else { continue }
            let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
            if sources.contains(where: { $0.displayURL.standardizedFileURL.resolvingSymlinksInPath() == canonical }) { continue }
            if url.pathExtension.lowercased() == "iso" {
                if !isoMounts.isEmpty || sources.contains(where: { $0.originURL != nil }) {
                    failures.append("Only one disc image can be open at a time.")
                    continue
                }
                if !sources.isEmpty { failures.append("Open the disc image before adding other files."); continue }
            }
            var openedMount: BluRayMount?
            do {
                let importURL: URL
                let originURL: URL?
                let sourceBytes: Int64
                var appendedParts: [URL] = []
                if url.pathExtension.lowercased() == "iso" {
                    let mount = try await Task.detached(priority: .userInitiated) { try BluRayISO.attach(iso: canonical) }.value
                    openedMount = mount
                    importURL = mount.mediaURL
                    appendedParts = mount.extraParts
                    originURL = canonical
                    sourceBytes = mount.inputBytes
                } else {
                    importURL = canonical
                    originURL = nil
                    sourceBytes = Int64((try? importURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                }
                let (probe, fileDVProfile, subtitleCharset) = try await Task.detached(priority: .userInitiated) { () throws -> (Probe, Int?, String?) in
                    let probe = try Engine.identify(importURL, engine: engine)
                    let container = (probe.container.type ?? "").lowercased()
                    let hasHEVC = probe.tracks.contains { $0.type == "video" && ($0.codec.uppercased().contains("HEVC") || $0.codec.uppercased().contains("H.265")) }
                    let readable = container.contains("matroska") || container.contains("mp4") || container.contains("quicktime")
                    return (probe, hasHEVC && readable ? VideoHDR.dolbyVisionProfile(fileURL: importURL) : nil, SubtitleCharset.detect(fileURL: importURL))
                }.value
                let supported = probe.tracks.filter { ["video", "audio", "subtitles"].contains($0.type) }
                guard !supported.isEmpty else { throw MuxError.message("\(url.lastPathComponent) contains no supported tracks.") }
                let isPrimary = sources.isEmpty
                if isPrimary && !supported.contains(where: { $0.type == "video" }) { throw MuxError.message("Open a video before adding audio or subtitles.") }
                let sourceID = UUID()
                sources.append(MediaSource(id: sourceID, url: importURL, originURL: originURL, container: probe.container.type ?? importURL.pathExtension.uppercased(), byteSize: sourceBytes, appendedParts: appendedParts))
                if let m = openedMount { isoMounts[sourceID] = m; openedMount = nil }
                var added: [MediaTrack] = []
                for t in supported {
                    let detail: String
                    if let dimensions = t.properties.pixel_dimensions { detail = dimensions.replacingOccurrences(of: "x", with: " × ") }
                    else if let channels = t.properties.audio_channels { detail = "\(channels) ch" }
                    else { detail = "" }
                    let pixelHeight = t.properties.pixel_dimensions.flatMap { Int($0.split(separator: "x").last ?? "") }
                    let dvProfile = t.type == "video" ? (fileDVProfile ?? VideoHDR.dolbyVisionProfile(codecPrivateHex: t.properties.codec_private_data)) : nil
                    let hdr = t.type == "video" ? (dvProfile != nil ? .dolbyVision : VideoHDR.badge(transfer: t.properties.color_transfer_characteristics, codecPrivateHex: t.properties.codec_private_data)) : nil
                    added.append(MediaTrack(sourceID: sourceID, trackID: t.id, kind: t.type, codec: t.codec, name: t.properties.track_name ?? "", language: t.properties.language_ietf ?? t.properties.language ?? "und", isDefault: isPrimary ? (t.properties.default_track ?? false) : false, isForced: t.properties.forced_track ?? false, enabled: false, detail: detail, audioChannels: t.type == "audio" ? t.properties.audio_channels : nil, isAAC: t.type == "audio" ? t.codec.uppercased().contains("AAC") : nil, pixelHeight: pixelHeight, codecPrivateHex: t.type == "video" ? t.properties.codec_private_data : nil, colorTransfer: t.type == "video" ? t.properties.color_transfer_characteristics : nil, hdrBadge: hdr, dolbyVisionProfile: dvProfile, subtitleCharset: t.type == "subtitles" ? subtitleCharset : nil))
                }
                if isPrimary { TrackAutoSelect.apply(&added) }
                tracks += added
            } catch {
                if let openedMount { BluRayISO.detach(openedMount) }
                failures.append(error.localizedDescription)
            }
        }
        importing = false
        exportMode = .mux
        refreshCompressEligibility()
        if !failures.isEmpty { fail(failures.joined(separator: "\n\n")) }
    }
    func refreshCompressEligibility() {
        guard enabled.contains(where: { $0.kind == "video" }), let video = tracks.first(where: { $0.kind == "video" && $0.enabled }) else {
            compressEligible = true
            return
        }
        let codec = video.codec.uppercased()
        let already = (codec.contains("HEVC") || codec.contains("H.265"))
            && Engine.hevcBitDepth(fromCodecPrivate: video.codecPrivateHex) == 10
            && (video.pixelHeight ?? 9999) <= 1080
        compressEligible = !already
        if !compressEligible && exportMode == .compress { exportMode = .mux }
    }
    func hdrCompressWarning() -> String? {
        guard exportMode == .compress else { return nil }
        let badges = tracks.filter { $0.enabled && $0.kind == "video" }.compactMap(\.hdrBadge)
        let profiles = tracks.filter { $0.enabled && $0.kind == "video" }.compactMap { $0.dolbyVisionProfile ?? VideoHDR.dolbyVisionProfile(codecPrivateHex: $0.codecPrivateHex) }
        return VideoHDR.compressExportWarning(badges: badges, encoder: CompressEncoder.current, dolbyVisionProfiles: profiles)
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
            if keyPath == \MediaTrack.enabled { self.refreshCompressEligibility() }
        })
    }
    func intBinding(_ id: UUID, _ keyPath: WritableKeyPath<MediaTrack, Int>) -> Binding<Int> {
        Binding(get: { self.tracks.first { $0.id == id }?[keyPath: keyPath] ?? 0 }, set: { value in
            if let i = self.tracks.firstIndex(where: { $0.id == id }) { self.tracks[i][keyPath: keyPath] = value; self.completed = nil }
        })
    }
    func optionalIntBinding(_ id: UUID, numerator: WritableKeyPath<MediaTrack, Int?>, denominator: WritableKeyPath<MediaTrack, Int?>) -> Binding<String> {
        Binding(get: {
            guard let track = self.tracks.first(where: { $0.id == id }), let num = track[keyPath: numerator], let den = track[keyPath: denominator], den != 0 else { return "" }
            return "\(num)/\(den)"
        }, set: { raw in
            guard let i = self.tracks.firstIndex(where: { $0.id == id }) else { return }
            let cleaned = raw.trimmingCharacters(in: .whitespaces)
            if cleaned.isEmpty {
                self.tracks[i][keyPath: numerator] = nil
                self.tracks[i][keyPath: denominator] = nil
            } else {
                let parts = cleaned.split(separator: "/").map(String.init)
                if parts.count == 2, let num = Int(parts[0]), let den = Int(parts[1]), den != 0 {
                    self.tracks[i][keyPath: numerator] = num
                    self.tracks[i][keyPath: denominator] = den
                }
            }
            self.completed = nil
        })
    }
    func removeSource(_ source: MediaSource) {
        guard !importing, source.id != sources.first?.id else { return }
        tracks.removeAll { $0.sourceID == source.id }; sources.removeAll { $0.id == source.id }
        if let mount = isoMounts.removeValue(forKey: source.id) { BluRayISO.detach(mount) }
        if !tracks.contains(where: { $0.id == selected }) { selected = tracks.first?.id }; completed = nil
    }
    func reset() {
        guard !importing else { return }
        detachAllISO()
        sources = []; tracks = []; selected = nil; completed = nil; warning = nil; filter = "All"; trackPage = 0
        exportMode = .mux; compressEligible = true; compressQuality = CompressQuality()
    }
    func prepareForQuit() {
        QueuePersistence.saveForTermination(jobs: queueJobs, hold: queueHoldFlag, resumePending: queueResumePending)
        queueJobs.removeAll()
        detachAllISO()
        detachAllQueueISO()
    }
    func exportPanel() {
        guard canExport, let source = sources.first else { return }
        if let hdrWarning = hdrCompressWarning() {
            let alert = NSAlert()
            alert.messageText = "HDR and Dolby Vision"
            alert.informativeText = hdrWarning
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() != .alertFirstButtonReturn { return }
        }
        ExportNotifications.requestAuthorizationIfNeeded()
        let panel = NSSavePanel(); panel.title = "Export MKV"; panel.prompt = "Export"; panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "mkv") ?? .data]
        let baseName = source.displayURL.deletingPathExtension().lastPathComponent
        if let scene = sceneName(from: baseName) {
            panel.nameFieldStringValue = scene
        } else if exportMode == .compress {
            panel.nameFieldStringValue = baseName + "-compressed.mkv"
        } else if source.displayURL.pathExtension.lowercased() == "mkv" {
            panel.nameFieldStringValue = baseName + "-muxie.mkv"
        } else {
            panel.nameFieldStringValue = baseName + ".mkv"
        }
        panel.directoryURL = source.displayURL.deletingLastPathComponent()
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.enqueueExport(to: url) }
        }
    }
    /// Direct export for integration tests (bypasses the queue UI).
    func export(to output: URL) async {
        guard canExport || (!sources.isEmpty && Engine.executable != nil), let engine = Engine.executable else { return }
        progress = 0; completed = nil; warning = nil
        IdleSleepActivity.begin()
        do { try await ensureISOMounted() } catch {
            IdleSleepActivity.end()
            fail(error.localizedDescription)
            return
        }
        let plan = ExportPlan(sources: sources, tracks: tracks); let running = RunningJob(); job = running
        ExportActivity.shared.active = true; ExportActivity.shared.cancel = { running.cancel() }
        defer {
            detachAllISO()
            IdleSleepActivity.end()
            ExportActivity.shared.active = false; ExportActivity.shared.cancel = nil
        }
        do {
            let mode = exportMode
            let handbrake = Engine.handbrakeExecutable
            let encoder = CompressEncoder.current
            let quality = compressQuality
            let warnings = try await Task.detached(priority: .userInitiated) { [weak self] in
                if mode == .compress, let handbrake {
                    return try Engine.exportCompressed(plan: plan, output: output, mkvmerge: engine, handbrake: handbrake, job: running, encoder: encoder, quality: quality) { [weak self] update in
                        Task { @MainActor in self?.progress = update.value }
                    }
                }
                return try Engine.export(plan: plan, output: output, engine: engine, job: running) { [weak self] update in
                    Task { @MainActor in self?.progress = update.value }
                }
            }.value
            progress = 1; completed = output; warning = warnings
        } catch is CancellationError { progress = 0 }
        catch { fail(error.localizedDescription) }
        job = nil
    }
    func reveal() { if let url = completed { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
}

final class ExportActivity { static let shared = ExportActivity(); var active = false; var terminating = false; var cancel: (() -> Void)? }
