// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

private let accent = Color(red: 0.31, green: 0.38, blue: 0.96)
struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var targeted = false
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            GeometryReader { geo in
                Ellipse().fill(accent.opacity(scheme == .dark ? 0.13 : 0.08)).frame(width: 750, height: 550).blur(radius: 100).offset(x: geo.size.width - 630, y: -270)
                Ellipse().fill(Color.cyan.opacity(0.07)).frame(width: 500, height: 500).blur(radius: 100).offset(x: 80, y: 390)
            }.allowsHitTesting(false)
            VStack(spacing: 0) {
                header
                Rectangle().fill(.primary.opacity(0.07)).frame(height: 1)
                HStack(spacing: 0) {
                    sidebar.frame(width: 218)
                    Rectangle().fill(.primary.opacity(0.07)).frame(width: 1)
                    workspace.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if !model.sources.isEmpty {
                        Rectangle().fill(.primary.opacity(0.07)).frame(width: 1)
                        inspector.frame(width: 258)
                    }
                }
                exportBar
            }
        }
        .tint(accent)
        .overlay { if targeted { RoundedRectangle(cornerRadius: 22).strokeBorder(accent, lineWidth: 3).padding(5).allowsHitTesting(false) } }
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
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.fill").font(.system(size: 23, weight: .medium)).foregroundStyle(accent)
                .frame(width: 43, height: 43).background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text("Muxie").font(.system(size: 23, weight: .semibold, design: .rounded))
                Text("原生轨道整理工具").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
            Spacer()
            if model.importing { ProgressView().controlSize(.small); Text("正在读取轨道…").font(.callout).foregroundStyle(.secondary) }
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 10) {
                    if !model.sources.isEmpty {
                        Button { model.openFiles(additional: true) } label: { Label("添加音轨 / 字幕", systemImage: "plus") }.buttonStyle(.glass).disabled(model.busy)
                    }
                    Button { model.showAbout = true } label: { Image(systemName: "info.circle").frame(width: 19) }.buttonStyle(.glass).help("关于与处理引擎")
                }
            }
        }.padding(.horizontal, 26).padding(.top, 27).padding(.bottom, 18)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("来源文件").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary); Spacer(); Text("\(model.sources.count)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary) }
                .padding(.horizontal, 18).padding(.top, 23).padding(.bottom, 14)
            if model.sources.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "tray").font(.title2).foregroundStyle(.tertiary)
                    Text("从一部影片开始").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    Text("MP4、MKV 及更多格式").font(.system(size: 10)).foregroundStyle(.tertiary)
                }.padding(18)
            } else {
                ScrollView {
                    VStack(spacing: 9) {
                        ForEach(Array(model.sources.enumerated()), id: \.element.id) { index, source in
                            VStack(alignment: .leading, spacing: 9) {
                                HStack {
                                    Image(systemName: index == 0 ? "film.stack" : source.url.pathExtension.lowercased() == "srt" ? "captions.bubble" : "waveform").foregroundStyle(index == 0 ? accent : .secondary)
                                    Spacer()
                                    if index == 0 { Text("主影片").font(.system(size: 9, weight: .semibold)).foregroundStyle(accent).padding(.horizontal, 6).padding(.vertical, 3).background(accent.opacity(0.1), in: Capsule()) }
                                    else { Button { model.removeSource(source) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)) }.buttonStyle(.plain).foregroundStyle(.tertiary).help("移除这个来源").disabled(model.busy) }
                                }
                                Text(source.url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(3).textSelection(.enabled)
                                Text(source.url.pathExtension.uppercased() + " · " + ByteCountFormatter.string(fromByteCount: source.byteSize, countStyle: .file)).font(.system(size: 10)).foregroundStyle(.secondary)
                            }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
                                .background(index == 0 ? accent.opacity(0.06) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 13))
                                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.primary.opacity(0.055)))
                        }
                    }.padding(.horizontal, 12)
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 12) {
                if !model.sources.isEmpty {
                    Button { model.reset() } label: { Label("新建项目", systemImage: "arrow.counterclockwise") }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary).disabled(model.busy)
                }
                Rectangle().fill(.primary.opacity(0.07)).frame(height: 1)
                HStack(spacing: 6) { Circle().fill(model.enginePath == nil ? .orange : .green).frame(width: 5, height: 5); Text(model.enginePath == nil ? "需要 MKVToolNix" : "MKVToolNix 引擎就绪").font(.system(size: 10)).foregroundStyle(.secondary) }
                Text("本地处理 · 文件不会上传").font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(18)
        }.background(.thinMaterial)
    }
    private var workspace: some View {
        Group {
            if model.sources.isEmpty { emptyState }
            else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("你的影片，你的轨道。").font(.system(size: 26, weight: .semibold, design: .rounded))
                            Text("勾选保留，取消即移除。点选轨道可编辑名称与语言。").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.padding(.bottom, 24)
                    HStack(spacing: 6) {
                        ForEach(["全部", "视频", "音轨", "字幕"], id: \.self) { name in
                            Button { withAnimation(.easeInOut(duration: 0.18)) { model.filter = name } } label: {
                                HStack(spacing: 5) { Text(name); Text("\(model.tracks.filter { name == "全部" || $0.kindName == name }.count)").font(.system(size: 10, weight: .medium, design: .rounded)).opacity(0.6) }
                                    .font(.system(size: 11, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 8)
                                    .foregroundStyle(model.filter == name ? accent : .secondary)
                                    .background(model.filter == name ? accent.opacity(0.1) : .clear, in: Capsule())
                            }.buttonStyle(.plain)
                        }
                        Spacer()
                    }.padding(4).background(.primary.opacity(0.025), in: Capsule()).padding(.bottom, 18)
                    ScrollView {
                        LazyVStack(spacing: 9) {
                            ForEach(model.filtered) { track in trackRow(track) }
                            if model.filtered.isEmpty { ContentUnavailableView("没有这类轨道", systemImage: "line.3.horizontal.decrease", description: Text("添加音频或字幕文件，就会显示在这里。")) }
                        }.padding(.bottom, 16)
                    }
                    HStack(spacing: 6) { Image(systemName: "checkmark.shield"); Text("只调整容器与轨道，不重新编码视频或音频。") }.font(.system(size: 10)).foregroundStyle(.tertiary).padding(.top, 12)
                }.padding(.horizontal, 26).padding(.vertical, 26)
            }
        }
    }
    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle().fill(accent.opacity(0.055)).frame(width: 220, height: 220)
                Circle().strokeBorder(accent.opacity(0.08), lineWidth: 1).frame(width: 275, height: 275)
                RoundedRectangle(cornerRadius: 23).fill(accent.opacity(0.1)).frame(width: 139, height: 103).rotationEffect(.degrees(-13)).offset(x: -14, y: -6)
                VStack(spacing: 13) {
                    HStack(spacing: 9) { Image(systemName: "play.fill").font(.system(size: 13)); Capsule().frame(width: 65, height: 5) }
                    HStack(spacing: 9) { Image(systemName: "waveform").font(.system(size: 14)); Capsule().frame(width: 65, height: 5) }
                    HStack(spacing: 9) { Image(systemName: "captions.bubble").font(.system(size: 13)); Capsule().frame(width: 65, height: 5) }
                }.foregroundStyle(accent).padding(25).glassEffect(.regular, in: RoundedRectangle(cornerRadius: 23)).rotationEffect(.degrees(6))
                Image(systemName: "plus").font(.system(size: 14, weight: .semibold)).padding(12).glassEffect(.regular.tint(accent.opacity(0.12)), in: Circle()).offset(x: 84, y: 48)
            }.frame(height: 245)
            Text("好影片，值得清爽的轨道。").font(.system(size: 30, weight: .semibold, design: .rounded)).padding(.top, 23)
            Text("加入配音，收好字幕，或换一个 MKV 容器。\n不损画质，不留多余。")
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5).padding(.top, 13)
            Button { model.openFiles() } label: { Label("选择影片", systemImage: "plus").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 20).padding(.vertical, 7) }.buttonStyle(.glassProminent).padding(.top, 27).disabled(model.busy)
            Text("或将影片拖到这里   ·   MP4 / MKV").font(.system(size: 11)).foregroundStyle(.tertiary).padding(.top, 14)
            Spacer()
            HStack(spacing: 28) {
                feature("waveform", "多音轨")
                feature("captions.bubble", "多字幕")
                feature("arrow.triangle.2.circlepath", "无损封装")
            }.padding(.bottom, 32)
        }.frame(maxWidth: .infinity)
    }
    private func feature(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 11)).foregroundStyle(.secondary)
    }
    private func trackRow(_ track: MediaTrack) -> some View {
        let isSelected = track.id == model.selected
        return HStack(spacing: 12) {
            Toggle("保留这条\(track.kindName)", isOn: model.boolBinding(track.id, \.enabled)).labelsHidden().toggleStyle(.checkbox).help("勾选保留，取消即从输出中移除")
            Image(systemName: track.symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(track.enabled ? accent : Color.secondary).frame(width: 39, height: 42).background(accent.opacity(track.enabled ? 0.08 : 0.025), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 5) {
                Text(track.name.isEmpty ? (track.kindName + " \(track.trackID + 1)") : track.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(track.codec + (track.detail.isEmpty ? "" : " · " + track.detail)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                if let source = model.sources.first(where: { $0.id == track.sourceID }) { Text(source.url.lastPathComponent).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1) }
            }
            Spacer(minLength: 2)
            VStack(alignment: .trailing, spacing: 6) {
                Text(track.language.uppercased()).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                if track.isDefault { Text("默认").font(.system(size: 9, weight: .medium)).foregroundStyle(accent).padding(.horizontal, 6).padding(.vertical, 3).background(accent.opacity(0.08), in: Capsule()) }
                if !track.enabled { Text("不导出").font(.system(size: 9)).foregroundStyle(.tertiary) }
            }
        }.padding(13).contentShape(RoundedRectangle(cornerRadius: 15))
            .background(isSelected ? accent.opacity(0.065) : Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(isSelected ? accent.opacity(0.45) : .primary.opacity(0.065), lineWidth: 1))
            .opacity(track.enabled ? 1 : 0.58)
            .onTapGesture { model.selected = track.id }
            .disabled(model.busy)
    }
    private var inspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("轨道详情").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.bottom, 25)
            if let track = model.active {
                HStack(spacing: 10) {
                    Image(systemName: track.symbol).font(.system(size: 22)).foregroundStyle(accent).frame(width: 43, height: 43).glassEffect(.regular, in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 5) { Text(track.kindName).font(.system(size: 17, weight: .semibold)); Text("ID \(track.trackID) · \(track.enabled ? "将保留" : "不导出")").font(.system(size: 10)).foregroundStyle(.secondary) }
                }.padding(.bottom, 27)
                VStack(alignment: .leading, spacing: 19) {
                    VStack(alignment: .leading, spacing: 9) {
                        inspectorLabel("轨道名称")
                        TextField("例如：国语 / 简体中文", text: model.binding(track.id, \.name)).textFieldStyle(.roundedBorder).controlSize(.large)
                        Text("显示在播放器的音轨或字幕列表中。") .font(.system(size: 10)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        inspectorLabel("语言")
                        Picker("语言", selection: model.binding(track.id, \.language)) {
                            let common = [("und", "未指定"), ("zh", "中文"), ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"), ("yue", "粤语"), ("en", "English"), ("ja", "日本語"), ("ko", "한국어"), ("fr", "Français"), ("de", "Deutsch"), ("es", "Español")]
                            ForEach(common, id: \.0) { item in Text(item.1).tag(item.0) }
                            if !common.contains(where: { $0.0 == track.language }) { Text(track.language).tag(track.language) }
                        }.labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading).controlSize(.large)
                        TextField("BCP 47，例如 en / zh-Hans", text: model.binding(track.id, \.language)).textFieldStyle(.roundedBorder).font(.system(size: 10, design: .monospaced)).help("支持自定义语言标签；标签由 MKVToolNix 在导出时验证")
                    }
                    Rectangle().fill(.primary.opacity(0.08)).frame(height: 1)
                    Toggle("默认轨道", isOn: model.boolBinding(track.id, \.isDefault)).font(.system(size: 12)).toggleStyle(.switch).controlSize(.small)
                    Text("播放器仍可能优先使用自己的语言偏好。") .font(.system(size: 10)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true).padding(.top, -11)
                    if track.kind == "subtitles" { Toggle("强制字幕", isOn: model.boolBinding(track.id, \.isForced)).font(.system(size: 12)).toggleStyle(.switch).controlSize(.small) }
                }.disabled(model.busy)
                Spacer(minLength: 15)
                VStack(alignment: .leading, spacing: 7) { Label("无损保留", systemImage: "checkmark.shield").font(.system(size: 11, weight: .medium)); Text("勾掉轨道只影响新的 MKV，\n不会修改或删除原文件。") .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4) }.padding(13).frame(maxWidth: .infinity, alignment: .leading).background(accent.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            } else { Text("点选一条轨道，编辑它的名称和语言。").font(.callout).foregroundStyle(.secondary); Spacer() }
        }.padding(21).frame(maxHeight: .infinity, alignment: .topLeading)
    }
    private func inspectorLabel(_ title: String) -> some View { Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary) }
    private var exportBar: some View {
        HStack(spacing: 16) {
            if model.exporting {
                ProgressView(value: model.progress).frame(width: 150)
                VStack(alignment: .leading, spacing: 3) { Text("正在无损封装… \(Int(model.progress * 100))%").font(.system(size: 12, weight: .medium)); Text("完成后自动校验轨道，原文件保持不变。").font(.system(size: 10)).foregroundStyle(.secondary) }
                Spacer()
                Button("取消导出", role: .cancel) { model.job?.cancel() }.buttonStyle(.glass)
            } else if model.completed != nil {
                Image(systemName: model.warning == nil ? "checkmark.circle.fill" : "exclamationmark.circle.fill").font(.title2).foregroundStyle(model.warning == nil ? .green : .orange)
                VStack(alignment: .leading, spacing: 4) { Text(model.warning == nil ? "导出完成" : "导出完成，有引擎提示").font(.system(size: 13, weight: .semibold)); Text(model.completed?.lastPathComponent ?? "").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
                Spacer()
                if let warning = model.warning { Button("查看提示") { model.fail(warning) }.buttonStyle(.glass) }
                Button("在 Finder 中显示", systemImage: "folder") { model.reveal() }.buttonStyle(.glass)
                Button("再次导出", systemImage: "square.and.arrow.up") { model.exportPanel() }.buttonStyle(.glassProminent)
            } else {
                Image(systemName: "shippingbox").font(.system(size: 19)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.sources.isEmpty ? "一切准备就绪" : "\(model.enabled.filter { $0.kind == "audio" }.count) 条音轨 · \(model.enabled.filter { $0.kind == "subtitles" }.count) 条字幕") .font(.system(size: 12, weight: .medium))
                    Text(model.sources.isEmpty ? "添加影片，即可开始" : "输出为 MKV · 不覆盖原文件") .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                if !model.sources.isEmpty { Text("MKV").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary).padding(.horizontal, 11).padding(.vertical, 7).background(.primary.opacity(0.04), in: Capsule()) }
                Button { model.exportPanel() } label: { Label("导出 MKV", systemImage: "arrow.up.right").font(.system(size: 12, weight: .semibold)).padding(.horizontal, 15).padding(.vertical, 5) }.buttonStyle(.glassProminent).disabled(!model.canExport)
            }
        }.padding(.horizontal, 22).padding(.vertical, 16)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20)).padding(.horizontal, 18).padding(.bottom, 16).padding(.top, 6)
    }
}
struct AboutView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Image(systemName: "square.stack.3d.up.fill").font(.largeTitle).foregroundStyle(accent); VStack(alignment: .leading) { Text("Muxie").font(.title.bold()); Text("1.0.0 · 原生 macOS 26+").foregroundStyle(.secondary) }; Spacer(); Button("完成") { dismiss() }.buttonStyle(.glass) }
            Text("你的影片，你的轨道。").font(.title3.weight(.semibold))
            Text("SwiftUI + 原生 Liquid Glass。全部处理在本机完成，影片不会上传。添加、移除音轨和字幕，以及 MP4 → MKV，均通过重新封装完成，不重新编码。") .font(.callout).foregroundStyle(.secondary)
            Divider()
            Text("处理引擎").font(.headline)
            Text(model.enginePath ?? "尚未找到 mkvmerge").font(.system(size: 11, design: .monospaced)).textSelection(.enabled).foregroundStyle(.secondary)
            Button("选择外部 mkvmerge…") { model.chooseEngine() }.disabled(model.busy)
            Text("本应用是独立的 macOS 界面，并非 MKVToolNix 官方产品。MKVToolNix 由 Moritz Bunkus 及贡献者开发，采用 GPL-2.0-only。本地自用包可能包含其引擎；公开分发前必须同时整理对应源码、构建资料及依赖许可证。") .font(.system(size: 11)).foregroundStyle(.secondary)
            Link("MKVToolNix 官方网站 ↗", destination: URL(string: "https://mkvtoolnix.download/")!)
            Text("不支持 DRM 文件、视频转码、声音混音或字幕烧录。字幕必须是独立轨道，不能移除已烧入画面的字幕。") .font(.system(size: 10)).foregroundStyle(.tertiary)
        }.padding(30).frame(width: 540)
    }
}
