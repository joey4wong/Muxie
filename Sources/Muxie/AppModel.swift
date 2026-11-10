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
    var job: RunningJob?
    private var persistQueueTask: Task<Void, Never>?
    private var sessionNotifications = Set<UUID>()
    private var isoMounts: [UUID: BluRayMount] = [:]
    /// Per queue job (a paused job keeps its disc mounted while another job runs), then per source.
    private var queueISOMounts: [UUID: [UUID: BluRayMount]] = [:]
    private var queueRunning: [UUID: RunningJob] = [:]
    private var activeQueueTasks = 0
    /// Set when the user pauses: the queue waits for Resume or Run Now instead of starting the next job.
    private var queueHoldFlag = false
    private var queueHeld: Bool { queueHoldFlag && queueJobs.contains { $0.isPaused } }
    private var queueSleeping = false
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
                    let pixelHeight = t.properties.pixel_dimensions.flatMap { Int($0.split(separator: "x").last ?? "") }
                    let hdr = t.type == "video" ? VideoHDR.badge(transfer: t.properties.color_transfer_characteristics, codecPrivateHex: t.properties.codec_private_data) : nil
                    added.append(MediaTrack(sourceID: sourceID, trackID: t.id, kind: t.type, codec: t.codec, name: t.properties.track_name ?? "", language: t.properties.language_ietf ?? t.properties.language ?? "und", isDefault: isPrimary ? (t.properties.default_track ?? false) : false, isForced: t.properties.forced_track ?? false, enabled: false, detail: detail, audioChannels: t.type == "audio" ? t.properties.audio_channels : nil, isAAC: t.type == "audio" ? t.codec.uppercased().contains("AAC") : nil, pixelHeight: pixelHeight, codecPrivateHex: t.type == "video" ? t.properties.codec_private_data : nil, colorTransfer: t.type == "video" ? t.properties.color_transfer_characteristics : nil, hdrBadge: hdr))
                }
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
    func restorePersistedQueue() {
        guard queueJobs.isEmpty, let saved = QueuePersistence.load() else { return }
        queueJobs = saved.jobs.map { item in
            var job = item.job
            if item.wasInterrupted { job.interruptedNote = "Will restart from the beginning." }
            return job
        }
        queueHoldFlag = saved.hold
        queueResumePending = saved.resumePending || saved.jobs.contains(where: \.wasInterrupted)
        if !queueResumePending { scheduleNextQueueJob() }
    }
    func continuePersistedQueue() {
        queueResumePending = false
        queueHoldFlag = false
        schedulePersistedSave()
        scheduleNextQueueJob()
    }
    func hdrCompressWarning() -> String? {
        guard exportMode == .compress else { return nil }
        let badges = tracks.filter { $0.enabled && $0.kind == "video" }.compactMap(\.hdrBadge)
        return VideoHDR.compressExportWarning(badges: badges, encoder: CompressEncoder.current)
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
        exportMode = .mux; compressEligible = true
    }
    func recoverStaleISOMounts() { BluRayISO.recoverStaleMounts(); isoMounts = [:] }
    func prepareForQuit() {
        QueuePersistence.saveForTermination(jobs: queueJobs, hold: queueHoldFlag, resumePending: queueResumePending)
        queueJobs.removeAll()
        detachAllISO()
        detachAllQueueISO()
    }
    private func detachAllISO() {
        for mount in isoMounts.values { BluRayISO.detach(mount) }
        isoMounts = [:]
    }
    private func detachQueueISO(jobID: UUID) {
        for mount in (queueISOMounts.removeValue(forKey: jobID) ?? [:]).values { BluRayISO.detach(mount) }
    }
    private func detachAllQueueISO() {
        for mounts in queueISOMounts.values { for mount in mounts.values { BluRayISO.detach(mount) } }
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
    private func ensureQueueISOMounted(jobID: UUID, sources: inout [MediaSource]) async throws {
        for index in sources.indices {
            guard let iso = sources[index].originURL, queueISOMounts[jobID]?[sources[index].id] == nil else { continue }
            let sourceID = sources[index].id
            let mount = try await Task.detached(priority: .userInitiated) { try BluRayISO.attach(iso: iso) }.value
            queueISOMounts[jobID, default: [:]][sourceID] = mount
            sources[index].url = mount.mediaURL
            sources[index].byteSize = mount.inputBytes
            sources[index].appendedParts = mount.extraParts
        }
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
    /// Standard release name for films that are compressed (Compress mode) or already HEVC 10-bit 1080p or below:
    /// Title.Year.1080p.BluRay.x265.10bit.AAC-Joey.mkv (4K in place of 1080p for UHD). Nil if no year can be found in the file name.
    func sceneName(from baseName: String) -> String? {
        guard exportMode == .compress else { return nil }
        let cleaned = baseName.replacingOccurrences(of: "-compressed", with: "").replacingOccurrences(of: "-muxie", with: "")
        let words = cleaned.split(whereSeparator: { " ._()[]".contains($0) }).map(String.init)
        guard let yearIndex = words.lastIndex(where: { $0.count == 4 && $0.hasPrefix("19") || $0.count == 4 && $0.hasPrefix("20") }),
              words[yearIndex].allSatisfy(\.isNumber), yearIndex > 0 else { return nil }
        let bad = CharacterSet(charactersIn: "/:\\*?\"<>|,'’!")
        let title = words[..<yearIndex].map { String($0.unicodeScalars.filter { !bad.contains($0) }) }.filter { !$0.isEmpty }.joined(separator: ".")
        guard !title.isEmpty else { return nil }
        let height = tracks.first(where: { $0.kind == "video" && $0.enabled })?.detail.split(separator: "×").last.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 1080
        let res = height > 1080 ? "4K" : "1080p"
        let codec = CompressEncoder.current == .hardware ? "HEVC" : "x265"
        let fromISO = sources.first?.originURL?.pathExtension.lowercased() == "iso"
        let sourceTag = releaseSourceTag(baseName: cleaned, fromISO: fromISO)
        let hdrTag: String? = {
            guard let badge = tracks.first(where: { $0.kind == "video" && $0.enabled })?.hdrBadge else { return nil }
            switch badge {
            case .dolbyVision: return "DV"
            case .hdr10Plus, .hdr10: return "HDR"
            case .hlg: return "HLG"
            }
        }()
        let hasAudio = tracks.contains { $0.enabled && $0.kind == "audio" }
        var parts = [title, words[yearIndex], res]
        if let sourceTag { parts.append(sourceTag) }
        if let hdrTag { parts.append(hdrTag) }
        parts += [codec, "10bit"]
        if hasAudio { parts.append("AAC") }
        parts.append("Joey")
        return parts.joined(separator: ".") + ".mkv"
    }
    private func releaseSourceTag(baseName: String, fromISO: Bool) -> String? {
        if fromISO { return "BluRay" }
        let upper = baseName.uppercased()
        if upper.contains("WEB-DL") || upper.contains("WEBDL") { return "WEB-DL" }
        if upper.contains("WEBRIP") { return "WEBRip" }
        if upper.contains("HDTV") { return "HDTV" }
        if upper.contains("BLURAY") || upper.contains("BLU-RAY") { return "BluRay" }
        return nil
    }
    func enqueueExport(to output: URL) {
        let target = output.standardizedFileURL.resolvingSymlinksInPath()
        let taken = queueJobs.filter(\.isPending).map { $0.output.standardizedFileURL.resolvingSymlinksInPath() }
        if taken.contains(target) {
            fail("Another queued export already uses this output path.")
            return
        }
        queueJobs.append(QueueJob.snapshot(sources: sources, tracks: tracks, mode: exportMode, output: output))
        ExportNotifications.requestAuthorizationIfNeeded()
        schedulePersistedSave()
        reset()
        scheduleNextQueueJob()
    }
    private func schedulePersistedSave() {
        persistQueueTask?.cancel()
        let jobs = queueJobs
        let hold = queueHoldFlag
        let resume = queueResumePending
        persistQueueTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            QueuePersistence.save(jobs: jobs, hold: hold, resumePending: resume)
        }
    }
    /// One job runs at a time. A paused job does not count as running, so another job can run meanwhile.
    private func scheduleNextQueueJob() {
        if queueJobs.contains(where: { $0.isRunning }) { return }
        if queueHeld { endQueueSleep(); return }
        if let next = queueJobs.first(where: { $0.state == .queued }) { startQueueJob(next.id); return }
        // Nothing else is waiting: carry on with a paused job instead of leaving it forgotten.
        if let paused = queueJobs.first(where: { $0.isPaused }) { resumeQueueJob(paused.id); return }
        guard activeQueueTasks == 0 else { return }
        let failedCount = queueJobs.filter { if case .failed = $0.state { return true }; return false }.count
        if failedCount > 0 { fail(failedCount == 1 ? "1 queued export failed. Open the export queue for details." : "\(failedCount) queued exports failed. Open the export queue for details.") }
        if !queueJobs.contains(where: \.isPending) {
            let doneCount = queueJobs.filter { $0.state == .done }.count
            if doneCount > 0 || failedCount > 0 { ExportNotifications.notifyQueueSummary(done: doneCount, failed: failedCount) }
            QueuePersistence.clear()
        }
        schedulePersistedSave()
        endQueueSleep()
        ExportActivity.shared.active = false
        ExportActivity.shared.cancel = nil
        if ExportActivity.shared.terminating { NSApp.reply(toApplicationShouldTerminate: true) }
    }
    private func beginQueueSleep() {
        if !queueSleeping { IdleSleepActivity.begin(); queueSleeping = true }
    }
    private func endQueueSleep() {
        if queueSleeping { IdleSleepActivity.end(); queueSleeping = false }
    }
    private func startQueueJob(_ id: UUID) {
        guard let index = queueJobs.firstIndex(where: { $0.id == id }), queueJobs[index].state == .queued else { return }
        queueHoldFlag = false
        beginQueueSleep()
        queueJobs[index].state = .running(progress: 0)
        let running = RunningJob()
        queueRunning[id] = running
        ExportActivity.shared.active = true
        ExportActivity.shared.cancel = { [weak self] in MainActor.assumeIsolated { self?.queueRunning.values.forEach { $0.cancel() } } }
        activeQueueTasks += 1
        Task { @MainActor in
            await runQueueJob(id, running: running)
            activeQueueTasks -= 1
            scheduleNextQueueJob()
        }
    }
    func pauseQueueJob(_ id: UUID) {
        guard let index = queueJobs.firstIndex(where: { $0.id == id }), case .running(let value) = queueJobs[index].state else { return }
        queueRunning[id]?.pause()
        queueJobs[index].state = .paused(progress: value)
        queueHoldFlag = true
        endQueueSleep()
    }
    /// Resume a paused job. Only while no other job is running.
    func resumeQueueJob(_ id: UUID) {
        guard !queueJobs.contains(where: { $0.isRunning }),
              let index = queueJobs.firstIndex(where: { $0.id == id }), case .paused(let value) = queueJobs[index].state else { return }
        queueHoldFlag = false
        beginQueueSleep()
        queueJobs[index].state = .running(progress: value)
        queueRunning[id]?.resume()
    }
    /// Start a waiting job now. Only while no other job is running (for example while one is paused); the paused job stays paused.
    func runQueueJobNow(_ id: UUID) {
        guard !queueJobs.contains(where: { $0.isRunning }),
              let index = queueJobs.firstIndex(where: { $0.id == id }), queueJobs[index].state == .queued else { return }
        moveQueueJobToFront(id)
        startQueueJob(id)
    }
    /// Put a waiting job first among the waiting jobs, so it runs next.
    func moveQueueJobToFront(_ id: UUID) {
        guard let index = queueJobs.firstIndex(where: { $0.id == id }), queueJobs[index].state == .queued,
              let firstWaiting = queueJobs.firstIndex(where: { $0.state == .queued }), firstWaiting < index else { return }
        let moved = queueJobs.remove(at: index)
        queueJobs.insert(moved, at: firstWaiting)
    }
    private func runQueueJob(_ jobID: UUID, running: RunningJob) async {
        progress = 0
        var workingSources = self[job: jobID].sources
        let mode = self[job: jobID].mode
        let output = self[job: jobID].output
        let planTracks = self[job: jobID].tracks
        defer {
            detachQueueISO(jobID: jobID)
            queueRunning[jobID] = nil
        }
        if let missing = missingQueueSources(job: self[job: jobID]) {
            self[job: jobID].state = .failed(missing)
            progress = 0
            notifyQueueJob(self[job: jobID])
            return
        }
        do {
            try await ensureQueueISOMounted(jobID: jobID, sources: &workingSources)
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
            let encoder = CompressEncoder.current
            let warnings = try await Task.detached(priority: .userInitiated) { [running] in
                if mode == .compress, let handbrake {
                    return try Engine.exportCompressed(plan: plan, output: output, mkvmerge: engine, handbrake: handbrake, job: running, encoder: encoder) { update in
                        Task { @MainActor in self.updateQueueProgress(jobID: jobID, update: update) }
                    }
                }
                return try Engine.export(plan: plan, output: output, engine: engine, job: running) { update in
                    Task { @MainActor in self.updateQueueProgress(jobID: jobID, update: update) }
                }
            }.value
            self[job: jobID].warning = warnings
            self[job: jobID].state = .done
            progress = 1
            notifyQueueJob(self[job: jobID])
        } catch is CancellationError {
            self[job: jobID].state = .cancelled
            progress = 0
        } catch {
            self[job: jobID].state = .failed(error.localizedDescription)
            progress = 0
            notifyQueueJob(self[job: jobID])
        }
        schedulePersistedSave()
    }
    private func missingQueueSources(job: QueueJob) -> String? {
        let fm = FileManager.default
        for source in job.sources {
            let path = (source.originURL ?? source.url).path
            if !fm.fileExists(atPath: path) { return "Source file is missing: \(URL(fileURLWithPath: path).lastPathComponent)" }
        }
        return nil
    }
    private func notifyQueueJob(_ job: QueueJob) {
        guard !sessionNotifications.contains(job.id) else { return }
        sessionNotifications.insert(job.id)
        switch job.state {
        case .done:
            ExportNotifications.notify(title: "Export finished", body: job.output.lastPathComponent, output: job.output)
        case .failed(let text):
            ExportNotifications.notify(title: "Export failed", body: text.components(separatedBy: .newlines).first ?? job.output.lastPathComponent, output: nil)
        default: break
        }
    }
    /// Job lookup by id. Writes to a job that no longer exists are ignored.
    private subscript(job id: UUID) -> QueueJob {
        get { queueJobs.first { $0.id == id } ?? QueueJob(id: id, sources: [], tracks: [], mode: .mux, output: URL(fileURLWithPath: "/"), state: .cancelled, warning: nil) }
        set { if let i = queueJobs.firstIndex(where: { $0.id == id }) { queueJobs[i] = newValue } }
    }
    private func updateQueueProgress(jobID: UUID, update: JobProgress) {
        guard let index = queueJobs.firstIndex(where: { $0.id == jobID }) else { return }
        switch queueJobs[index].state {
        case .running:
            queueJobs[index].state = .running(progress: update.value)
            queueJobs[index].progressPhase = update.phase
            queueJobs[index].progressFPS = update.fps
            queueJobs[index].progressETA = update.etaSeconds
        case .paused:
            queueJobs[index].state = .paused(progress: update.value)
            queueJobs[index].progressPhase = update.phase
            queueJobs[index].progressFPS = update.fps
            queueJobs[index].progressETA = update.etaSeconds
        default: return
        }
        progress = update.value
    }
    func cancelQueueJob(_ id: UUID) {
        guard let index = queueJobs.firstIndex(where: { $0.id == id }) else { return }
        switch queueJobs[index].state {
        case .running, .paused: queueRunning[id]?.cancel()
        case .queued: queueJobs[index].state = .cancelled
        default: break
        }
    }
    func removeQueueJob(_ id: UUID) {
        guard let index = queueJobs.firstIndex(where: { $0.id == id }) else { return }
        switch queueJobs[index].state {
        case .running, .paused: queueRunning[id]?.cancel()
        case .queued: queueJobs.remove(at: index)
        case .done, .failed, .cancelled: queueJobs.remove(at: index)
        }
        schedulePersistedSave()
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
            let encoder = CompressEncoder.current
            let warnings = try await Task.detached(priority: .userInitiated) { [weak self] in
                if mode == .compress, let handbrake {
                    return try Engine.exportCompressed(plan: plan, output: output, mkvmerge: engine, handbrake: handbrake, job: running, encoder: encoder) { [weak self] update in
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
    func waitForQueueIdle() async {
        while queueHasPendingExport || activeQueueTasks > 0 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}

final class ExportActivity { static let shared = ExportActivity(); var active = false; var terminating = false; var cancel: (() -> Void)? }
