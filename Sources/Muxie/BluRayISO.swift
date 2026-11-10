// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import Foundation

struct BluRayMount: Sendable, Equatable {
    var isoURL: URL
    var mountPoint: URL
    var device: String
    var m2tsURL: URL
    var m2tsName: String
    var m2tsBytes: Int64
}

enum BluRayISO {
    private static let persistenceKey = "isoMounts"
    private static let fm = FileManager.default

    static func recoverStaleMounts() {
        for record in storedRecords() { detachDevice(record.device) }
        saveRecords([])
    }

    static func attach(iso: URL) throws -> BluRayMount {
        let data = try runHdiutil(["attach", "-readonly", "-nobrowse", "-plist", iso.path])
        guard let objects = try PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]],
              let first = objects.first else { throw MuxError.message("Could not mount \(iso.lastPathComponent).") }
        let mountPoint = (first["mount-point"] as? String).map { URL(fileURLWithPath: $0, isDirectory: true) }
        let device = (first["dev-entry"] as? String) ?? (first["device"] as? String)
        guard let mountPoint, let device else {
            if let device { detachDevice(device) }
            throw MuxError.message("Could not mount \(iso.lastPathComponent).")
        }
        let layout = try classifyVolume(at: mountPoint)
        switch layout {
        case .encrypted:
            detachDevice(device)
            throw MuxError.message("This disc is encrypted. Muxie does not handle encrypted Blu-ray images.")
        case .dvd:
            detachDevice(device)
            throw MuxError.message("DVD ISO images are not supported yet.")
        case .unknown:
            detachDevice(device)
            throw MuxError.message("Unrecognized disc image.")
        case .bluRay:
            break
        }
        guard let feature = try largestM2TS(under: mountPoint) else {
            detachDevice(device)
            throw MuxError.message("No .m2ts files were found on this disc image.")
        }
        var mount = BluRayMount(isoURL: iso, mountPoint: mountPoint, device: device, m2tsURL: feature.url, m2tsName: feature.url.lastPathComponent, m2tsBytes: feature.bytes)
        remember(mount)
        return mount
    }

    static func detach(_ mount: BluRayMount) {
        detachDevice(mount.device)
        forget(device: mount.device)
    }

    private enum VolumeKind { case bluRay, dvd, encrypted, unknown }

    private static func classifyVolume(at mount: URL) throws -> VolumeKind {
        let bdmv = mount.appendingPathComponent("BDMV")
        let stream = bdmv.appendingPathComponent("STREAM")
        if fm.fileExists(atPath: bdmv.appendingPathComponent("AACS").path) { return .encrypted }
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
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/hdiutil")
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
