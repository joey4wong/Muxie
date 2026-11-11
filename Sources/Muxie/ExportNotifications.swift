// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import Foundation
import UserNotifications

enum ExportNotifications {
    private static var requested = false

    /// UNUserNotificationCenter requires a host app bundle; processes without one (the test harness)
    /// cannot present notifications and would crash the framework instead.
    private static var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestAuthorizationIfNeeded() {
        guard !requested, canNotify else { return }
        requested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notify(title: String, body: String, output: URL?) {
        guard canNotify else { return }
        requestAuthorizationIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let output { content.userInfo = ["reveal": output.path] }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func notifyQueueSummary(done: Int, failed: Int) {
        guard done > 0 || failed > 0 else { return }
        let title = failed > 0 ? "Exports finished with errors" : "All exports finished"
        var parts: [String] = []
        if done > 0 { parts.append("\(done) completed") }
        if failed > 0 { parts.append("\(failed) failed") }
        notify(title: title, body: parts.joined(separator: ", "), output: nil)
    }
}
