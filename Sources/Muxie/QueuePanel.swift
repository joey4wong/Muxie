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
                Text(job.output.lastPathComponent).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Text(job.mode.label + " · " + job.statusTitle).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if job.isRunning || job.isPaused {
                ProgressView(value: job.progress).frame(width: 140)
                Text("\(Int(job.progress * 100))%").font(.system(size: 10, design: .monospaced)).monospacedDigit().frame(width: 34, alignment: .trailing)
            }
            let anyRunning = model.queueJobs.contains { $0.isRunning }
            switch job.state {
            case .queued:
                // While another job runs the button moves this one up the line; while the queue is paused it starts this one now.
                if anyRunning {
                    Button("Run Next") { model.moveQueueJobToFront(job.id) }.buttonStyle(NeutralGlassButtonStyle())
                } else {
                    Button("Run Now") { model.runQueueJobNow(job.id) }.buttonStyle(NeutralGlassButtonStyle())
                }
                Button("Remove") { model.removeQueueJob(job.id) }.buttonStyle(NeutralGlassButtonStyle())
            case .running:
                Button("Pause") { model.pauseQueueJob(job.id) }.buttonStyle(NeutralGlassButtonStyle())
                Button("Cancel", role: .cancel) { model.cancelQueueJob(job.id) }.buttonStyle(NeutralGlassButtonStyle())
            case .paused:
                if !anyRunning { Button("Resume") { model.resumeQueueJob(job.id) }.buttonStyle(NeutralGlassButtonStyle()) }
                Button("Cancel", role: .cancel) { model.cancelQueueJob(job.id) }.buttonStyle(NeutralGlassButtonStyle())
            case .done:
                Button("Show in Finder", systemImage: "folder") { model.revealQueueOutput(job.output) }.buttonStyle(NeutralGlassButtonStyle())
                Button("Clear") { model.clearFinishedQueueJob(job.id) }.buttonStyle(NeutralGlassButtonStyle())
            case .failed(let text):
                Button("Copy Details") { model.copyQueueFailure(job.id); model.fail(text) }.buttonStyle(NeutralGlassButtonStyle())
                Button("Clear") { model.clearFinishedQueueJob(job.id) }.buttonStyle(NeutralGlassButtonStyle())
            case .cancelled:
                Button("Clear") { model.clearFinishedQueueJob(job.id) }.buttonStyle(NeutralGlassButtonStyle())
            }
        }
        .padding(.horizontal, 14).frame(height: rowHeight)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
    }
}
