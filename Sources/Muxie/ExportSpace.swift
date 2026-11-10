// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import Foundation

enum ExportSpace {
    /// Conservative compressed output size as a fraction of checked input bytes (tunable).
    static let compressOutputRatio: Double = 0.5

    static func checkedInputBytes(plan: ExportPlan) -> Int64 {
        let active = Set(plan.tracks.filter(\.enabled).map(\.sourceID))
        return plan.sources.filter { active.contains($0.id) }.reduce(Int64(0)) { $0 + $1.byteSize }
    }

    static func requiredBytes(mode: ExportMode, plan: ExportPlan) -> Int64 {
        let input = checkedInputBytes(plan: plan)
        guard mode == .compress else { return input }
        let outputEstimate = Int64((Double(input) * compressOutputRatio).rounded(.up))
        let staging = Int64((Double(input) * 0.20).rounded(.up))
        return input + max(outputEstimate, 1) + staging
    }

    static func spaceErrorMessage(required: Int64, available: Int64) -> String {
        "This export needs about \(BluRayISO.bytesDescription(required)) free on this disk; \(BluRayISO.bytesDescription(available)) is available."
    }

    static func verifySpace(mode: ExportMode, plan: ExportPlan, destination: URL) throws {
        let fsAttrs = try FileManager.default.attributesOfFileSystem(forPath: destination.path)
        let freeBytes = (fsAttrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        let required = requiredBytes(mode: mode, plan: plan)
        guard freeBytes >= required else {
            throw MuxError.message(spaceErrorMessage(required: required, available: freeBytes))
        }
    }
}
