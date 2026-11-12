// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import SwiftUI
import AppKit

extension AppModel {
    var queueHeld: Bool { queueHoldFlag && queueJobs.contains { $0.isPaused } }
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
    func enqueueExport(to output: URL) {
        let target = output.standardizedFileURL.resolvingSymlinksInPath()
        let taken = queueJobs.filter(\.isPending).map { $0.output.standardizedFileURL.resolvingSymlinksInPath() }
        if taken.contains(target) {
            fail("Another queued export already uses this output path.")
            return
        }
        queueJobs.append(QueueJob.snapshot(sources: sources, tracks: tracks, mode: exportMode, output: output, quality: exportMode == .compress ? compressQuality : nil))
        ExportNotifications.requestAuthorizationIfNeeded()
        schedulePersistedSave()
        reset()
        scheduleNextQueueJob()
    }
    func schedulePersistedSave() {
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
    func scheduleNextQueueJob() {
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
        } catch {
            self[job: jobID].state = .failed(error.localizedDescription)
            return
        }
        do {
            let handbrake = Engine.handbrakeExecutable
            // The encoder and quality chosen when the job was queued; the toolbar may have changed since.
            let encoder = self[job: jobID].encoder ?? CompressEncoder.current
            let quality = self[job: jobID].quality ?? CompressQuality()
            let warnings = try await Task.detached(priority: .userInitiated) { [running] in
                if mode == .compress, let handbrake {
                    return try Engine.exportCompressed(plan: plan, output: output, mkvmerge: engine, handbrake: handbrake, job: running, encoder: encoder, quality: quality) { update in
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
        case .paused:
            queueJobs[index].state = .paused(progress: update.value)
        default: return
        }
        queueJobs[index].progressPhase = update.phase
        queueJobs[index].progressFPS = update.fps
        queueJobs[index].progressETA = update.etaSeconds
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
    func waitForQueueIdle() async {
        while queueHasPendingExport || activeQueueTasks > 0 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
