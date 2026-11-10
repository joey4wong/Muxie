// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import Foundation

enum ExportPhase: String, Sendable, Codable {
    case prepare, encode, finalize, mux
}

struct JobProgress: Sendable {
    var value: Double
    var phase: ExportPhase?
    var fps: Double?
    var etaSeconds: TimeInterval?

    static func fraction(_ value: Double) -> JobProgress { JobProgress(value: value, phase: nil, fps: nil, etaSeconds: nil) }
}
