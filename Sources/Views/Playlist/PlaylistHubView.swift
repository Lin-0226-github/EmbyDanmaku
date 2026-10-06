//
//  PlaylistHubView.swift
//  EmbyDanmaku
//
//  「清单」页：顶部 继续观看 大列表（进度条样式），下方 我的清单 / 服务器播放列表。
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

// MARK: - 清单页

struct PlaylistHubView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var store = PlaylistStore.shared

    @State private var resumeItems: [BaseItem] = []
    @State private var serverPlaylists: [BaseItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""
    @State private var newPlaylistSymbol = "list.bullet"
    @State private var playRequest: EntryPlayRequest?
    @State private var addTarget: BaseItem?

    private var client: EmbyClient? { appState.client }

    private let symbolChoices = ["list.bullet", "star.fill", "heart.fill", "flame.fill",
                                 "tv.fill", "film.fill", "bolt.fill", "moon.stars.fill"]

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerRow
                        Text("继续观看")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .padding(.horizontal, 16)

                        resumeList

                        if !store.customPlaylists.isEmpty || !serverPlaylists.isEmpty {
                            SectionHeader(title: "我的清单", systemImage: "list.bullet",
                                          actionTitle: "新建",
                                          action: { showNewPlaylist = true })
                            myPlaylists
                                .padding(.horizontal, 16)
                        }

                        if !serverPlaylists.isEmpty {
                            SectionHeader(title: "服务器播放列表", systemImage: "server.rack")
                            serverSection
                                .padding(.horizontal, 16)
                        }

                        Color.clear.frame(height: 16)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationBarHidden(true)
            .refreshable { await reload() }
            .task { await reload() }
            .sheet(isPresented: $showNewPlaylist) { newPlaylistSheet }
            .sheet(item: $addTarget) { item in
                AddToPlaylistSheet(item: item)
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
        }
        .navigationViewStyle(.stack)
    }

    // MARK: 顶部

    private var headerRow: some View {
        HStack(spacing: 12) {
            Menu {
                NavigationLink { HistoryListView() } label: { Label("播放历史", systemImage: "clock") }
                NavigationLink { PlaylistDetailView(playlistId: PlaylistStore.watchLaterId) } label: { Label("稍后再看", systemImage: "bookmark") }
                Button { showNewPlaylist = true } label: { Label("新建清单", systemImage: "plus") }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(AppTheme.card))
            }

            Spacer(minLength: 0)

            NavigationLink { ResumeListView() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill").font(.system(size: 12, weight: .bold))
                    Text("继续观看").font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(AppTheme.accent))
            }
            .buttonStyle(.plain)

            NavigationLink { PlaylistDetailView(playlistId: PlaylistStore.watchLaterId) } label: {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(AppTheme.card))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    // MARK: 继续观看列表

    @ViewBuilder
    private var resumeList: some View {
        if isLoading && resumeItems.isEmpty {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.vertical, 40)
        } else if resumeItems.isEmpty {
            Text("没有正在看的内容，去媒体库挑一部吧")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
        } else {
            VStack(spacing: 12) {
                ForEach(resumeItems) { item in
                    Button {
                        openResume(item)
                    } label: {
                        ResumeRow(item: item,
                                  serverName: appState.currentServer?.name ?? "",
                                  client: appState.client)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            let serverId = appState.currentServer?.id ?? ""
                            store.toggleWatchLater(PlaylistEntry.make(from: item, serverId: serverId))
                        } label: {
                            Label("稍后再看", systemImage: "bookmark")
                        }
                        Button { addTarget = item } label: {
                            Label("加入清单…", systemImage: "plus")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
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
        }
    }

    private func playlistRow(_ p: UserPlaylist) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.elevated)
                    .frame(width: 42, height: 42)
                Image(systemName: p.symbol)
                    .font(.system(size: 17, weight: .semibold))
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
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppTheme.card))
    }

    // MARK: 服务器播放列表

    private var serverSection: some View {
        VStack(spacing: 10) {
            ForEach(serverPlaylists) { p in
                NavigationLink {
                    ServerPlaylistDetailView(playlist: p)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(AppTheme.elevated)
                                .frame(width: 42, height: 42)
                            Image(systemName: "music.note.list")
                                .font(.system(size: 17, weight: .semibold))
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

    // MARK: 数据 / 播放

    private func reload() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let r = client.fetchResume(limit: 30)
            async let p = client.fetchServerPlaylists()
            let (resumeResult, playlistResult) = try await (r, p)
            resumeItems = resumeResult
            serverPlaylists = playlistResult
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    private func openResume(_ item: BaseItem) {
        if item.isEpisode, let seriesId = item.SeriesId {
            Task {
                guard let client else { return }
                let eps = try? await client.fetchEpisodes(seriesId: seriesId)
                playRequest = EntryPlayRequest(item: item,
                                               playlist: eps ?? [item],
                                               startSeconds: item.resumeSeconds)
            }
        } else {
            playRequest = EntryPlayRequest(item: item, playlist: [item], startSeconds: item.resumeSeconds)
        }
    }
}

// MARK: - 继续观看行（带进度条）

struct ResumeRow: View {
    let item: BaseItem
    let serverName: String
    let client: EmbyClient?

    private var elapsed: Double { item.resumeSeconds }
    private var total: Double { item.durationSeconds }
    private var remaining: Double { max(0, total - elapsed) }
    private var progress: Double { min(1, max(0, item.progress)) }

    var body: some View {
        HStack(spacing: 12) {
            RemoteImageView(url: posterURL, placeholderSystemImage: item.isEpisode ? "tv" : "film")
                .frame(width: 64, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                Text(item.isEpisode ? (item.SeriesName ?? item.Name ?? "") : (item.Name ?? ""))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)

                if progress > 0.001 {
                    progressBar
                } else if let d = durationText {
                    Text(d)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
    }

    private var subtitle: String {
        var parts: [String] = []
        if item.isEpisode {
            if let s = item.ParentIndexNumber, let e = item.IndexNumber {
                parts.append(String(format: "S%d:E%d", s, e))
            }
            if let n = item.Name, !n.isEmpty { parts.append(n) }
        } else if let y = item.ProductionYear {
            parts.append(String(y))
        }
        if !serverName.isEmpty { parts.append(serverName) }
        if let d = daysAgoText { parts.append(d) }
        return parts.joined(separator: " · ")
    }

    private var durationText: String? {
        guard total > 0 else { return nil }
        return "\(Int(total / 60)) 分钟"
    }

    /// 「5 天前」这类相对时间，来自服务器记录的上次播放时间
    private var daysAgoText: String? {
        guard let raw = item.UserData?.LastPlayedDate, !raw.isEmpty else { return nil }
        var date = ISO8601DateFormatter().date(from: raw)
        if date == nil {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = f.date(from: raw)
        }
        guard let date = date else { return nil }
        let days = Int(Date().timeIntervalSince(date) / 86400)
        if days <= 0 { return "今天" }
        return "\(days) 天前"
    }

    private var posterURL: URL? {
        guard let c = client else { return nil }
        if let tag = item.primaryImageTag {
            return c.imageURL(itemId: item.id, tag: tag, maxWidth: 300)
        }
        if let sid = item.SeriesId, let tag = item.SeriesPrimaryImageTag {
            return c.imageURL(itemId: sid, tag: tag, maxWidth: 300)
        }
        return nil
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(AppTheme.elevated)
                Capsule()
                    .fill(AppTheme.accent)
                    .frame(width: max(10, geo.size.width * CGFloat(progress)))
                HStack {
                    Text(PlayerViewModel.formatTime(elapsed))
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.leading, 8)
                    Spacer()
                    Text(total > 0 ? "剩余 \(PlayerViewModel.formatTime(remaining)) · \(PlayerViewModel.formatTime(total))" : "")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.trailing, 8)
                }
            }
        }
        .frame(height: 22)
        .accessibilityHidden(true)
    }
}
