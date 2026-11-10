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
    var job: RunningJob?
    private var isoMounts: [UUID: BluRayMount] = [:]
    private var queueISOMounts: [UUID: BluRayMount] = [:]
    private var queueProcessor: Task<Void, Never>?
    private var queueSleeping = false
    var active: MediaTrack? { tracks.first { $0.id == selected } }
    var enabled: [MediaTrack] { tracks.filter(\.enabled) }
    var busy: Bool { importing || queueHasPendingExport }
    var queueHasPendingExport: Bool { queueJobs.contains { $0.isPending } }
    var queueBadgeCount: Int { queueJobs.filter { $0.state == .queued || $0.isRunning }.count }
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
                    failures.append("Only one Blu-ray ISO can be open at a time.")
                    continue
                }
                if !sources.isEmpty { failures.append("Open the Blu-ray ISO before adding other files."); continue }
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
                let probe = try await Task.detached(priority: .userInitiated) { try Engine.identify(importURL, engine: engine) }.value
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
                    added.append(MediaTrack(sourceID: sourceID, trackID: t.id, kind: t.type, codec: t.codec, name: t.properties.track_name ?? "", language: t.properties.language_ietf ?? t.properties.language ?? "und", isDefault: isPrimary ? (t.properties.default_track ?? false) : false, isForced: t.properties.forced_track ?? false, enabled: false, detail: detail))
                }
                tracks += added
            } catch {
                if let openedMount { BluRayISO.detach(openedMount) }
                failures.append(error.localizedDescription)
            }
        }
        importing = false
        exportMode = .mux
        await refreshCompressEligibility()
        if !failures.isEmpty { fail(failures.joined(separator: "\n\n")) }
    }
    func refreshCompressEligibility() async {
        guard let engine = Engine.executable, enabled.contains(where: { $0.kind == "video" }) else {
            compressEligible = true
            return
        }
        let tracks = tracks
        let sources = sources
        let already = (try? await Task.detached(priority: .utility) {
            try Engine.videoAlreadyHEVC1080p(tracks, sources: sources, engine: engine)
        }.value) ?? false
        compressEligible = !already
        if !compressEligible && exportMode == .compress { exportMode = .mux }
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
            if keyPath == \MediaTrack.enabled { Task { @MainActor in await self.refreshCompressEligibility() } }
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
        exportMode = .mux; compressEligible = true
    }
    func recoverStaleISOMounts() { BluRayISO.recoverStaleMounts(); isoMounts = [:] }
    func prepareForQuit() {
        queueJobs.removeAll()
        detachAllISO()
        detachQueueISO()
    }
    private func detachAllISO() {
        for mount in isoMounts.values { BluRayISO.detach(mount) }
        isoMounts = [:]
    }
    private func detachQueueISO() {
        for mount in queueISOMounts.values { BluRayISO.detach(mount) }
        queueISOMounts = [:]
    }
    private func ensureISOMounted() async throws {
        for index in sources.indices {
            guard let iso = sources[index].originURL, isoMounts[sources[index].id] == nil else { continue }
            let mount = try await Task.detached(priority: .userInitiated) { try BluRayISO.attach(iso: iso) }.value
            isoMounts[sources[index].id] = mount
            sources[index].url = mount.mediaURL
            sources[index].byteSize = mount.inputBytes
            sources[index].appendedParts = mount.extraParts
        }
    }
    private func ensureQueueISOMounted(sources: inout [MediaSource]) async throws {
        for index in sources.indices {
            guard let iso = sources[index].originURL, queueISOMounts[sources[index].id] == nil else { continue }
            let sourceID = sources[index].id
            let mount = try await Task.detached(priority: .userInitiated) { try BluRayISO.attach(iso: iso) }.value
            queueISOMounts[sourceID] = mount
            sources[index].url = mount.mediaURL
            sources[index].byteSize = mount.inputBytes
            sources[index].appendedParts = mount.extraParts
        }
    }
    func exportPanel() {
        guard canExport, let source = sources.first else { return }
        let panel = NSSavePanel(); panel.title = "Export MKV"; panel.prompt = "Export"; panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "mkv") ?? .data]
        let baseName = source.displayURL.deletingPathExtension().lastPathComponent
        if exportMode == .compress {
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
    func enqueueExport(to output: URL) {
        let target = output.standardizedFileURL.resolvingSymlinksInPath()
        let taken = queueJobs.filter(\.isPending).map { $0.output.standardizedFileURL.resolvingSymlinksInPath() }
        if taken.contains(target) {
            fail("Another queued export already uses this output path.")
            return
        }
        queueJobs.append(QueueJob.snapshot(sources: sources, tracks: tracks, mode: exportMode, output: output))
        reset()
        startQueueProcessorIfNeeded()
    }
    private func startQueueProcessorIfNeeded() {
        guard queueProcessor == nil else { return }
        ExportActivity.shared.active = queueHasPendingExport
        queueProcessor = Task { @MainActor in
            defer { queueProcessor = nil }
            while let index = queueJobs.firstIndex(where: { $0.state == .queued }) {
                await runQueueJob(at: index)
            }
            let failedCount = queueJobs.filter { if case .failed = $0.state { return true }; return false }.count
            if failedCount > 0 { fail(failedCount == 1 ? "1 queued export failed. Open the export queue for details." : "\(failedCount) queued exports failed. Open the export queue for details.") }
            if queueSleeping {
                IdleSleepActivity.end()
                queueSleeping = false
            }
            ExportActivity.shared.active = false
            ExportActivity.shared.cancel = nil
            if ExportActivity.shared.terminating { NSApp.reply(toApplicationShouldTerminate: true) }
        }
    }
    private func runQueueJob(at index: Int) async {
        let jobID = queueJobs[index].id
        if !queueSleeping {
            IdleSleepActivity.begin()
            queueSleeping = true
        }
        self[job: jobID].state = .running(progress: 0)
        progress = 0
        var workingSources = self[job: jobID].sources
        let mode = self[job: jobID].mode
        let output = self[job: jobID].output
        let planTracks = self[job: jobID].tracks
        let running = RunningJob()
        job = running
        ExportActivity.shared.active = true
        ExportActivity.shared.cancel = { running.cancel() }
        defer {
            detachQueueISO()
            job = nil
        }
        do {
            try await ensureQueueISOMounted(sources: &workingSources)
        } catch {
            self[job: jobID].state = .failed(error.localizedDescription)
            progress = 0
            return
        }
        let plan = ExportPlan(sources: workingSources, tracks: planTracks)
        guard let engine = Engine.executable else {
            self[job: jobID].state = .failed("The bundled mkvmerge is missing. Reinstall Muxie.")
            return
        }
        if mode == .compress, Engine.handbrakeExecutable == nil {
            self[job: jobID].state = .failed("The bundled HandBrakeCLI is missing. Reinstall Muxie.")
            return
        }
        do {
            try ExportSpace.verifySpace(mode: mode, plan: plan, destination: output.deletingLastPathComponent())
        } catch let err as MuxError {
            self[job: jobID].state = .failed(err.localizedDescription)
            return
        } catch {
            self[job: jobID].state = .failed(error.localizedDescription)
            return
        }
        do {
            let handbrake = Engine.handbrakeExecutable
            let warnings = try await Task.detached(priority: .userInitiated) { [running] in
                if mode == .compress, let handbrake {
                    return try Engine.exportCompressed(plan: plan, output: output, mkvmerge: engine, handbrake: handbrake, job: running) { value in
                        Task { @MainActor in self.updateQueueProgress(jobID: jobID, value: value) }
                    }
                }
                return try Engine.export(plan: plan, output: output, engine: engine, job: running) { value in
                    Task { @MainActor in self.updateQueueProgress(jobID: jobID, value: value) }
                }
            }.value
            self[job: jobID].warning = warnings
            self[job: jobID].state = .done
            progress = 1
        } catch is CancellationError {
            self[job: jobID].state = .cancelled
            progress = 0
        } catch {
            self[job: jobID].state = .failed(error.localizedDescription)
            progress = 0
        }
    }
    /// Job lookup by id. Writes to a job that no longer exists are ignored.
    private subscript(job id: UUID) -> QueueJob {
        get { queueJobs.first { $0.id == id } ?? QueueJob(id: id, sources: [], tracks: [], mode: .mux, output: URL(fileURLWithPath: "/"), state: .cancelled, warning: nil) }
        set { if let i = queueJobs.firstIndex(where: { $0.id == id }) { queueJobs[i] = newValue } }
    }
    private func updateQueueProgress(jobID: UUID, value: Double) {
        guard let index = queueJobs.firstIndex(where: { $0.id == jobID }) else { return }
        queueJobs[index].state = .running(progress: value)
        progress = value
    }
    func cancelQueueJob(_ id: UUID) {
        guard let index = queueJobs.firstIndex(where: { $0.id == id }) else { return }
        switch queueJobs[index].state {
        case .running: job?.cancel()
        case .queued: queueJobs[index].state = .cancelled
        default: break
        }
    }
    func removeQueueJob(_ id: UUID) {
        guard let index = queueJobs.firstIndex(where: { $0.id == id }) else { return }
        switch queueJobs[index].state {
        case .running: job?.cancel()
        case .queued: queueJobs.remove(at: index)
        case .done, .failed, .cancelled: queueJobs.remove(at: index)
        }
    }
    func clearFinishedQueueJob(_ id: UUID) {
        guard let index = queueJobs.firstIndex(where: { $0.id == id }) else { return }
        switch queueJobs[index].state {
        case .done, .failed, .cancelled: queueJobs.remove(at: index)
        default: break
        }
    }
    func revealQueueOutput(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func copyQueueFailure(_ id: UUID) {
        guard let job = queueJobs.first(where: { $0.id == id }), case .failed(let text) = job.state else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
            let warnings = try await Task.detached(priority: .userInitiated) { [weak self] in
                if mode == .compress, let handbrake {
                    return try Engine.exportCompressed(plan: plan, output: output, mkvmerge: engine, handbrake: handbrake, job: running) { [weak self] value in
                        Task { @MainActor in self?.progress = value }
                    }
                }
                return try Engine.export(plan: plan, output: output, engine: engine, job: running) { [weak self] value in
                    Task { @MainActor in self?.progress = value }
                }
            }.value
            progress = 1; completed = output; warning = warnings
        } catch is CancellationError { progress = 0 }
        catch { fail(error.localizedDescription) }
        job = nil
    }
    func reveal() { if let url = completed { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
    func waitForQueueIdle() async {
        while queueHasPendingExport || queueProcessor != nil {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}

final class ExportActivity { static let shared = ExportActivity(); var active = false; var terminating = false; var cancel: (() -> Void)? }
