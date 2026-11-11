// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import Foundation

struct BluRayMount: Sendable, Equatable {
    var isoURL: URL
    var mountPoint: URL
    var device: String
    /// First clip of the main title. mkvmerge identifies this file; it must be a `.m2ts`, not the `.mpls` playlist:
    /// given a playlist, mkvmerge reports only the video track and chapters, so audio and subtitles would be lost.
    var mediaURL: URL
    /// The remaining clips of the main title, in playback order (appended to `mediaURL` with `+`).
    var extraParts: [URL] = []
    var inputBytes: Int64
}

enum BluRayISO {
    private static let persistenceKey = "isoMounts"
    private static let fm = FileManager.default

    static func recoverStaleMounts() {
        for record in storedRecords() { detachDevice(record.device) }
        saveRecords([])
    }

    /// Picks the largest `.mpls` file in `BDMV/PLAYLIST` (main-feature heuristic). Exposed for unit tests.
    static func longestPlaylist(under mount: URL) throws -> URL? {
        let playlist = mount.appendingPathComponent("BDMV/PLAYLIST", isDirectory: true)
        guard fm.fileExists(atPath: playlist.path) else { return nil }
        let entries = try fm.contentsOfDirectory(at: playlist, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
        return entries.compactMap { url -> (URL, Int64)? in
            guard url.pathExtension.lowercased() == "mpls" else { return nil }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            return (url, size)
        }.max(by: { lhs, rhs in
            // Longest running time wins; file size only breaks ties and covers playlists that cannot be parsed.
            let l = playlistSeconds(lhs.0), r = playlistSeconds(rhs.0)
            return l != r ? l < r : lhs.1 < rhs.1
        })?.0
    }

    struct PlayItem: Equatable {
        var clip: String
        var seconds: Double
    }

    /// Reads the PlayItems of an MPLS file: clip name (5 digits) and running time (45 kHz ticks). Returns nil if it is not a playlist.
    static func parsePlayItems(_ data: Data) -> [PlayItem]? {
        let b = [UInt8](data)
        guard b.count >= 12, Array(b[0..<4]) == Array("MPLS".utf8) else { return nil }
        func u32(_ o: Int) -> Int { (Int(b[o]) << 24) | (Int(b[o + 1]) << 16) | (Int(b[o + 2]) << 8) | Int(b[o + 3]) }
        func u16(_ o: Int) -> Int { (Int(b[o]) << 8) | Int(b[o + 1]) }
        let start = u32(8)
        guard start + 10 <= b.count else { return nil }
        let count = u16(start + 6)
        var p = start + 10
        var items: [PlayItem] = []
        for _ in 0..<count {
            guard p + 22 <= b.count else { return nil }
            let length = u16(p)
            guard length >= 20, let clip = String(bytes: b[(p + 2)..<(p + 7)], encoding: .ascii) else { return nil }
            let inTime = u32(p + 14), outTime = u32(p + 18)
            items.append(PlayItem(clip: clip, seconds: Double(max(0, outTime - inTime)) / 45_000))
            p += length + 2
        }
        return items.isEmpty ? nil : items
    }

    static func playlistSeconds(_ mpls: URL) -> Double {
        guard let data = try? Data(contentsOf: mpls), let items = parsePlayItems(data) else { return 0 }
        return items.reduce(0) { $0 + $1.seconds }
    }

    /// The `.m2ts` clips of the main title in playback order. Uses the main playlist when every clip it names exists and
    /// no clip repeats (a repeat would need in/out trimming, which appending cannot do); otherwise the largest clip.
    static func mainClips(under mount: URL) throws -> [URL] {
        let stream = mount.appendingPathComponent("BDMV/STREAM", isDirectory: true)
        if let mpls = try longestPlaylist(under: mount), let data = try? Data(contentsOf: mpls), let items = parsePlayItems(data) {
            let urls = items.map { stream.appendingPathComponent($0.clip + ".m2ts") }
            if Set(urls).count == urls.count, urls.allSatisfy({ fm.fileExists(atPath: $0.path) }) { return urls }
        }
        if let feature = try largestM2TS(under: mount) { return [feature.url] }
        return []
    }

    static func attach(iso: URL) throws -> BluRayMount {
        let data = try runHdiutil(["attach", "-readonly", "-nobrowse", "-noverify", "-plist", iso.path])
        let attached = try parseAttachOutput(data, isoName: iso.lastPathComponent)
        let device = attached.device
        let mountPoint = attached.mountPoint
        let layout = try classifyVolume(at: mountPoint)
        switch layout {
        case .dvd:
            detachDevice(device)
            throw MuxError.message("DVD ISO images are not supported yet.")
        case .unknown:
            detachDevice(device)
            throw MuxError.message("Unrecognized disc image.")
        case .bluRay:
            break
        }
        let isoBytes = (try? iso.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let clips = try mainClips(under: mountPoint)
        guard let mediaURL = clips.first else {
            detachDevice(device)
            throw MuxError.message("No Blu-ray playlist or feature file was found on this disc image.")
        }
        let mount = BluRayMount(isoURL: iso, mountPoint: mountPoint, device: device, mediaURL: mediaURL, extraParts: Array(clips.dropFirst()), inputBytes: isoBytes)
        remember(mount)
        return mount
    }

    /// `hdiutil attach -plist` prints a dictionary whose `system-entities` array lists the whole disk and
    /// every partition/volume; only the volume entity carries `mount-point`. Older/odd outputs may be a bare array.
    static func parseAttachOutput(_ data: Data, isoName: String) throws -> (device: String, mountPoint: URL) {
        let root = try? PropertyListSerialization.propertyList(from: data, format: nil)
        let entities: [[String: Any]]
        if let dict = root as? [String: Any], let list = dict["system-entities"] as? [[String: Any]] { entities = list }
        else if let list = root as? [[String: Any]] { entities = list }
        else { throw MuxError.message("Could not mount \(isoName).") }
        let devices = entities.compactMap { ($0["dev-entry"] as? String) ?? ($0["device"] as? String) }
        let wholeDisk = devices.min(by: { $0.count < $1.count })
        let mountPath = entities.compactMap { $0["mount-point"] as? String }.first
        guard let wholeDisk, let mountPath else {
            if let wholeDisk { detachDevice(wholeDisk) }
            throw MuxError.message("Could not mount \(isoName).")
        }
        return (wholeDisk, URL(fileURLWithPath: mountPath, isDirectory: true))
    }

    static func detach(_ mount: BluRayMount) {
        detachDevice(mount.device)
        forget(device: mount.device)
    }

    private enum VolumeKind { case bluRay, dvd, unknown }

    private static func classifyVolume(at mount: URL) throws -> VolumeKind {
        let bdmv = mount.appendingPathComponent("BDMV")
        let stream = bdmv.appendingPathComponent("STREAM")
        if fm.fileExists(atPath: stream.path) { return .bluRay }
        if fm.fileExists(atPath: mount.appendingPathComponent("VIDEO_TS").path) { return .dvd }
        return .unknown
    }

    private static func largestM2TS(under mount: URL) throws -> (url: URL, bytes: Int64)? {
        let stream = mount.appendingPathComponent("BDMV/STREAM")
        let entries = try fm.contentsOfDirectory(at: stream, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
        return entries.compactMap { url -> (URL, Int64)? in
            guard url.pathExtension.lowercased() == "m2ts" else { return nil }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            return (url, size)
        }.max(by: { $0.1 < $1.1 }).map { ($0.0, $0.1) }
    }

    private static func runHdiutil(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ["/usr/bin/hdiutil", "/usr/sbin/hdiutil"].first { fm.isExecutableFile(atPath: $0) } ?? "/usr/bin/hdiutil")
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let output = out.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            let detail = errorText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw MuxError.message(detail.isEmpty ? "hdiutil failed." : detail)
        }
        return output
    }

    private static func detachDevice(_ device: String) {
        _ = try? runHdiutil(["detach", device, "-force"])
        forget(device: device)
    }

    private struct Persisted: Codable {
        var device: String
        var mountPoint: String?
        var isoPath: String
    }

    private static func storedRecords() -> [Persisted] {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let records = try? JSONDecoder().decode([Persisted].self, from: data) else { return [] }
        return records
    }

    private static func saveRecords(_ records: [Persisted]) {
        let data = try? JSONEncoder().encode(records)
        UserDefaults.standard.set(data, forKey: persistenceKey)
    }

    private static func remember(_ mount: BluRayMount) {
        var records = storedRecords().filter { $0.device != mount.device }
        records.append(Persisted(device: mount.device, mountPoint: mount.mountPoint.path, isoPath: mount.isoURL.path))
        saveRecords(records)
    }

    private static func forget(device: String) {
        saveRecords(storedRecords().filter { $0.device != device })
    }

    static func bytesDescription(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
