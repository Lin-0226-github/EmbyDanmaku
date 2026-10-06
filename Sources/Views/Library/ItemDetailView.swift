//
//  ItemDetailView.swift
//  EmbyDanmaku
//
//  条目详情：电影直接播放，剧集按季/集浏览。
//

import SwiftUI

struct ItemDetailView: View {
    @EnvironmentObject private var appState: AppState
    let item: BaseItem

    @State private var detail: BaseItem?
    @State private var seasons: [BaseItem] = []
    @State private var episodes: [BaseItem] = []
    @State private var selectedSeasonId: String?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var playTarget: PlayTarget?

    struct PlayTarget: Identifiable {
        var id: String { item.id + String(startSeconds ?? 0) }
        let item: BaseItem
        let playlist: [BaseItem]
        let startSeconds: Double?
    }

    private var shown: BaseItem { detail ?? item }
    private var client: EmbyClient? { appState.client }

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
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .fullScreenCover(item: $playTarget) { target in
            if let c = client {
                PlayerView(client: c, item: target.item, playlist: target.playlist, startSeconds: target.startSeconds)
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
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button { startPlayback() } label: {
                    HStack {
                        Image(systemName: shown.progress > 0.02 ? "play.fill" : "play.fill")
                        Text(shown.progress > 0.02 ? "继续播放" : "播放")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)

                Button { Task { await toggleWatched() } } label: {
                    Image(systemName: shown.watched ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 22))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)

                Button { Task { await toggleFavorite() } } label: {
                    Image(systemName: (shown.UserData?.IsFavorite ?? false) ? "heart.fill" : "heart")
                        .font(.system(size: 22))
                        .foregroundStyle((shown.UserData?.IsFavorite ?? false) ? .red : .primary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
            }

            if !shown.Genres.orEmpty.isEmpty {
                chipsRow(shown.Genres.orEmpty, systemImage: "tag")
            }
        }
        .padding(16)
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
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
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
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            if let ov = ep.Overview, !ov.isEmpty {
                                Text(ov)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
                Divider()
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
                               let url = appState.client?.imageURL(itemId: pid, tag: tag, maxWidth: 200) {
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
                            Text(p.Role ?? p.Type ?? "")
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
            errorMessage = error.localizedDescription
        }
    }

    private func loadEpisodes(seasonId: String) async {
        guard let client else { return }
        do {
            episodes = try await client.fetchEpisodes(seriesId: item.id, seasonId: seasonId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startPlayback() {
        if shown.isSeries, let first = episodes.first {
            playEpisode(first)
        } else {
            playTarget = PlayTarget(item: shown, playlist: [shown], startSeconds: shown.resumeSeconds)
        }
    }

    private func playEpisode(_ ep: BaseItem) {
        playTarget = PlayTarget(item: ep, playlist: episodes.isEmpty ? [ep] : episodes,
                                startSeconds: ep.resumeSeconds > 5 ? ep.resumeSeconds : nil)
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
            errorMessage = error.localizedDescription
        }
    }

    private func toggleFavorite() async {
        guard let client else { return }
        do {
            try await client.setFavorite(shown.id, favorite: !(shown.UserData?.IsFavorite ?? false))
            detail = try await client.fetchItem(item.id)
        } catch {
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

extension Optional where Wrapped == [String] {
    var orEmpty: [String] { self ?? [] }
}
