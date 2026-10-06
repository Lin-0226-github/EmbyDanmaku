//
//  ItemDetailView.swift
//  EmbyDanmaku
//
//  条目详情：电影直接播放，剧集按季/集浏览。
//

import SwiftUI

struct ItemDetailView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var store = PlaylistStore.shared
    let item: BaseItem
    /// 指定用哪个服务器的客户端浏览/播放（跨服务器搜索结果、片源切换进入时传入）
    var clientOverride: EmbyClient? = nil
    var serverNameOverride: String? = nil

    @State private var detail: BaseItem?
    @State private var seasons: [BaseItem] = []
    @State private var episodes: [BaseItem] = []
    @State private var selectedSeasonId: String?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var playTarget: PlayTarget?
    @State private var showAddToPlaylist = false
    @State private var showSourceSheet = false

    struct PlayTarget: Identifiable {
        var id: String { item.id + String(startSeconds ?? 0) }
        let item: BaseItem
        let playlist: [BaseItem]
        let startSeconds: Double?
        var clientOverride: EmbyClient? = nil
    }

    private var shown: BaseItem { detail ?? item }
    private var client: EmbyClient? { clientOverride ?? appState.client }
    private var serverName: String { serverNameOverride ?? appState.currentServer?.name ?? "" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                infoSection
                if shown.isSeries {
                    seasonSection
                }
                overviewSection
                if let people = shown.People, !people.isEmpty {
                    castSection(people)
                }
                Color.clear.frame(height: 24)
            }
        }
        .appBackground()
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistSheet(item: shown, episodes: shown.isSeries ? episodes : [])
        }
        .fullScreenCover(item: $playTarget) { target in
            if let c = target.clientOverride ?? client {
                PlayerView(client: c, item: target.item, playlist: target.playlist, startSeconds: target.startSeconds)
            }
        }
        .sheet(isPresented: $showSourceSheet) {
            ItemSourceSheet(item: shown) { target in
                showSourceSheet = false
                playTarget = target
            }
        }
        .alert("出错了", isPresented: Binding(get: { errorMessage != nil },
                                              set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - 头部

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geo in
                RemoteImageView(url: backdropURL, placeholderSystemImage: "photo")
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .overlay {
                        LinearGradient(colors: [.clear, .black.opacity(0.75)],
                                       startPoint: .center, endPoint: .bottom)
                    }
            }
            .frame(height: 220)

            HStack(alignment: .bottom, spacing: 12) {
                RemoteImageView(url: posterURL, placeholderSystemImage: "film")
                    .frame(width: 96, height: 144)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(radius: 6)
                VStack(alignment: .leading, spacing: 4) {
                    Text(shown.Name ?? "")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                    metaLine
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }

    private var metaLine: some View {
        let parts = [shown.ProductionYear.map(String.init),
                     shown.OfficialRating,
                     durationText,
                     shown.CommunityRating.map { String(format: "%.1f 分", $0) }]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return Text(parts.joined(separator: " · "))
    }

    private var durationText: String? {
        let d = shown.durationSeconds
        guard d > 0 else { return nil }
        let m = Int(d / 60)
        return "\(m) 分钟"
    }

    // MARK: - 操作区

    private var infoSection: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                PrimaryPlayButton(title: shown.progress > 0.02 ? "继续播放" : "播放",
                                  isLoading: isLoading) {
                    startPlayback()
                }

                CircleIconButton(systemImage: shown.watched ? "checkmark.circle.fill" : "checkmark.circle",
                                 active: shown.watched,
                                 activeColor: AppTheme.success) {
                    Task { await toggleWatched() }
                }

                CircleIconButton(systemImage: (shown.UserData?.IsFavorite ?? false) ? "heart.fill" : "heart",
                                 active: shown.UserData?.IsFavorite ?? false,
                                 activeColor: AppTheme.accentWarm) {
                    Task { await toggleFavorite() }
                }

                CircleIconButton(systemImage: store.isInWatchLater(shown.id) ? "bookmark.fill" : "bookmark",
                                 active: store.isInWatchLater(shown.id),
                                 activeColor: AppTheme.accentWarm) {
                    toggleWatchLater()
                }

                CircleIconButton(systemImage: "plus", active: false, activeColor: AppTheme.accent) {
                    showAddToPlaylist = true
                }
            }

            if let genres = shown.Genres?.names, !genres.isEmpty {
                chipsRow(genres, systemImage: "tag")
            }

            // 片源：多服务器时可在其他服务器上找同名片并切换播放
            if appState.servers.count > 1 {
                Button { showSourceSheet = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left.arrow.right.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                        Text("片源 · \(serverName)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text("切换")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppTheme.hairline, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func toggleWatchLater() {
        let serverId = appState.currentServer?.id ?? ""
        store.toggleWatchLater(PlaylistEntry.make(from: shown, serverId: serverId))
    }

    private func chipsRow(_ items: [String], systemImage: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(items, id: \.self) { t in
                    Text(t)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(AppTheme.elevated, in: Capsule())
                }
            }
        }
    }

    // MARK: - 剧集

    private var seasonSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if seasons.count > 1 {
                Picker("季", selection: Binding(get: { selectedSeasonId ?? seasons.first?.id ?? "" },
                                                set: { newId in
                                                    selectedSeasonId = newId
                                                    Task { await loadEpisodes(seasonId: newId) }
                                                })) {
                    ForEach(seasons) { s in
                        Text(s.Name ?? "第 \(s.IndexNumber ?? 0) 季").tag(s.id)
                    }
                }
                .pickerStyle(.segmented)
            }

            ForEach(episodes) { ep in
                Button { playEpisode(ep) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        RemoteImageView(url: episodeStill(ep), placeholderSystemImage: "tv")
                            .frame(width: 128, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ep.displayTitle)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                                .lineLimit(2)
                            if let ov = ep.Overview, !ov.isEmpty {
                                Text(ov)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textTertiary)
                                    .lineLimit(3)
                            }
                            HStack(spacing: 8) {
                                if ep.watched {
                                    Label("已看", systemImage: "checkmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                }
                                if ep.progress > 0.02, !ep.watched {
                                    ProgressView(value: ep.progress)
                                        .frame(width: 60)
                                }
                                if let d = ep.RunTimeTicks, d > 0 {
                                    Text("\(Int(Double(d) / 10_000_000 / 60)) 分钟")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        let serverId = appState.currentServer?.id ?? ""
                        store.toggleWatchLater(PlaylistEntry.make(from: ep, serverId: serverId))
                    } label: {
                        Label("加入稍后再看", systemImage: "bookmark")
                    }
                }
                Divider()
                    .background(AppTheme.hairline)
            }
        }
        .padding(.horizontal, 16)
    }

    private var overviewSection: some View {
        Group {
            if let ov = shown.Overview, !ov.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("简介")
                        .font(.headline)
                    Text(ov)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    private func castSection(_ people: [EmbyPerson]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("演职人员")
                .font(.headline)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(people.prefix(24)) { p in
                        VStack(spacing: 4) {
                            if let tag = p.PrimaryImageTag, let pid = p.Id,
                               let url = client?.imageURL(itemId: pid, tag: tag, maxWidth: 200) {
                                RemoteImageView(url: url, placeholderSystemImage: "person.circle")
                                    .frame(width: 62, height: 62)
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 56))
                                    .foregroundStyle(.secondary)
                            }
                            Text(p.Name ?? "")
                                .font(.caption2)
                                .lineLimit(1)
                                .frame(width: 70)
                            Text(p.Role ?? p.ItemType ?? "")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(width: 70)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - 数据

    private func load() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await client.fetchItem(item.id)
            guard shown.isSeries else { return }
            let s = try await client.fetchSeasons(seriesId: item.id)
            seasons = s
            let firstId = s.first(where: { ($0.UserData?.UnplayedItemCount ?? 0) > 0 })?.id ?? s.first?.id
            selectedSeasonId = firstId
            if let firstId { await loadEpisodes(seasonId: firstId) }
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    private func loadEpisodes(seasonId: String) async {
        guard let client else { return }
        do {
            episodes = try await client.fetchEpisodes(seriesId: item.id, seasonId: seasonId)
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    private func startPlayback() {
        if shown.isSeries, let first = episodes.first {
            playEpisode(first)
        } else {
            playTarget = PlayTarget(item: shown, playlist: [shown], startSeconds: shown.resumeSeconds,
                                    clientOverride: client)
        }
    }

    private func playEpisode(_ ep: BaseItem) {
        playTarget = PlayTarget(item: ep, playlist: episodes.isEmpty ? [ep] : episodes,
                                startSeconds: ep.resumeSeconds > 5 ? ep.resumeSeconds : nil,
                                clientOverride: client)
    }

    private func toggleWatched() async {
        guard let client else { return }
        do {
            if shown.watched {
                try await client.markUnplayed(shown.id)
            } else {
                try await client.markPlayed(shown.id)
            }
            detail = try await client.fetchItem(item.id)
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    private func toggleFavorite() async {
        guard let client else { return }
        do {
            try await client.setFavorite(shown.id, favorite: !(shown.UserData?.IsFavorite ?? false))
            detail = try await client.fetchItem(item.id)
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 图片

    private var backdropURL: URL? {
        guard let client else { return nil }
        let id = shown.ParentBackdropItemId ?? shown.id
        let tag = shown.ParentBackdropImageTags?.first ?? shown.backdropImageTag
        return client.backdropURL(itemId: id, tag: tag, maxWidth: 1200)
    }

    private var posterURL: URL? {
        guard let client else { return nil }
        return client.imageURL(itemId: shown.id, tag: shown.primaryImageTag, maxWidth: 400)
    }

    private func episodeStill(_ ep: BaseItem) -> URL? {
        guard let client else { return nil }
        if let tag = ep.primaryImageTag {
            return client.imageURL(itemId: ep.id, imageType: "Primary", tag: tag, maxWidth: 500)
        }
        if let sid = ep.SeriesId, let stag = ep.SeriesPrimaryImageTag {
            return client.imageURL(itemId: sid, imageType: "Primary", tag: stag, maxWidth: 500)
        }
        return nil
    }
}

// MARK: - 切换片源（在其他服务器上找同名片）

struct ItemSourceSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let item: BaseItem
    var onPick: (ItemDetailView.PlayTarget) -> Void

    struct Match: Identifiable {
        let id: String
        let server: EmbyServer
        let client: EmbyClient
        let item: BaseItem
    }

    @State private var matches: [Match] = []
    @State private var isSearching = true
    @State private var searchTerm = ""

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("在其他已登录的服务器上搜索「\(searchTerm)」，点击即可切换到该服务器播放。")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.textTertiary)

                        if isSearching {
                            HStack {
                                Spacer()
                                ProgressView("正在搜索其他服务器…")
                                Spacer()
                            }
                            .padding(.vertical, 40)
                        } else if matches.isEmpty {
                            EmptyStateView(systemImage: "arrow.left.arrow.right.circle",
                                           title: "其他服务器没有找到这部影片",
                                           subtitle: "只有已登录（有保存凭据）的服务器会被搜索")
                        } else {
                            ForEach(matches) { m in
                                matchRow(m)
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("切换片源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .task { await search() }
        }
        .navigationViewStyle(.stack)
    }

    private func matchRow(_ m: Match) -> some View {
        Button {
            Task { await pick(m) }
        } label: {
            HStack(spacing: 12) {
                RemoteImageView(url: posterURL(m), placeholderSystemImage: "film")
                    .frame(width: 52, height: 74)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(m.item.Name ?? "")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 10))
                        Text(m.server.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(AppTheme.accent)
                    Text(m.item.isSeries ? "剧集 · 点击播放第一集" : "电影")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func posterURL(_ m: Match) -> URL? {
        if let tag = m.item.primaryImageTag {
            return m.client.imageURL(itemId: m.item.id, tag: tag, maxWidth: 300)
        }
        return nil
    }

    /// 并行搜索所有其他已登录服务器
    private func search() async {
        searchTerm = item.SeriesName ?? item.Name ?? ""
        guard !searchTerm.isEmpty else {
            isSearching = false
            return
        }
        let currentId = appState.currentServer?.id ?? ""
        let targets = appState.servers
            .filter { $0.id != currentId }
            .compactMap { s -> (EmbyServer, EmbyClient)? in
                guard let c = appState.client(for: s) else { return nil }
                return (s, c)
            }
        guard !targets.isEmpty else {
            isSearching = false
            return
        }

        let found = await withTaskGroup(of: [Match].self) { group -> [Match] in
            for (server, client) in targets {
                group.addTask {
                    let items = (try? await client.search(term: searchTerm,
                                                          types: ["Movie", "Series"],
                                                          limit: 20)) ?? []
                    let kw = searchTerm.lowercased()
                    let hits = items.filter { it in
                        guard let n = it.Name?.lowercased(), !n.isEmpty else { return false }
                        return n.contains(kw) || kw.contains(n)
                    }.prefix(2)
                    return hits.map {
                        Match(id: server.id + "/" + $0.id, server: server, client: client, item: $0)
                    }
                }
            }
            var out: [Match] = []
            for await r in group { out.append(contentsOf: r) }
            return out
        }
        matches = found
        isSearching = false
    }

    private func pick(_ m: Match) async {
        let target: ItemDetailView.PlayTarget
        if m.item.isSeries {
            let eps = (try? await m.client.fetchEpisodes(seriesId: m.item.id)) ?? []
            let first = eps.first ?? m.item
            target = ItemDetailView.PlayTarget(item: first,
                                               playlist: eps.isEmpty ? [m.item] : eps,
                                               startSeconds: first.resumeSeconds > 5 ? first.resumeSeconds : nil,
                                               clientOverride: m.client)
        } else {
            target = ItemDetailView.PlayTarget(item: m.item,
                                               playlist: [m.item],
                                               startSeconds: m.item.resumeSeconds,
                                               clientOverride: m.client)
        }
        onPick(target)
    }
}

