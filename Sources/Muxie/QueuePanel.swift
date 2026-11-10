// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import SwiftUI

struct QueuePanelView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exports").font(.system(size: 13, weight: .semibold))
            if model.queueJobs.isEmpty {
                Text("No queued exports.").font(.callout).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(model.queueJobs) { job in queueRow(job) }
                    }
                }.frame(maxHeight: 320)
            }
        }.padding(16).frame(width: 380)
    }
    @ViewBuilder private func queueRow(_ job: QueueJob) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(job.output.lastPathComponent).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Spacer()
                Text(job.statusTitle).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Text(job.mode.label).font(.system(size: 10)).foregroundStyle(.tertiary)
            if case .running(let value) = job.state {
                ProgressView(value: value)
                Text("\(Int(value * 100))%").font(.system(size: 10, design: .monospaced))
            }
            HStack(spacing: 8) {
                switch job.state {
                case .queued, .running:
                    Button("Cancel", role: .cancel) { model.cancelQueueJob(job.id) }.buttonStyle(NeutralGlassButtonStyle())
                    if job.state == .queued {
                        Button("Remove") { model.removeQueueJob(job.id) }.buttonStyle(NeutralGlassButtonStyle())
                    }
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
        }
        .padding(10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
    }
}
