//
//  PlayerPanels.swift
//  EmbyDanmaku
//
//  播放器弹出面板：播放设置、选集、弹幕、定时关闭。
//

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

// MARK: - 播放设置

struct PlayerSettingsPanel: View {
    @ObservedObject var vm: PlayerViewModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var tab: Tab = .playback

    enum Tab: String, CaseIterable, Identifiable {
        case playback = "播放"
        case danmaku = "弹幕"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationView {
            TabView(selection: $tab) {
                playbackTab.tag(Tab.playback)
                danmakuTab.tag(Tab.danmaku)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .navigationTitle("播放设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        vm.refreshDanmakuSettings()
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: 播放

    private var playbackTab: some View {
        Form {
            Section("倍速") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0], id: \.self) { r in
                            Button {
                                vm.setRate(Float(r))
                            } label: {
                                Text(String(format: "%.2gx", r))
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(abs(vm.playbackRate - Float(r)) < 0.01 ? Color.accentColor : Color(.secondarySystemBackground),
                                                in: Capsule())
                                    .foregroundStyle(abs(vm.playbackRate - Float(r)) < 0.01 ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Section("音轨") {
                if vm.audioChoices.isEmpty {
                    Text("无可切换音轨").foregroundStyle(.secondary)
                } else {
                    ForEach(vm.audioChoices) { c in
                        Button {
                            vm.selectedAudioID = c.id
                        } label: {
                            HStack {
                                Text(c.title)
                                Spacer()
                                if vm.selectedAudioID == c.id { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }

            Section("字幕") {
                if vm.subtitleChoices.count <= 1 {
                    Text("无字幕轨").foregroundStyle(.secondary)
                } else {
                    ForEach(vm.subtitleChoices) { c in
                        Button {
                            vm.selectedSubtitleID = c.id
                        } label: {
                            HStack {
                                Text(c.title)
                                Spacer()
                                if vm.selectedSubtitleID == c.id { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
                Stepper(value: $vm.subtitleFontSize, in: 14...36, step: 1) {
                    Text("字幕字号 \(Int(vm.subtitleFontSize))")
                }
                .onChange(of: vm.subtitleFontSize) { newValue in
                    settings.subtitleSize = Double(newValue)
                }
            }

            Section("画面") {
                Picker("画面比例", selection: Binding(get: { vm.videoGravity },
                                                      set: { vm.videoGravity = $0 })) {
                    Text("适应").tag(AVLayerVideoGravity.resizeAspect)
                    Text("填充").tag(AVLayerVideoGravity.resizeAspectFill)
                }
                .pickerStyle(.segmented)

                Toggle("自动连播下一集", isOn: $vm.autoPlayNext)
                Toggle("优先直连（关闭则强制转码）", isOn: $settings.preferDirectPlay)
                    .onChange(of: settings.preferDirectPlay) { _ in
                        Task { await vm.load() }
                    }
            }
        }
    }

    // MARK: 弹幕

    private var danmakuTab: some View {
        Form {
            Section {
                Toggle("启用弹幕", isOn: Binding(get: { settings.danmakuEnabled },
                                                 set: { vm.danmakuManager.toggleEnabled($0) }))
            }

            Section("显示") {
                LabeledRow("透明度") {
                    Slider(value: $settings.danmakuOpacity, in: 0.2...1)
                        .frame(width: 180)
                }
                LabeledRow("字号") {
                    Slider(value: $settings.danmakuScale, in: 0.6...2, step: 0.05)
                        .frame(width: 180)
                }
                LabeledRow("速度") {
                    Slider(value: $settings.danmakuSpeed, in: 0.5...2, step: 0.05)
                        .frame(width: 180)
                }
                LabeledRow("显示区域") {
                    Picker("", selection: $settings.danmakuArea) {
                        Text("1/4").tag(0.25)
                        Text("1/2").tag(0.5)
                        Text("3/4").tag(0.75)
                        Text("全屏").tag(1.0)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }
                Stepper(value: $settings.danmakuLimit, in: 40...600, step: 20) {
                    Text("同屏上限 \(settings.danmakuLimit)")
                }
            }

            Section("类型") {
                Toggle("滚动弹幕", isOn: $settings.showScrollDanmaku)
                Toggle("顶部弹幕", isOn: $settings.showTopDanmaku)
                Toggle("底部弹幕", isOn: $settings.showBottomDanmaku)
            }

            Section("屏蔽") {
                TextField("关键词，用逗号分隔", text: $settings.blockedWords)
                    .disableAutocorrection(true)
            }
        }
        .onDisappear { vm.refreshDanmakuSettings() }
    }
}

// MARK: - 选集

struct EpisodePanel: View {
    @ObservedObject var vm: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(vm.playlist) { ep in
                    Button {
                        dismiss()
                        Task { await vm.switchTo(ep) }
                    } label: {
                        HStack(spacing: 10) {
                            Text(ep.isEpisode ? "E\(ep.IndexNumber ?? 0)" : (ep.Name ?? ""))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 34, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ep.Name ?? "")
                                    .font(.subheadline)
                                    .foregroundStyle(ep.id == vm.item.id ? Color.accentColor : .primary)
                                    .lineLimit(2)
                                if let ov = ep.Overview, !ov.isEmpty {
                                    Text(ov).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            Spacer()
                            if ep.id == vm.item.id {
                                Image(systemName: "speaker.wave.2.fill").foregroundStyle(Color.accentColor)
                            } else if ep.watched {
                                Image(systemName: "checkmark").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("选集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - 弹幕面板

struct DanmakuPanel: View {
    @ObservedObject var vm: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var keyword = ""
    @State private var showFileImporter = false
    @State private var offsetInput: Double = 0

    private var dm: DanmakuManager { vm.danmakuManager }

    var body: some View {
        NavigationView {
            List {
                Section("当前状态") {
                    LabeledRow("状态") { Text(dm.status.message).foregroundStyle(.secondary) }
                    if let t = dm.boundTitle {
                        LabeledRow("弹幕库") {
                            Text(t).lineLimit(2).multilineTextAlignment(.trailing).foregroundStyle(.secondary)
                        }
                        if let e = dm.boundEpisodeName {
                            LabeledRow("节目") { Text(e).foregroundStyle(.secondary) }
                        }
                        Button("解除绑定", role: .destructive) { dm.clearBinding() }
                    }
                }

                Section("时间校准") {
                    HStack {
                        Text("偏移")
                        Slider(value: Binding(get: { dm.offset },
                                              set: { dm.setOffset($0) }),
                               in: -30...30, step: 0.5)
                        Text(String(format: "%+.1fs", dm.offset))
                            .font(.caption.monospacedDigit())
                            .frame(width: 58)
                    }
                    HStack {
                        Button("-0.5s") { dm.setOffset(dm.offset - 0.5) }
                        Button("+0.5s") { dm.setOffset(dm.offset + 0.5) }
                        Button("归零") { dm.setOffset(0) }
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }

                Section("搜索弹幕库") {
                    HStack {
                        TextField("番剧 / 影视名称", text: $keyword)
                            .disableAutocorrection(true)
                        Button("搜索") {
                            Task { await dm.search(keyword: keyword) }
                        }
                        .disabled(keyword.isEmpty)
                    }
                    ForEach(dm.searchResults) { r in
                        Button {
                            dm.choose(episodeId: r.episodeId, title: r.animeTitle, episodeName: r.episodeTitle)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.animeTitle ?? "").font(.subheadline).foregroundStyle(.primary)
                                Text(r.episodeTitle ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    ForEach(dm.animeResults) { a in
                        NavigationLink {
                            BangumiEpisodeList(anime: a, dm: dm)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.animeTitle).font(.subheadline)
                                Text(a.typeDescription ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("本地弹幕") {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("导入弹幕文件（XML / JSON）", systemImage: "tray.and.arrow.down")
                    }
                    let files = LocalStore.shared.localDanmakuFiles()
                    if files.isEmpty {
                        Text("暂无本地弹幕文件").foregroundStyle(.secondary)
                    } else {
                        ForEach(files, id: \.absoluteString) { url in
                            Button {
                                dm.importLocalFile(url, itemId: vm.item.id)
                            } label: {
                                Text(url.lastPathComponent).foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("弹幕")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: [.xml, .json, .data],
                          allowsMultipleSelection: false) { result in
                guard let url = try? result.get().first else { return }
                importFile(url)
            }
        }
        .navigationViewStyle(.stack)
    }

    private func importFile(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        let dest = LocalStore.shared.danmakuDirectory.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        guard (try? FileManager.default.copyItem(at: url, to: dest)) != nil else { return }
        dm.importLocalFile(dest, itemId: vm.item.id)
    }
}

struct BangumiEpisodeList: View {
    let anime: AnimeSearchResult
    @ObservedObject var dm: DanmakuManager

    var body: some View {
        List {
            ForEach(dm.bangumiEpisodes) { ep in
                Button {
                    dm.choose(episodeId: ep.episodeId, title: anime.animeTitle, episodeName: ep.episodeTitle)
                } label: {
                    Text(ep.episodeTitle ?? "第 \(ep.episodeId % 1000) 集")
                        .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle(anime.animeTitle)
        .task { await dm.loadEpisodes(animeId: anime.animeId) }
    }
}

// MARK: - 简介 / 演职表

struct ItemInfoPanel: View {
    let client: EmbyClient
    let item: BaseItem

    @State private var detail: BaseItem?
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                if isLoading {
                    ProgressView()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if let d = detail, let ov = d.Overview, !ov.isEmpty {
                                SectionHeader(title: "简介", systemImage: "text.alignleft")
                                Text(ov)
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .lineSpacing(4)
                                    .padding(.horizontal, 16)
                            }
                            if let people = detail?.People, !people.isEmpty {
                                SectionHeader(title: "演职表", systemImage: "person.2.fill")
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 14) {
                                        ForEach(people.prefix(30)) { p in
                                            VStack(spacing: 5) {
                                                if let tag = p.PrimaryImageTag, let pid = p.Id,
                                                   let url = client.imageURL(itemId: pid, tag: tag, maxWidth: 200) {
                                                    RemoteImageView(url: url, placeholderSystemImage: "person.circle")
                                                        .frame(width: 58, height: 58)
                                                        .clipShape(Circle())
                                                } else {
                                                    Image(systemName: "person.circle.fill")
                                                        .font(.system(size: 50))
                                                        .foregroundStyle(AppTheme.textTertiary)
                                                        .frame(width: 58, height: 58)
                                                }
                                                Text(p.Name ?? "")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(AppTheme.textPrimary)
                                                    .lineLimit(1)
                                                    .frame(width: 66)
                                                Text(p.Role ?? "")
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(AppTheme.textTertiary)
                                                    .lineLimit(1)
                                                    .frame(width: 66)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                            Color.clear.frame(height: 20)
                        }
                        .padding(.top, 14)
                    }
                }
            }
            .navigationTitle(item.Name ?? "详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .task { await load() }
        }
        .navigationViewStyle(.stack)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        detail = try? await client.fetchItem(item.id)
    }
}

// MARK: - 切换来源（直连 / 转码 / 码率 / 倍速）

struct SourcePanel: View {
    @ObservedObject var vm: PlayerViewModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    private let bitrateOptions: [(String, Int)] = [
        ("自动（60 Mbps）", 60_000_000),
        ("40 Mbps", 40_000_000),
        ("20 Mbps", 20_000_000),
        ("10 Mbps", 10_000_000),
        ("4 Mbps", 4_000_000),
        ("2 Mbps", 2_000_000)
    ]

    var body: some View {
        NavigationView {
            Form {
                Section("当前播放") {
                    LabeledRow("标题") { Text(vm.item.Name ?? "").foregroundStyle(.secondary).lineLimit(1) }
                    LabeledRow("方式") {
                        Text(vm.plan.map { PlaybackDecision.description(for: $0.method) } ?? "准备中…")
                            .foregroundStyle(.secondary)
                    }
                    if let q = vm.plan?.qualityLabel {
                        LabeledRow("画质") { Text(q).foregroundStyle(.secondary) }
                    }
                }

                Section("倍速") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0], id: \.self) { r in
                                Button {
                                    vm.setRate(Float(r))
                                } label: {
                                    Text(String(format: "%.2gx", r))
                                        .font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(abs(vm.playbackRate - Float(r)) < 0.01 ? Color.accentColor : Color(.secondarySystemBackground),
                                                    in: Capsule())
                                        .foregroundStyle(abs(vm.playbackRate - Float(r)) < 0.01 ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section {
                    Toggle("优先直连播放（关闭则强制服务器转码）", isOn: $settings.preferDirectPlay)
                        .onChange(of: settings.preferDirectPlay) { _ in
                            Task { await vm.load() }
                        }
                    Picker("转码码率上限", selection: $settings.maxBitrate) {
                        ForEach(bitrateOptions, id: \.1) { t in
                            Text(t.0).tag(t.1)
                        }
                    }
                } header: {
                    Text("切换来源")
                } footer: {
                    Text("改完会立刻按新的来源重新取流，当前进度会保留。")
                }

                Section("画面") {
                    Picker("画面比例", selection: Binding(get: { vm.videoGravity },
                                                          set: { vm.videoGravity = $0 })) {
                        Text("适应").tag(AVLayerVideoGravity.resizeAspect)
                        Text("填充").tag(AVLayerVideoGravity.resizeAspectFill)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("切换来源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - 定时关闭

struct SleepTimerPanel: View {
    @ObservedObject var timer: SleepTimer
    @Environment(\.dismiss) private var dismiss

    @State private var customMinutes: Double = 30

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(SleepTimer.presets, id: \.self) { m in
                        Button {
                            timer.start(minutes: m)
                            dismiss()
                        } label: {
                            HStack {
                                Text("\(m) 分钟后")
                                Spacer()
                                if case .countdown(let t) = timer.mode, Int(t / 60) == m {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                } header: {
                    Text("常用")
                }

                Section("自定义") {
                    HStack {
                        Slider(value: $customMinutes, in: 1...180, step: 1)
                        Text("\(Int(customMinutes)) 分钟")
                            .font(.caption.monospacedDigit())
                            .frame(width: 68, alignment: .trailing)
                    }
                    Button {
                        timer.start(seconds: customMinutes * 60)
                        dismiss()
                    } label: {
                        Text("开始倒计时")
                    }
                }

                Section {
                    Button {
                        timer.startEndOfEpisode()
                        dismiss()
                    } label: {
                        HStack {
                            Text("播完本集后停止")
                            Spacer()
                            if timer.mode == .endOfEpisode { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                        }
                        .foregroundStyle(.primary)
                    }

                    if timer.isActive {
                        Button("取消定时关闭", role: .destructive) {
                            timer.cancel()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("定时关闭")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .navigationViewStyle(.stack)
    }
}
