// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import Foundation

enum IdleSleepActivity {
    static var provider: (String) -> (() -> Void) = { reason in
        let token = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: reason)
        return { ProcessInfo.processInfo.endActivity(token) }
    }
    private static var endActivity: (() -> Void)?

    static func begin(reason: String = "Muxie export") {
        endActivity = provider(reason)
    }

    static func end() {
        endActivity?()
        endActivity = nil
    }
}
