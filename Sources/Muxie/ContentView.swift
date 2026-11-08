// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

private let accent = Color(red: 0.31, green: 0.38, blue: 0.96)
struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var targeted = false
    @State private var showCompactInspector = false
    var body: some View {
        GeometryReader { geometry in
            if model.sources.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        trackList(compact: geometry.size.width < 720)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if model.active != nil && geometry.size.width >= 720 {
                            Divider()
                            ScrollView { inspector }.frame(width: 238)
                        }
                    }.frame(height: geometry.size.height * 0.70)
                    Button("Export") { model.exportPanel() }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 32).padding(.vertical, 7)
                        .buttonStyle(.glassProminent)
                        .disabled(!model.canExport)
                        .padding(.top, 16)
                    Spacer(minLength: 8)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(accent)
        .navigationTitle(model.sources.first?.url.lastPathComponent ?? "Muxie")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if !model.sources.isEmpty {
                    Button { model.reset() } label: { Image(systemName: "doc.badge.plus") }.help("New Project").disabled(model.busy)
                    Button { model.openFiles(additional: true) } label: { Label("Add Tracks", systemImage: "plus") }.disabled(model.busy)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.exporting || model.importing || model.completed != nil { activityBar }
        }
        .sheet(isPresented: $showCompactInspector) {
            VStack(spacing: 0) {
                HStack { Spacer(); Button("Done") { showCompactInspector = false }.buttonStyle(.glass).keyboardShortcut(.defaultAction) }
                    .padding(.horizontal, 18).padding(.top, 16)
                ScrollView { inspector }
            }.frame(width: 320, height: 320)
        }
        .onChange(of: model.sources.isEmpty) { _, empty in if empty { showCompactInspector = false } }
        .overlay {
            if targeted { RoundedRectangle(cornerRadius: 15).strokeBorder(accent, lineWidth: 2).padding(4).allowsHitTesting(false) }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            guard !model.busy else { return false }
            Task {
                var urls: [URL] = []
                for provider in providers {
                    let url: URL? = await withCheckedContinuation { continuation in
                        _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
                    }
                    if let url { urls.append(url) }
                }
                await model.importFiles(urls)
            }
            return true
        }
    }
    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(nsImage: NSApplication.shared.applicationIconImage).resizable().interpolation(.high).frame(width: 112, height: 112)
            Button { model.openFiles() } label: {
                Label("Open Video…", systemImage: "plus").font(.system(size: 13, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 5)
            }.buttonStyle(.glassProminent).disabled(model.busy)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func trackList(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 3) {
                ForEach(["All", "Video", "Audio", "Subtitles"], id: \.self) { filter in
                    Button { withAnimation(.easeInOut(duration: 0.15)) { model.filter = filter } } label: {
                        HStack(spacing: 5) {
                            Text(filter)
                            Text("\(model.tracks.filter { filter == "All" || $0.filterName == filter }.count)")
                                .font(.system(size: 10, weight: .medium, design: .rounded)).opacity(0.55)
                        }.font(.system(size: 11, weight: .medium)).padding(.horizontal, 11).padding(.vertical, 8)
                            .foregroundStyle(model.filter == filter ? accent : .secondary)
                            .background(model.filter == filter ? accent.opacity(0.09) : .clear, in: Capsule())
                    }.buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }.disabled(model.busy)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.filtered) { track in trackRow(track, compact: compact) }
                    if model.filtered.isEmpty {
                        Text("No tracks").font(.callout).foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding(.top, 40)
                    }
                }.padding(2)
            }
        }.padding(20)
    }
    private func trackRow(_ track: MediaTrack, compact: Bool) -> some View {
        let selected = track.id == model.selected
        return HStack(spacing: 11) {
            Toggle("Include \(model.displayName(for: track))", isOn: model.boolBinding(track.id, \.enabled)).labelsHidden().toggleStyle(.checkbox)
            Image(systemName: track.symbol).font(.system(size: 17, weight: .medium))
                .foregroundStyle(track.enabled ? accent : Color.secondary).frame(width: 38, height: 39)
                .background(accent.opacity(0.065), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                Text(model.displayName(for: track)).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(track.codec + (track.detail.isEmpty ? "" : " · " + track.detail)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 5) {
                Text(track.language.uppercased()).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                if track.isDefault { Text("Default").font(.system(size: 9)).foregroundStyle(accent) }
            }
        }.padding(12).contentShape(RoundedRectangle(cornerRadius: 13))
            .background(selected ? accent.opacity(0.06) : Color(nsColor: .controlBackgroundColor).opacity(0.45), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(selected ? accent.opacity(0.4) : .primary.opacity(0.065)))
            .opacity(track.enabled || selected ? 1 : 0.72)
            .onTapGesture {
                model.selected = track.id
                if compact { showCompactInspector = true }
            }
            .disabled(model.busy)
    }
    private var inspector: some View {
        VStack(alignment: .leading, spacing: 23) {
            if let track = model.active {
                HStack(spacing: 10) {
                    Image(systemName: track.symbol).font(.system(size: 21)).foregroundStyle(accent)
                        .frame(width: 41, height: 41).glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
                    Text(track.kindName).font(.system(size: 16, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    TextField("Track name", text: model.binding(track.id, \.name)).textFieldStyle(.roundedBorder).controlSize(.large)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Language").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Picker("Language", selection: model.binding(track.id, \.language)) {
                        let languages = [("und", "Unspecified"), ("en", "English"), ("zh", "Chinese"), ("zh-Hans", "Chinese (Simplified)"), ("zh-Hant", "Chinese (Traditional)"), ("yue", "Cantonese"), ("ja", "Japanese"), ("ko", "Korean"), ("fr", "French"), ("de", "German"), ("es", "Spanish"), ("it", "Italian"), ("pt", "Portuguese"), ("ru", "Russian")]
                        ForEach(languages, id: \.0) { item in Text(item.1).tag(item.0) }
                        if !languages.contains(where: { $0.0 == track.language }) { Text(track.language).tag(track.language) }
                    }.labelsHidden().pickerStyle(.menu).controlSize(.large).frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                Toggle("Default", isOn: model.boolBinding(track.id, \.isDefault)).font(.system(size: 12)).toggleStyle(.switch).controlSize(.small)
                if track.kind == "subtitles" {
                    Toggle("Forced", isOn: model.boolBinding(track.id, \.isForced)).font(.system(size: 12)).toggleStyle(.switch).controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }.padding(22).frame(maxHeight: .infinity, alignment: .topLeading).disabled(model.busy)
    }
    private var activityBar: some View {
        HStack(spacing: 12) {
            if model.importing {
                ProgressView().controlSize(.small)
                Text("Importing…").font(.system(size: 11))
                Spacer()
            } else if model.exporting {
                ProgressView(value: model.progress).frame(width: 150)
                Text("\(Int(model.progress * 100))%").font(.system(size: 11, design: .monospaced)).monospacedDigit()
                Spacer()
                Button("Cancel", role: .cancel) { model.job?.cancel() }.buttonStyle(.glass)
            } else if let output = model.completed {
                Image(systemName: model.warning == nil ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(model.warning == nil ? .green : .orange)
                Text(output.lastPathComponent).font(.system(size: 11)).lineLimit(1)
                Spacer()
                if let warning = model.warning { Button("Warnings") { model.fail(warning) }.buttonStyle(.glass) }
                Button("Show in Finder", systemImage: "folder") { model.reveal() }.buttonStyle(.glass)
            }
        }.padding(.horizontal, 16).padding(.vertical, 12)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 15)).padding(12)
    }
}
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 15) {
            Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 80, height: 80)
            Text("Muxie").font(.title.weight(.semibold))
            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.0").font(.callout).foregroundStyle(.secondary)
            Text("© 2026 Yunyi Tang").font(.system(size: 11)).foregroundStyle(.secondary)
            Text("GPL-2.0-only").font(.system(size: 11)).foregroundStyle(.secondary)
            Link("MKVToolNix", destination: URL(string: "https://mkvtoolnix.download/")!).font(.system(size: 11))
            Text("© Moritz Bunkus and contributors").font(.system(size: 10)).foregroundStyle(.tertiary)
            Button("Done") { dismiss() }.buttonStyle(.glass).keyboardShortcut(.defaultAction).padding(.top, 8)
        }.padding(30).frame(width: 320)
    }
}
