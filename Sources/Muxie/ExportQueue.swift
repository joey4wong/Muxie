// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import Foundation
import SwiftUI

enum QueueJobState: Equatable {
    case queued
    case running(progress: Double)
    case paused(progress: Double)
    case done
    case failed(String)
    case cancelled
}

struct QueueJob: Identifiable, Equatable, Sendable {
    let id: UUID
    let sources: [MediaSource]
    let tracks: [MediaTrack]
    let mode: ExportMode
    let output: URL
    var state: QueueJobState
    var warning: String?

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
        return QueueJob(id: UUID(), sources: snapSources, tracks: tracks, mode: mode, output: output, state: .queued, warning: nil)
    }

    var statusTitle: String {
        switch state {
        case .queued: return "Queued"
        case .running: return "Running"
        case .paused: return "Paused"
        case .done: return "Done"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

