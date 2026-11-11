// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import SwiftUI
import AppKit

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
                Text(job.isRunning || job.isPaused ? job.statusSubtitle : job.mode.label + " · " + job.statusTitle + (job.state == .done && job.warning != nil ? " with warnings" : "")).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if job.isRunning || job.isPaused {
                ChargingBar(progress: job.progress, animating: job.isRunning).frame(minWidth: 50, maxWidth: 140).frame(height: 6)
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
                if let warning = job.warning {
                    Button("Warnings", systemImage: "exclamationmark.triangle") { model.fail(warning) }.labelStyle(.iconOnly).help("Show warnings").buttonStyle(NeutralGlassButtonStyle()).fixedSize()
                }
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

/// Frame rate of the charging glow. The sweep and pulse are time based, so a lower rate only makes the glow slightly
/// coarser; redrawing every display frame for a 6 pt bar kept the main thread and WindowServer busy for the whole encode.
private let chargingFramesPerSecond = 24.0

private struct ChargingBar: View {
    let progress: Double
    let animating: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// False while every Muxie window is hidden, minimised or fully covered: nobody can see the glow then.
    @State private var windowVisible = NSApp.occlusionState.contains(.visible)
    var body: some View {
        GeometryReader { geo in
            let p = min(max(progress, 0), 1)
            let fillWidth = geo.size.width * p
            let amber = Color(red: 1.0, green: 0.78, blue: 0.0)
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.15))
                Capsule().fill(LinearGradient(colors: [Color(red: 0.95, green: 0.62, blue: 0.0), amber, Color(red: 1.0, green: 0.92, blue: 0.3)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: fillWidth)
                    .overlay(alignment: .leading) {
                        if animating && !reduceMotion {
                            TimelineView(.animation(minimumInterval: 1 / chargingFramesPerSecond, paused: !windowVisible)) { context in
                                let period = 1.6 - 1.0 * p
                                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                                let glow = max(fillWidth * 0.45, 16)
                                let pulse = 0.5 + 0.5 * sin(context.date.timeIntervalSinceReferenceDate * (3 + 8 * p))
                                ZStack(alignment: .leading) {
                                    Color.white.opacity(0.10 * p + 0.20 * p * pulse)
                                    LinearGradient(colors: [.clear, .white.opacity(0.35 + 0.6 * p), .clear], startPoint: .leading, endPoint: .trailing)
                                        .frame(width: glow)
                                        .offset(x: -glow + (fillWidth + glow) * t)
                                }
                            }
                        }
                    }
                    .clipShape(Capsule())
                    .shadow(color: amber.opacity(animating ? 0.9 * p * p : 0), radius: 2 + 8 * p)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeOcclusionStateNotification)) { _ in
            windowVisible = NSApp.occlusionState.contains(.visible)
        }
        .accessibilityElement()
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}
