// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import SwiftUI
import AppKit

@main struct MuxieApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var updater = UpdaterModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Window("Muxie", id: "main") {
            ContentView().environmentObject(model)
                .frame(minWidth: model.sources.isEmpty && model.queueJobs.isEmpty ? 380 : 560, idealWidth: 760, minHeight: model.minimumContentHeight, idealHeight: 520)
                .onAppear { delegate.bind(model) }
                .onOpenURL { url in Task { await model.importFiles([url]) } }
                .alert("Unable to Complete", isPresented: $model.showError) {
                    Button("Copy Details") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.error ?? "", forType: .string) }
                    Button("OK", role: .cancel) { }
                } message: { Text(model.error ?? "Unknown error") }
                .sheet(isPresented: $model.showAbout) { AboutView() }
        }
        .defaultSize(width: 760, height: 520)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .windowResizability(.contentMinSize)
        Settings { SettingsView() }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Muxie") { model.showAbout = true }
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheck || model.busy || model.queueHasPendingExport)
            }
            CommandGroup(replacing: .help) {
                Button("Contact Developer") { NSWorkspace.shared.open(URL(string: "https://github.com/joey4wong/Muxie")!) }
            }
            CommandGroup(replacing: .newItem) {
                Button("New Project") { model.reset() }.keyboardShortcut("n").disabled(model.importing || model.sources.isEmpty)
                Button("Open Video…") { model.openFiles() }.keyboardShortcut("o").disabled(model.importing || !model.sources.isEmpty)
                Button("Add Tracks…") { model.openFiles(additional: true) }.keyboardShortcut("o", modifiers: [.command, .shift]).disabled(model.importing || model.sources.isEmpty)
                Divider()
                Button("Export…") { model.exportPanel() }.keyboardShortcut("e").disabled(!model.canExport)
            }
        }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var model: AppModel?
    func bind(_ model: AppModel) { self.model = model }
    func applicationDidFinishLaunching(_ notification: Notification) {
        BluRayISO.recoverStaleMounts()
        Task.detached(priority: .utility) { TempFileRegistry.cleanupStale() }
        Task { @MainActor in
            model?.recoverStaleISOMounts()
            model?.restorePersistedQueue()
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if ExportActivity.shared.active {
            let alert = NSAlert(); alert.messageText = "Exports in progress"; alert.informativeText = "Quit and cancel all queued exports?"; alert.addButton(withTitle: "Continue Exports"); alert.addButton(withTitle: "Cancel and Quit")
            if alert.runModal() == .alertFirstButtonReturn { return .terminateCancel }
            ExportActivity.shared.cancel?(); ExportActivity.shared.terminating = true
            return .terminateLater
        }
        BluRayISO.recoverStaleMounts()
        return .terminateNow
    }
}
