//
//  PlaylistDetailView.swift
//  EmbyDanmaku
//
//  清单详情 / 播放历史 / 继续观看 / 服务器播放列表内容。
//  清单内支持排序、删除、整体连续播放。
//

import SwiftUI

// MARK: - 条目行

struct EntryRow: View {
    let entry: PlaylistEntry
    let client: EmbyClient?
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 12) {
            RemoteImageView(url: posterURL,
                            placeholderSystemImage: entry.isEpisode ? "tv" : "film")
                .frame(width: 62, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                if let s = entry.displaySubtitle, !s.isEmpty {
                    Text(s)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    Text(entry.isEpisode ? "剧集" : (entry.isSeries ? "剧集库" : "电影"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(AppTheme.accent.opacity(0.16), in: Capsule())
                    if let d = entry.durationText {
                        Text(d)
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.vertical, 6)
    }

    private var posterURL: URL? {
        guard let client else { return nil }
        if entry.isEpisode, let sid = entry.seriesId, let tag = entry.imageTag {
            return client.imageURL(itemId: sid, tag: tag, maxWidth: 300)
        }
        return client.imageURL(itemId: entry.itemId, tag: entry.imageTag, maxWidth: 300)
    }
}

// MARK: - 清单详情

struct PlaylistDetailView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var store = PlaylistStore.shared

    let playlistId: String

    @State private var isEditing = false
    @State private var isPreparing = false
    @State private var playRequest: EntryPlayRequest?
    @State private var errorMessage: String?
    @State private var showRename = false
    @State private var renameText = ""

    private var client: EmbyClient? { appState.client }
    private var playlist: UserPlaylist? { store.playlist(id: playlistId) }
    private var entries: [PlaylistEntry] { playlist?.items ?? [] }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            Group {
                if entries.isEmpty {
                    EmptyStateView(systemImage: "list.bullet",
                                   title: "清单还是空的",
                                   subtitle: "在影片详情页点「加入清单」把内容收进来")
                } else {
                    List {
                        Section {
                            playAllRow
                        }
                        ForEach(entries) { e in
                            Button {
                                Task { await play(e) }
                            } label: {
                                EntryRow(entry: e, client: client,
                                         trailing: AnyView(
                                            Image(systemName: "play.circle.fill")
                                                .font(.system(size: 22))
                                                .foregroundStyle(AppTheme.accent)
                                         ))
                            }
                            .listRowBackground(AppTheme.card)
                        }
                        .onDelete { offsets in
                            for i in offsets { store.remove(itemId: entries[i].itemId, from: playlistId) }
                        }
                        .onMove { source, dest in
                            store.move(playlistId: playlistId, from: source, to: dest)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .environment(\.editMode, .constant(isEditing ? EditMode.active : EditMode.inactive))
                }
            }
        }
        .navigationTitle(playlist?.name ?? "清单")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    if !entries.isEmpty {
                        Button {
                            isEditing.toggle()
                        } label: {
                            Label(isEditing ? "完成排序" : "排序 / 删除", systemImage: "arrow.up.arrow.down")
                        }
                        Button {
                            Task { await playAll() }
                        } label: {
                            Label("从第一项开始连播", systemImage: "play.fill")
                        }
                    }
                    if let p = playlist, !p.isBuiltIn {
                        Button { renameText = p.name; showRename = true } label: {
                            Label("重命名", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            store.delete(id: playlistId)
                        } label: {
                            Label("删除清单", systemImage: "trash")
                        }
                    } else if !entries.isEmpty {
                        Button(role: .destructive) {
                            store.clear(playlistId: playlistId)
                        } label: {
                            Label("清空清单", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .overlay {
            if isPreparing {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("准备播放…")
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                    }
                    .padding(24)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppTheme.elevated))
                }
            }
        }
        .fullScreenCover(item: $playRequest) { req in
            if let c = client {
                PlayerView(client: c, item: req.item, playlist: req.playlist, startSeconds: req.startSeconds)
            }
        }
        .alert("出错了", isPresented: Binding(get: { errorMessage != nil },
                                              set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showRename) {
            NavigationView {
                ZStack {
                    AppTheme.background.ignoresSafeArea()
                    VStack(spacing: 16) {
                        TextField("清单名称", text: $renameText)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppTheme.elevated))
                            .foregroundStyle(AppTheme.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                        Spacer()
                    }
                }
                .navigationTitle("重命名")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showRename = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            store.rename(id: playlistId, to: renameText)
                            showRename = false
                        }
                    }
                }
            }
        }
    }

    private var playAllRow: some View {
        Button { Task { await playAll() } } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("连续播放全部（\(entries.count) 项）")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                LinearGradient(colors: [AppTheme.accent, AppTheme.accent.opacity(0.72)],
                               startPoint: .leading, endPoint: .trailing)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            )
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
    }

    // MARK: 播放

    @MainActor
    private func play(_ entry: PlaylistEntry) async {
        await start(with: entry)
    }

    @MainActor
    private func playAll() async {
        guard let first = entries.first else { return }
        await start(with: first)
    }

    @MainActor
    private func start(with entry: PlaylistEntry) async {
        guard let client else { return }
        isPreparing = true
        let items = await fetchItemsParallel(entries.map { $0.itemId }, client: client)
        isPreparing = false
        guard !items.isEmpty else {
            errorMessage = "这些条目在当前服务器上没有找到，可能已被删除或切换了服务器。"
            return
        }
        let target = items.first { $0.id == entry.itemId } ?? items[0]
        let start = target.resumeSeconds > 5 ? target.resumeSeconds : nil
        playRequest = EntryPlayRequest(item: target, playlist: items, startSeconds: start)
    }
}

// MARK: - 播放历史

struct HistoryListView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var store = PlaylistStore.shared

    @State private var isPreparing = false
    @State private var playRequest: EntryPlayRequest?
    @State private var errorMessage: String?
    @State private var showClearConfirm = false

    private var client: EmbyClient? { appState.client }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            Group {
                if store.history.isEmpty {
                    EmptyStateView(systemImage: "clock",
                                   title: "还没有播放记录",
                                   subtitle: "在本机播过的影片会出现在这里")
                } else {
                    List {
                        ForEach(store.history) { e in
                            Button { Task { await start(with: e) } } label: {
                                EntryRow(entry: e, client: client)
                            }
                            .listRowBackground(AppTheme.card)
                        }
                        .onDelete { offsets in
                            for i in offsets { store.removeHistory(store.history[i].itemId) }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
        }
        .navigationTitle("播放历史")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !store.history.isEmpty {
                    Button("清空") { showClearConfirm = true }
                }
            }
        }
        .confirmationDialog("清空播放历史？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清空", role: .destructive) { store.clearHistory() }
            Button("取消", role: .cancel) { }
        }
        .overlay { preparingOverlay }
        .fullScreenCover(item: $playRequest) { req in
            if let c = client {
                PlayerView(client: c, item: req.item, playlist: req.playlist, startSeconds: req.startSeconds)
            }
        }
        .alert("出错了", isPresented: Binding(get: { errorMessage != nil },
                                              set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var preparingOverlay: some View {
        Group {
            if isPreparing {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("准备播放…").font(.system(size: 13)).foregroundStyle(.white)
                    }
                    .padding(24)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppTheme.elevated))
                }
            }
        }
    }

    @MainActor
    private func start(with entry: PlaylistEntry) async {
        guard let client else { return }
        isPreparing = true
        let items = await fetchItemsParallel(store.history.map { $0.itemId }, client: client)
        isPreparing = false
        guard !items.isEmpty else {
            errorMessage = "这些条目在当前服务器上没有找到。"
            return
        }
        let target = items.first { $0.id == entry.itemId } ?? items[0]
        playRequest = EntryPlayRequest(item: target, playlist: items, startSeconds: nil)
    }
}

// MARK: - 继续观看

struct ResumeListView: View {
    @EnvironmentObject private var appState: AppState

    @State private var items: [BaseItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var target: BaseItem?

    private var client: EmbyClient? { appState.client }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            Group {
                if isLoading {
                    ProgressView("加载中…")
                } else if items.isEmpty {
                    EmptyStateView(systemImage: "play.circle",
                                   title: "没有正在看的内容",
                                   subtitle: "播过一部分的影片会出现在这里")
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 14)], spacing: 18) {
                            ForEach(items) { item in
                                Button { target = item } label: {
                                    PosterCard(item: item, client: client!)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .navigationTitle("继续观看")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .fullScreenCover(item: $target) { item in
            if let c = client {
                PlayerView(client: c, item: item, playlist: items, startSeconds: item.resumeSeconds)
            }
        }
        .alert("出错了", isPresented: Binding(get: { errorMessage != nil },
                                              set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func load() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await client.fetchResume(limit: 100)
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - 服务器播放列表内容

struct ServerPlaylistDetailView: View {
    @EnvironmentObject private var appState: AppState
    let playlist: BaseItem

    @State private var items: [BaseItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var target: BaseItem?

    private var client: EmbyClient? { appState.client }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            Group {
                if isLoading {
                    ProgressView("加载中…")
                } else if items.isEmpty {
                    EmptyStateView(systemImage: "music.note.list",
                                   title: "这个播放列表是空的",
                                   subtitle: nil)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 14)], spacing: 18) {
                            ForEach(items) { item in
                                Button { target = item } label: {
                                    PosterCard(item: item, client: client!)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .navigationTitle(playlist.Name ?? "播放列表")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .fullScreenCover(item: $target) { item in
            if let c = client {
                PlayerView(client: c, item: item, playlist: items, startSeconds: item.resumeSeconds)
            }
        }
        .alert("出错了", isPresented: Binding(get: { errorMessage != nil },
                                              set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func load() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await client.fetchPlaylistItems(playlist.id)
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }
}
