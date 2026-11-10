// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import Foundation

struct PersistedQueue: Codable, Equatable {
    var jobs: [PersistedQueueJob]
    var hold: Bool
    var resumePending: Bool
}

struct PersistedQueueJob: Codable, Equatable {
    var job: QueueJob
    var wasInterrupted: Bool
}

enum QueuePersistence {
    private static let fileName = "queue.json"

    static var supportDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["MUXIE_APP_SUPPORT"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Muxie", isDirectory: true)
    }

    static var fileURL: URL { supportDirectory.appendingPathComponent(fileName) }

    static func save(jobs: [QueueJob], hold: Bool, resumePending: Bool) {
        let fm = FileManager.default
        try? fm.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let persisted = PersistedQueue(jobs: jobs.map { PersistedQueueJob(job: $0, wasInterrupted: false) }, hold: hold, resumePending: resumePending)
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Snapshots running or paused jobs as queued for relaunch.
    static func saveForTermination(jobs: [QueueJob], hold: Bool, resumePending: Bool) {
        let normalized = jobs.map { job -> PersistedQueueJob in
            var copy = job
            let interrupted: Bool
            switch job.state {
            case .running(let value), .paused(let value):
                interrupted = true
                copy.state = .queued
                copy.progressPhase = nil
                copy.progressFPS = nil
                copy.progressETA = nil
                _ = value
            default:
                interrupted = false
            }
            return PersistedQueueJob(job: copy, wasInterrupted: interrupted)
        }
        let persisted = PersistedQueue(jobs: normalized, hold: hold || normalized.contains(where: \.wasInterrupted), resumePending: resumePending || normalized.contains(where: \.wasInterrupted))
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func load() -> PersistedQueue? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(PersistedQueue.self, from: data)
    }

    static func clear() { try? FileManager.default.removeItem(at: fileURL) }
}
