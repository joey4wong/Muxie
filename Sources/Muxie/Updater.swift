// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import SwiftUI
import Combine
import Sparkle

/// Wraps Sparkle's standard updater. Checks are manual only (Info.plist disables background checks).
@MainActor final class UpdaterModel: ObservableObject {
    private let controller: SPUStandardUpdaterController
    @Published private(set) var canCheck = false

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheck)
    }

    func checkForUpdates() { controller.checkForUpdates(nil) }
}
