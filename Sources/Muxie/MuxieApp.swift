// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import SwiftUI
import AppKit

@main struct MuxieApp: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Window("Muxie", id: "main") {
            ContentView().environmentObject(model)
                .frame(minWidth: 780, idealWidth: 980, minHeight: 500, idealHeight: 640)
                .onOpenURL { url in Task { await model.importFiles([url]) } }
                .alert("Unable to Complete", isPresented: $model.showError) {
                    Button("Copy Details") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.error ?? "", forType: .string) }
                    Button("OK", role: .cancel) { }
                } message: { Text(model.error ?? "Unknown error") }
                .sheet(isPresented: $model.showAbout) { AboutView() }
        }
        .defaultSize(width: 980, height: 640)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) { Button("About Muxie") { model.showAbout = true } }
            CommandGroup(replacing: .newItem) {
                Button("New Project") { model.reset() }.keyboardShortcut("n").disabled(model.busy || model.sources.isEmpty)
                Button("Open Video…") { model.openFiles() }.keyboardShortcut("o").disabled(model.busy || !model.sources.isEmpty)
                Button("Add Tracks…") { model.openFiles(additional: true) }.keyboardShortcut("o", modifiers: [.command, .shift]).disabled(model.busy || model.sources.isEmpty)
                Divider()
                Button("Export MKV…") { model.exportPanel() }.keyboardShortcut("e").disabled(!model.canExport)
            }
        }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if ExportActivity.shared.active {
            let alert = NSAlert(); alert.messageText = "Export in progress"; alert.informativeText = "Quit and cancel the export?"; alert.addButton(withTitle: "Continue Export"); alert.addButton(withTitle: "Cancel and Quit")
            if alert.runModal() == .alertFirstButtonReturn { return .terminateCancel }
            ExportActivity.shared.cancel?(); ExportActivity.shared.terminating = true
            return .terminateLater
        }
        return .terminateNow
    }
}
