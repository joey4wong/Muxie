// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import Foundation
import SwiftUI

enum QueueJobState: Equatable, Codable {
    case queued
    case running(progress: Double)
    case paused(progress: Double)
    case done
    case failed(String)
    case cancelled

    enum CodingKeys: String, CodingKey { case kind, progress, message }
    enum Kind: String, Codable { case queued, running, paused, done, failed, cancelled }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .queued: self = .queued
        case .running: self = .running(progress: try c.decode(Double.self, forKey: .progress))
        case .paused: self = .paused(progress: try c.decode(Double.self, forKey: .progress))
        case .done: self = .done
        case .failed: self = .failed(try c.decode(String.self, forKey: .message))
        case .cancelled: self = .cancelled
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .queued: try c.encode(Kind.queued, forKey: .kind)
        case .running(let value): try c.encode(Kind.running, forKey: .kind); try c.encode(value, forKey: .progress)
        case .paused(let value): try c.encode(Kind.paused, forKey: .kind); try c.encode(value, forKey: .progress)
        case .done: try c.encode(Kind.done, forKey: .kind)
        case .failed(let text): try c.encode(Kind.failed, forKey: .kind); try c.encode(text, forKey: .message)
        case .cancelled: try c.encode(Kind.cancelled, forKey: .kind)
        }
    }
}

struct QueueJob: Identifiable, Equatable, Sendable, Codable {
    let id: UUID
    let sources: [MediaSource]
    let tracks: [MediaTrack]
    let mode: ExportMode
    let output: URL
    var state: QueueJobState
    var warning: String?
    var progressPhase: ExportPhase? = nil
    var progressFPS: Double? = nil
    var progressETA: TimeInterval? = nil
    var interruptedNote: String? = nil
    var encoder: CompressEncoder? = nil

    var isRunning: Bool { if case .running = state { return true }; return false }
    var isPaused: Bool { if case .paused = state { return true }; return false }
    var isPending: Bool { state == .queued || isRunning || isPaused }
    var progress: Double {
        switch state {
        case .running(let value), .paused(let value): return value
        default: return 0
        }
    }

    static func snapshot(sources: [MediaSource], tracks: [MediaTrack], mode: ExportMode, output: URL) -> QueueJob {
        let snapSources = sources.map { source -> MediaSource in
            guard let iso = source.originURL else { return source }
            var copy = source
            copy.url = iso
            copy.originURL = iso
            copy.appendedParts = []
            return copy
        }
        return QueueJob(id: UUID(), sources: snapSources, tracks: tracks, mode: mode, output: output, state: .queued, warning: nil, progressPhase: nil, progressFPS: nil, progressETA: nil, interruptedNote: nil, encoder: mode == .compress ? CompressEncoder.current : nil)
    }

    var statusTitle: String {
        switch state {
        case .queued: return interruptedNote == nil ? "Queued" : "Queued (interrupted)"
        case .running: return "Running"
        case .paused: return "Paused"
        case .done: return "Done"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    var statusSubtitle: String {
        var parts = [mode.label, phaseLabel]
        if let encoder { parts.append(encoder.technology) }
        if let progressFPS { parts.append(String(format: "%.0f fps", progressFPS)) }
        if let progressETA, progressETA > 0 { parts.append("ETA \(Self.formatETA(progressETA))") }
        return parts.joined(separator: " · ")
    }

    private var phaseLabel: String {
        switch progressPhase {
        case .prepare: return "Preparing"
        case .encode: return "Encoding"
        case .finalize: return "Finalizing"
        case .mux: return "Muxing"
        case .none: return statusTitle
        }
    }

    private static func formatETA(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

enum ExportMode: String, CaseIterable, Identifiable, Codable {
    case mux, compress
    var id: String { rawValue }
    var label: String { self == .mux ? "Mux" : "Compress" }
}
