// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import Foundation

struct TempFileRecord: Codable, Equatable {
    var path: String
    var pid: Int32
}

enum TempFileRegistry {
    private static let fileName = "temp-files.json"
    private static let fm = FileManager.default

    static var supportDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["MUXIE_APP_SUPPORT"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Muxie", isDirectory: true)
    }

    static var registryURL: URL { supportDirectory.appendingPathComponent(fileName) }

    static func isManagedPartialFileName(_ name: String) -> Bool {
        (name.hasPrefix(".muxie-") || name.hasPrefix("Muxie temp - ")) && name.hasSuffix(".partial.mkv")
    }

    static func register(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard isManagedPartialFileName(url.lastPathComponent) else { return }
        var records = load()
        records.removeAll { $0.path == path }
        records.append(TempFileRecord(path: path, pid: ProcessInfo.processInfo.processIdentifier))
        save(records)
    }

    static func unregister(_ url: URL) {
        let path = url.standardizedFileURL.path
        var records = load()
        records.removeAll { $0.path == path }
        save(records)
    }

    static func load() -> [TempFileRecord] {
        guard let data = try? Data(contentsOf: registryURL),
              let records = try? JSONDecoder().decode([TempFileRecord].self, from: data) else { return [] }
        return records
    }

    static func save(_ records: [TempFileRecord]) {
        try? fm.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(records) else { return }
        let temp = registryURL.appendingPathExtension("new")
        do {
            try data.write(to: temp, options: .atomic)
            if fm.fileExists(atPath: registryURL.path) { try fm.removeItem(at: registryURL) }
            try fm.moveItem(at: temp, to: registryURL)
        } catch {
            try? fm.removeItem(at: temp)
        }
    }

    static func isProcessRunning(pid: Int32) -> Bool {
        if pid == ProcessInfo.processInfo.processIdentifier { return true }
        return kill(pid, 0) == 0
    }

    static func cleanupStale() {
        var kept: [TempFileRecord] = []
        for record in load() {
            if isProcessRunning(pid: record.pid) {
                kept.append(record)
                continue
            }
            let url = URL(fileURLWithPath: record.path)
            let name = url.lastPathComponent
            guard fm.fileExists(atPath: record.path) else { continue }
            guard isManagedPartialFileName(name) else {
                kept.append(record)
                continue
            }
            try? fm.removeItem(at: url)
            if fm.fileExists(atPath: record.path) { kept.append(record) }
        }
        save(kept)
    }

    static func replaceAll(_ records: [TempFileRecord]) { save(records) }
}
