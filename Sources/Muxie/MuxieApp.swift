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
                .frame(minWidth: 1100, idealWidth: 1210, minHeight: 740, idealHeight: 790)
                .onOpenURL { url in Task { await model.importFiles([url]) } }
                .alert("操作未完成", isPresented: $model.showError) {
                    Button("复制详情") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.error ?? "", forType: .string) }
                    Button("好", role: .cancel) { }
                } message: { Text(model.error ?? "未知错误") }
                .sheet(isPresented: $model.showAbout) { AboutView().environmentObject(model) }
        }
        .defaultSize(width: 1210, height: 790)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .appInfo) { Button("关于 Muxie") { model.showAbout = true } }
            CommandGroup(replacing: .newItem) {
                Button("添加影片…") { model.openFiles() }.keyboardShortcut("o").disabled(model.busy || !model.sources.isEmpty)
                Button("添加音轨或字幕…") { model.openFiles(additional: true) }.keyboardShortcut("o", modifiers: [.command, .shift]).disabled(model.busy || model.sources.isEmpty)
                Divider()
                Button("导出 MKV…") { model.exportPanel() }.keyboardShortcut("e").disabled(!model.canExport)
            }
        }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if ProcessInfo.processInfo.arguments.contains("--self-test") { return .terminateNow }
        // Active helpers must not outlive the UI without a clear user decision.
        if ExportActivity.shared.active {
            let alert = NSAlert(); alert.messageText = "正在导出 MKV"; alert.informativeText = "退出会取消导出并清理未完成文件。"; alert.addButton(withTitle: "继续导出"); alert.addButton(withTitle: "取消导出并退出")
            if alert.runModal() == .alertFirstButtonReturn { return .terminateCancel }
            ExportActivity.shared.cancel?()
            ExportActivity.shared.terminating = true
            return .terminateLater
        }
        return .terminateNow
    }
}
