//
//  PlaylistHubView.swift
//  EmbyDanmaku
//
//  「清单」页：继续观看 / 播放历史 / 稍后再看 / 我的清单 / 服务器播放列表。
//

import SwiftUI

/// 播放请求（从清单条目发起）
struct EntryPlayRequest: Identifiable {
    var id: String { item.id }
    let item: BaseItem
    let playlist: [BaseItem]
    let startSeconds: Double?
}

/// 并行把一组 itemId 取回完整条目，并保持传入顺序
func fetchItemsParallel(_ ids: [String], client: EmbyClient) async -> [BaseItem] {
    let found = await withTaskGroup(of: BaseItem?.self) { group -> [BaseItem?] in
        for id in ids {
            group.addTask { try? await client.fetchItem(id) }
        }
        var out: [BaseItem?] = []
        for await item in group { out.append(item) }
        return out
    }
    var map: [String: BaseItem] = [:]
    for item in found.compactMap({ $0 }) { map[item.id] = item }
    return ids.compactMap { map[$0] }
}

// MARK: - 清单中心

struct PlaylistHubView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var store = PlaylistStore.shared

    @State private var serverPlaylists: [BaseItem] = []
    @State private var isLoadingServer = false
    @State private var errorMessage: String?
    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""
    @State private var newPlaylistSymbol = "list.bullet"
    @State private var playRequest: EntryPlayRequest?

    private var client: EmbyClient? { appState.client }

    private let symbolChoices = ["list.bullet", "star.fill", "heart.fill", "flame.fill",
                                 "tv.fill", "film.fill", "bolt.fill", "moon.stars.fill"]

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {

                        // 快捷入口
                        SectionHeader(title: "快捷", systemImage: "bolt.fill")
                        quickRow
                            .padding(.horizontal, 16)

                        // 我的清单
                        SectionHeader(title: "我的清单", systemImage: "list.bullet",
                                      actionTitle: "新建",
                                      action: { showNewPlaylist = true })
                        myPlaylists
                            .padding(.horizontal, 16)

                        // 服务器播放列表
                        SectionHeader(title: "服务器播放列表", systemImage: "server.rack")
                        serverSection
                            .padding(.horizontal, 16)

                        Color.clear.frame(height: 20)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("清单")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showNewPlaylist = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task { await loadServerPlaylists() }
            .refreshable { await loadServerPlaylists() }
            .sheet(isPresented: $showNewPlaylist) { newPlaylistSheet }
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
        .navigationViewStyle(.stack)
    }

    // MARK: 快捷入口

    private var quickRow: some View {
        VStack(spacing: 10) {
            NavigationLink {
                ResumeListView()
            } label: {
                quickCard(title: "继续观看",
                          subtitle: "服务器记录的播放进度",
                          symbol: "play.circle.fill",
                          tint: AppTheme.accent)
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                NavigationLink {
                    HistoryListView()
                } label: {
                    quickCard(title: "播放历史",
                              subtitle: "本机的 \(store.history.count) 条记录",
                              symbol: "clock.fill",
                              tint: AppTheme.warning)
                }
                .buttonStyle(.plain)

                NavigationLink {
                    PlaylistDetailView(playlistId: PlaylistStore.watchLaterId)
                } label: {
                    quickCard(title: "稍后再看",
                              subtitle: store.watchLater.countText,
                              symbol: "bookmark.fill",
                              tint: AppTheme.accentWarm)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func quickCard(title: String, subtitle: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .frame(width: 44, height: 44)
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
    }

    // MARK: 我的清单

    private var myPlaylists: some View {
        VStack(spacing: 10) {
            ForEach(store.customPlaylists) { p in
                NavigationLink {
                    PlaylistDetailView(playlistId: p.id)
                } label: {
                    playlistRow(p)
                }
                .buttonStyle(.plain)
            }

            Button { showNewPlaylist = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppTheme.textTertiary)
                    Text("新建清单")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                    Spacer()
                }
                .padding(12)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppTheme.card)
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppTheme.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    }
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func playlistRow(_ p: UserPlaylist) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(AppTheme.elevated)
                    .frame(width: 46, height: 46)
                Image(systemName: p.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Text(p.countText)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            Spacer(minLength: 0)
            if let first = p.items.first, let c = client {
                RemoteImageView(url: c.imageURL(itemId: first.itemId, tag: first.imageTag, maxWidth: 200),
                                placeholderSystemImage: "film")
                    .frame(width: 34, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.card)
        )
    }

    // MARK: 服务器播放列表

    private var serverSection: some View {
        Group {
            if isLoadingServer && serverPlaylists.isEmpty {
                HStack {
                    ProgressView()
                    Text("读取服务器播放列表…")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppTheme.card))
            } else if serverPlaylists.isEmpty {
                Text("服务器上还没有播放列表")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppTheme.card))
            } else {
                VStack(spacing: 10) {
                    ForEach(serverPlaylists) { p in
                        NavigationLink {
                            ServerPlaylistDetailView(playlist: p)
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(AppTheme.elevated)
                                        .frame(width: 46, height: 46)
                                    Image(systemName: "music.note.list")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(AppTheme.success)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.Name ?? "播放列表")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(AppTheme.textPrimary)
                                        .lineLimit(1)
                                    Text("\(p.ChildCount ?? 0) 项")
                                        .font(.system(size: 12))
                                        .foregroundStyle(AppTheme.textTertiary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(AppTheme.textTertiary)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppTheme.card))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: 新建清单

    private var newPlaylistSheet: some View {
        NavigationView {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                Form {
                    Section {
                        TextField("清单名称", text: $newPlaylistName)
                    } header: {
                        Text("名称")
                    }

                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(symbolChoices, id: \.self) { s in
                                    Button { newPlaylistSymbol = s } label: {
                                        Image(systemName: s)
                                            .font(.system(size: 18))
                                            .foregroundStyle(newPlaylistSymbol == s ? .white : AppTheme.textSecondary)
                                            .frame(width: 42, height: 42)
                                            .background(
                                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                                    .fill(newPlaylistSymbol == s ? AppTheme.accent : AppTheme.elevated)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text("图标")
                    }
                }
            }
            .navigationTitle("新建清单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showNewPlaylist = false; newPlaylistName = "" }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        store.create(name: newPlaylistName, symbol: newPlaylistSymbol)
                        newPlaylistName = ""
                        showNewPlaylist = false
                    }
                }
            }
        }
    }

    // MARK: 数据

    private func loadServerPlaylists() async {
        guard let client else { return }
        isLoadingServer = true
        defer { isLoadingServer = false }
        do {
            serverPlaylists = try await client.fetchServerPlaylists()
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }
}
