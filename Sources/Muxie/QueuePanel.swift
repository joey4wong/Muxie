// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import SwiftUI

/// Export jobs listed at the top of the main window (running, queued and finished). Hidden when there are none.
struct QueueStripView: View {
    @EnvironmentObject var model: AppModel
    private let rowHeight: CGFloat = 46
    var body: some View {
        if !model.queueJobs.isEmpty {
            let visibleRows = min(model.queueJobs.count, 3)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.queueJobs) { job in queueRow(job) }
                }
            }
            .scrollIndicators(.hidden)
            .frame(height: CGFloat(visibleRows) * rowHeight + CGFloat(visibleRows - 1) * 6)
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)
        }
    }
    @ViewBuilder private func queueRow(_ job: QueueJob) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(job.output.lastPathComponent).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text(job.isRunning || job.isPaused ? job.statusSubtitle : job.mode.label + " · " + job.statusTitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if job.isRunning || job.isPaused {
                ProgressView(value: job.progress).frame(minWidth: 50, maxWidth: 140)
                Text("\(Int(job.progress * 100))%").font(.system(size: 10, design: .monospaced)).monospacedDigit().frame(width: 34, alignment: .trailing)
            }
            let anyRunning = model.queueJobs.contains { $0.isRunning }
            switch job.state {
            case .queued:
                // While another job runs the button moves this one up the line; while the queue is paused it starts this one now.
                if anyRunning {
                    Button("Run Next") { model.moveQueueJobToFront(job.id) }.buttonStyle(NeutralGlassButtonStyle()).fixedSize()
                } else {
                    Button("Run Now") { model.runQueueJobNow(job.id) }.buttonStyle(NeutralGlassButtonStyle()).fixedSize()
                }
                Button("Remove") { model.removeQueueJob(job.id) }.buttonStyle(NeutralGlassButtonStyle()).fixedSize()
            case .running:
                Button("Pause", systemImage: "pause.fill") { model.pauseQueueJob(job.id) }.labelStyle(.iconOnly).help("Pause").buttonStyle(NeutralGlassButtonStyle()).fixedSize()
                Button("Cancel", systemImage: "xmark", role: .cancel) { model.cancelQueueJob(job.id) }.labelStyle(.iconOnly).help("Cancel").buttonStyle(NeutralGlassButtonStyle()).fixedSize()
            case .paused:
                if !anyRunning { Button("Resume", systemImage: "play.fill") { model.resumeQueueJob(job.id) }.labelStyle(.iconOnly).help("Resume").buttonStyle(NeutralGlassButtonStyle()).fixedSize() }
                Button("Cancel", systemImage: "xmark", role: .cancel) { model.cancelQueueJob(job.id) }.labelStyle(.iconOnly).help("Cancel").buttonStyle(NeutralGlassButtonStyle()).fixedSize()
            case .done:
                Button("Show in Finder", systemImage: "folder") { model.revealQueueOutput(job.output) }.buttonStyle(NeutralGlassButtonStyle()).fixedSize()
                Button("Clear") { model.clearFinishedQueueJob(job.id) }.buttonStyle(NeutralGlassButtonStyle()).fixedSize()
            case .failed(let text):
                Button("Copy Details") { model.copyQueueFailure(job.id); model.fail(text) }.buttonStyle(NeutralGlassButtonStyle()).fixedSize()
                Button("Clear") { model.clearFinishedQueueJob(job.id) }.buttonStyle(NeutralGlassButtonStyle()).fixedSize()
            case .cancelled:
                Button("Clear") { model.clearFinishedQueueJob(job.id) }.buttonStyle(NeutralGlassButtonStyle()).fixedSize()
            }
        }
        .padding(.horizontal, 14).frame(height: rowHeight)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
    }
}
