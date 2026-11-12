// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import Foundation

extension AppModel {
    func recoverStaleISOMounts() { BluRayISO.recoverStaleMounts(); isoMounts = [:] }
    func detachAllISO() {
        for mount in isoMounts.values { BluRayISO.detach(mount) }
        isoMounts = [:]
    }
    func detachQueueISO(jobID: UUID) {
        for mount in (queueISOMounts.removeValue(forKey: jobID) ?? [:]).values { BluRayISO.detach(mount) }
    }
    func detachAllQueueISO() {
        for mounts in queueISOMounts.values { for mount in mounts.values { BluRayISO.detach(mount) } }
        queueISOMounts = [:]
    }
    func ensureISOMounted() async throws {
        for index in sources.indices {
            guard let iso = sources[index].originURL, isoMounts[sources[index].id] == nil else { continue }
            let mount = try await Task.detached(priority: .userInitiated) { try BluRayISO.attach(iso: iso) }.value
            isoMounts[sources[index].id] = mount
            sources[index].url = mount.mediaURL
            sources[index].byteSize = mount.inputBytes
            sources[index].appendedParts = mount.extraParts
        }
    }
    func ensureQueueISOMounted(jobID: UUID, sources: inout [MediaSource]) async throws {
        for index in sources.indices {
            guard let iso = sources[index].originURL, queueISOMounts[jobID]?[sources[index].id] == nil else { continue }
            let sourceID = sources[index].id
            let mount = try await Task.detached(priority: .userInitiated) { try BluRayISO.attach(iso: iso) }.value
            queueISOMounts[jobID, default: [:]][sourceID] = mount
            sources[index].url = mount.mediaURL
            sources[index].byteSize = mount.inputBytes
            sources[index].appendedParts = mount.extraParts
        }
    }
}
