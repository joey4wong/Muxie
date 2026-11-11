// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

private let accent = Color("AccentColor")
/// Native Liquid Glass button (system `.glass` style, capsule shape). `compact: false` is the large variant.
struct NeutralGlassButtonStyle: ButtonStyle {
    var compact = true
    var padded = true
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        // Own glass capsule instead of `.glass`: the system style picks up the app accent as a coloured fill.
        configuration.label.foregroundStyle(.primary)
            .padding(.horizontal, padded ? (compact ? 14 : 26) : 0)
            .padding(.vertical, padded ? (compact ? 6 : 10) : 0)
            .glassEffect(.regular.interactive(), in: Capsule())
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
    }
}
/// A faint graphite backdrop with a muted gray-green glow, so glass has something to refract instead of a flat fill.
private struct GlassBackdrop: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(colors: [accent.opacity(0.30), .clear], center: .topLeading, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [accent.opacity(0.20), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 480)
        }.ignoresSafeArea()
    }
}
struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var targeted = false
    @State private var showCompactInspector = false
    @AppStorage(CompressEncoder.defaultsKey) private var encoderRaw = CompressEncoder.software.rawValue
    var body: some View {
        GeometryReader { geometry in
            if model.sources.isEmpty {
                emptyState
            } else {
                let compactInspector = geometry.size.width < 720 || geometry.size.height - WorkspaceLayout.exportHeight - WorkspaceLayout.activityHeight < 400
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        trackList(compact: compactInspector)
                            .frame(maxWidth: .infinity, alignment: .top)
                        if model.active != nil && !compactInspector {
                            inspector.frame(width: 238)
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
                                .padding(.trailing, 14).padding(.top, WorkspaceLayout.inspectorTopInset).padding(.bottom, WorkspaceLayout.listInsets / 2)
                        }
                    }.frame(minHeight: model.minimumTrackSectionHeight, maxHeight: .infinity, alignment: .top)
                    VStack(spacing: 24) {
                        modeSwitch.disabled(model.importing)
                        Button { model.exportPanel() } label: {
                            Text("Export").font(.system(size: 16, weight: .semibold))
                                .frame(width: 150, height: 42)
                        }
                            .buttonStyle(NeutralGlassButtonStyle(compact: false, padded: false))
                            .disabled(!model.canExport)
                    }
                    .frame(height: WorkspaceLayout.exportHeight)
                    Group {
                        if model.importing || model.completed != nil { activityBar }
                        else { Color.clear }
                    }.frame(height: WorkspaceLayout.activityHeight)
                }

            }
        }
        .background(GlassBackdrop())
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if model.queueResumePending {
                    HStack(spacing: 10) {
                        Text("Saved export queue is ready.").font(.system(size: 11))
                        Spacer()
                        Button("Continue Queue") { model.continuePersistedQueue() }.buttonStyle(NeutralGlassButtonStyle())
                    }.padding(.horizontal, 14).padding(.vertical, 8)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 12).padding(.top, 6)
                }
                QueueStripView()
            }
        }
        .navigationTitle(model.sources.first?.displayURL.lastPathComponent ?? "Muxie")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if !model.sources.isEmpty && model.exportMode == .compress {
                    Button { encoderRaw = (encoderRaw == CompressEncoder.hardware.rawValue ? CompressEncoder.software : CompressEncoder.hardware).rawValue } label: {
                        Image(systemName: "bolt.fill").foregroundStyle(encoderRaw == CompressEncoder.hardware.rawValue ? Color.yellow : Color.secondary)
                    }
                    .help("Fast mode: hardware encoding, quicker but larger files").disabled(model.importing)
                }
                if !model.sources.isEmpty {
                    Button { model.reset() } label: { Image(systemName: "doc.badge.plus") }.help("New Project").disabled(model.importing)
                    Button { model.openFiles(additional: true) } label: { Label("Add Tracks", systemImage: "plus") }.disabled(model.importing)
                }
            }
        }
        .sheet(isPresented: $showCompactInspector) {
            VStack(spacing: 0) {
                HStack { Spacer(); Button("Done") { showCompactInspector = false }.buttonStyle(NeutralGlassButtonStyle()).keyboardShortcut(.defaultAction) }
                    .padding(.horizontal, 18).padding(.top, 16)
                inspector
            }.frame(width: 320, height: 420)
        }
        .onAppear { model.workspaceScreenHeight = NSScreen.main?.visibleFrame.height ?? 900 }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification)) { _ in
            model.workspaceScreenHeight = NSScreen.main?.visibleFrame.height ?? 900
        }
        .onChange(of: model.filter) { _, _ in model.trackPage = 0 }
        .onChange(of: model.sources.isEmpty) { _, empty in if empty { showCompactInspector = false } }
        .overlay {
            if targeted { RoundedRectangle(cornerRadius: 15).strokeBorder(accent, lineWidth: 2).padding(4).allowsHitTesting(false) }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            guard !model.importing else { return false }
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
    /// One glass capsule holding both modes; a glass indicator slides between them.
    private var modeSwitch: some View {
        let modes = model.compressEligible ? ExportMode.allCases : [.mux]
        let index = CGFloat(modes.firstIndex(of: model.exportMode) ?? 0)
        let segmentWidth: CGFloat = 104, segmentHeight: CGFloat = 32, inset: CGFloat = 4
        return GlassEffectContainer(spacing: 0) {
            ZStack(alignment: .leading) {
                Capsule().fill(.clear)
                    .frame(width: segmentWidth * CGFloat(modes.count) + inset * 2, height: segmentHeight + inset * 2)
                    .glassEffect(.regular, in: Capsule())
                Capsule().fill(.clear)
                    .frame(width: segmentWidth, height: segmentHeight)
                    .glassEffect(.clear.interactive(), in: Capsule())
                    .offset(x: inset + index * segmentWidth)
            }
        }
        // Labels sit outside the glass container so the lens never refracts or fades them.
        .overlay(alignment: .leading) {
            HStack(spacing: 0) {
                ForEach(modes) { mode in
                    Button { withAnimation(.spring(duration: 0.4, bounce: 0.28)) { model.exportMode = mode } } label: {
                        Text(mode.label)
                            .font(.system(size: 13, weight: model.exportMode == mode ? .semibold : .regular))
                            .foregroundStyle(.primary)
                            .frame(width: segmentWidth, height: segmentHeight)
                            .contentShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }.padding(.leading, inset)
        }
    }
    private var emptyState: some View {
        VStack(spacing: 24) {
            KnotMark().frame(width: 132, height: 132)
            Button { model.openFiles() } label: {
                Label("Open Video…", systemImage: "plus").font(.system(size: 13, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 5)
            }.buttonStyle(NeutralGlassButtonStyle(compact: false)).disabled(model.importing)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func trackList(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: WorkspaceLayout.filterGap) {
            HStack(spacing: 3) {
                ForEach(["All", "Video", "Audio", "Subtitles"], id: \.self) { filter in
                    Button { model.filter = filter } label: {
                        HStack(spacing: 5) {
                            Text(filter)
                            Text("\(model.tracks.filter { filter == "All" || $0.filterName == filter }.count)")
                                .font(.system(size: 10, weight: .medium, design: .rounded)).opacity(0.55)
                        }.font(.system(size: 11, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 8)
                            .foregroundStyle(model.filter == filter ? Color.primary : Color.secondary)
                            .glassEffect(model.filter == filter ? .regular.interactive() : .identity, in: Capsule())
                    }.buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }.frame(height: WorkspaceLayout.filterHeight).disabled(model.importing)
            GlassEffectContainer(spacing: WorkspaceLayout.rowSpacing) {
                VStack(spacing: WorkspaceLayout.rowSpacing) {
                    ForEach(model.pagedTracks) { track in trackRow(track, compact: compact) }
                    if model.filtered.isEmpty {
                        Text("No tracks").font(.callout).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity).frame(height: WorkspaceLayout.rowHeight)
                    }
                }
            }.fixedSize(horizontal: false, vertical: true)
            if model.reservesPagination {
                HStack(spacing: 16) {
                    Spacer()
                    if model.pageCount > 1 {
                        Button { model.trackPage = max(0, model.currentTrackPage - 1); model.selected = nil } label: { Image(systemName: "chevron.left") }
                            .disabled(model.currentTrackPage == 0).help("Previous Page")
                        Text("\(model.currentTrackPage + 1) / \(model.pageCount)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        Button { model.trackPage = min(model.pageCount - 1, model.currentTrackPage + 1); model.selected = nil } label: { Image(systemName: "chevron.right") }
                            .disabled(model.currentTrackPage + 1 >= model.pageCount).help("Next Page")
                    }
                    Spacer()
                }.buttonStyle(.plain).frame(height: WorkspaceLayout.paginationHeight - WorkspaceLayout.filterGap)
            }
        }.padding(18)
    }
    private func trackRow(_ track: MediaTrack, compact: Bool) -> some View {
        let selected = track.id == model.selected
        return HStack(spacing: 11) {
            Toggle("Include \(model.displayName(for: track))", isOn: model.boolBinding(track.id, \.enabled)).labelsHidden().toggleStyle(.checkbox)
            Image(systemName: track.symbol).font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary).frame(width: 38, height: 39)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                Text(model.displayName(for: track)).font(.system(size: 12, weight: .medium)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(track.codec + (track.detail.isEmpty ? "" : " · " + track.detail)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    if let badge = track.hdrBadge { Text(badge.rawValue).font(.system(size: 9, weight: .semibold)).padding(.horizontal, 5).padding(.vertical, 2).glassEffect(.identity, in: Capsule()) }
                    if track.delayMs != 0 { Text("\(track.delayMs > 0 ? "+" : "")\(track.delayMs) ms").font(.system(size: 9)).foregroundStyle(.secondary) }
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 5) {
                Text(track.language.uppercased()).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                if track.isDefault { Text("Default").font(.system(size: 9)).foregroundStyle(.secondary) }
            }
        }.padding(.horizontal, 12).frame(height: WorkspaceLayout.rowHeight).contentShape(RoundedRectangle(cornerRadius: 13))
            .glassEffect(selected ? .regular.tint(accent.opacity(0.22)).interactive() : .regular.interactive(), in: RoundedRectangle(cornerRadius: 13))
            .opacity(track.enabled || selected ? 1 : 0.72)
            .onTapGesture {
                model.selected = track.id
                if compact { showCompactInspector = true }
            }
            .disabled(model.importing)
    }
    private var inspector: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let track = model.active {
                HStack(spacing: 10) {
                    Image(systemName: track.symbol).font(.system(size: 21)).foregroundStyle(.secondary)
                        .frame(width: 41, height: 41).glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
                    Text(track.kindName).font(.system(size: 16, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    TextField("Track name", text: model.binding(track.id, \.name)).textFieldStyle(.roundedBorder).controlSize(.regular)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Language").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Picker("Language", selection: model.binding(track.id, \.language)) {
                        let languages = [("und", "Unspecified"), ("en", "English"), ("zh", "Chinese"), ("zh-Hans", "Chinese (Simplified)"), ("zh-Hant", "Chinese (Traditional)"), ("yue", "Cantonese"), ("ja", "Japanese"), ("ko", "Korean"), ("fr", "French"), ("de", "German"), ("es", "Spanish"), ("it", "Italian"), ("pt", "Portuguese"), ("ru", "Russian")]
                        ForEach(languages, id: \.0) { item in Text(item.1).tag(item.0) }
                        if !languages.contains(where: { $0.0 == track.language }) { Text(track.language).tag(track.language) }
                    }.labelsHidden().pickerStyle(.menu).controlSize(.regular).frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                Toggle("Default", isOn: model.boolBinding(track.id, \.isDefault)).font(.system(size: 12)).toggleStyle(.switch).controlSize(.small)
                if track.kind == "subtitles" {
                    Toggle("Forced", isOn: model.boolBinding(track.id, \.isForced)).font(.system(size: 12)).toggleStyle(.switch).controlSize(.small)
                }
                if track.kind == "audio" || track.kind == "subtitles" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Delay (ms)").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Stepper(value: model.intBinding(track.id, \.delayMs), in: -12_000...12_000, step: 50) { Text("\(track.delayMs)").font(.system(size: 12, design: .monospaced)).frame(width: 64, alignment: .trailing) }
                        }
                        Text("Drift fix (e.g. 25/23.976)").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        TextField("Optional", text: model.optionalIntBinding(track.id, numerator: \.syncDriftNumerator, denominator: \.syncDriftDenominator)).textFieldStyle(.roundedBorder)
                    }
                }
            }
            Spacer(minLength: 0)
        }.padding(18).frame(maxHeight: .infinity, alignment: .topLeading).disabled(model.importing)
    }
    private var activityBar: some View {
        HStack(spacing: 12) {
            if model.importing {
                ProgressView().controlSize(.small)
                Text("Importing…").font(.system(size: 11))
                Spacer()
            } else if let output = model.completed {
                Image(systemName: model.warning == nil ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(model.warning == nil ? accent : Color.orange)
                Text(output.lastPathComponent).font(.system(size: 11)).lineLimit(1)
                Spacer()
                if let warning = model.warning { Button("Warnings") { model.fail(warning) }.buttonStyle(NeutralGlassButtonStyle()) }
                Button("Show in Finder", systemImage: "folder") { model.reveal() }.buttonStyle(NeutralGlassButtonStyle())
            }
        }.padding(.horizontal, 16).frame(height: 40)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 15)).padding(.horizontal, 12)
    }
}
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 15) {
            KnotMark().frame(width: 92, height: 92)
            Text("Muxie").font(.title.weight(.semibold))
            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3.0").font(.callout).foregroundStyle(.secondary)
            Text("© 2026 Yunyi Tang").font(.system(size: 11)).foregroundStyle(.secondary)
            Text("GPL-2.0-only").font(.system(size: 11)).foregroundStyle(.secondary)
            Link("MKVToolNix", destination: URL(string: "https://mkvtoolnix.download/")!).font(.system(size: 11))
            Text("© Moritz Bunkus and contributors").font(.system(size: 10)).foregroundStyle(.tertiary)
            Button("Done") { dismiss() }.buttonStyle(NeutralGlassButtonStyle()).keyboardShortcut(.defaultAction).padding(.top, 8)
        }.padding(30).frame(width: 320)
    }
}

/// The knot artwork on a transparent background, shown directly on the window instead of inside the Dock tile.
struct KnotMark: View {
    private static let image: NSImage? = Bundle.main.url(forResource: "Knot", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
    var body: some View {
        if let image = Self.image {
            let base = Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            base.overlay {
                TimelineView(.animation) { context in
                    let cycle = 5.0, sweep = 1.6
                    let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
                    let p = min(t / sweep, 1)
                    let eased = p * p * (3 - 2 * p)
                    let c = -0.3 + eased * 1.6
                    LinearGradient(stops: [
                        .init(color: .white.opacity(0), location: c - 0.16),
                        .init(color: .white.opacity(0.55), location: c),
                        .init(color: .white.opacity(0), location: c + 0.16)
                    ], startPoint: .bottomLeading, endPoint: .topTrailing)
                    .opacity(p < 1 ? 1 : 0)
                    .blendMode(.plusLighter)
                }
                .mask(base)
                .allowsHitTesting(false)
            }
        } else {
            Image(nsImage: NSApplication.shared.applicationIconImage).resizable().aspectRatio(contentMode: .fit)
        }
    }
}
