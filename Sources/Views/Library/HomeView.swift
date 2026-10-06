//
//  HomeView.swift
//  EmbyDanmaku
//
//  首页：继续观看、最近加入、媒体库入口。深色卡片风格。
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var store = PlaylistStore.shared

    @State private var views: [BaseItem] = []
    @State private var resumeItems: [BaseItem] = []
    @State private var latestItems: [BaseItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var playingItem: PlayRequest?
    @State private var addTarget: BaseItem?

    struct PlayRequest: Identifiable {
        var id: String { item.id }
        let item: BaseItem
        let playlist: [BaseItem]
        let startSeconds: Double?
    }

    private var client: EmbyClient? { appState.client }

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        titleBlock

                        if !resumeItems.isEmpty {
                            SectionHeader(title: "继续观看", systemImage: "play.circle.fill")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(resumeItems) { item in
                                        Button { open(item) } label: {
                                            WideCard(item: item, client: client!)
                                        }
                                        .buttonStyle(.plain)
                                        .contextMenu { itemMenu(item) }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }

                        if !latestItems.isEmpty {
                            SectionHeader(title: "最近加入", systemImage: "sparkles")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(latestItems) { item in
                                        NavigationLink {
                                            ItemDetailView(item: item)
                                        } label: {
                                            PosterCard(item: item, client: client!)
                                        }
                                        .buttonStyle(.plain)
                                        .contextMenu { itemMenu(item) }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }

                        SectionHeader(title: "媒体库", systemImage: "square.grid.2x2.fill")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                            ForEach(views) { v in
                                NavigationLink {
                                    LibraryGridView(view: v)
                                } label: {
                                    libraryTile(v)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)

                        Color.clear.frame(height: 16)
                    }
                    .padding(.vertical, 12)
                }
            }
            .navigationBarHidden(true)
            .refreshable { await reload() }
            .overlay {
                if isLoading && resumeItems.isEmpty && views.isEmpty {
                    ProgressView("加载中…")
                }
            }
            .task { await reload() }
            .sheet(item: $addTarget) { item in
                AddToPlaylistSheet(item: item)
            }
            .fullScreenCover(item: $playingItem) { req in
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

    // MARK: - 顶部

    private var titleBlock: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("媒体库")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                HStack(spacing: 6) {
                    if let s = appState.currentServer {
                        Text(s.name)
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.textTertiary)
                            .lineLimit(1)
                    }
                    if let u = appState.currentUserName {
                        Text("· \(u)")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }
            }
            Spacer(minLength: 0)
            Menu {
                Button {
                    appState.switchServer()
                } label: {
                    Label("切换服务器", systemImage: "server.rack")
                }
            } label: {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func itemMenu(_ item: BaseItem) -> some View {
        Button {
            let serverId = appState.currentServer?.id ?? ""
            store.toggleWatchLater(PlaylistEntry.make(from: item, serverId: serverId))
        } label: {
            Label("稍后再看", systemImage: "bookmark")
        }
        Button {
            addTarget = item
        } label: {
            Label("加入清单…", systemImage: "plus")
        }
    }

    // MARK: - 视图组件

    private func libraryTile(_ v: BaseItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [AppTheme.accent.opacity(0.9), AppTheme.accent.opacity(0.42)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(height: 78)
            VStack(alignment: .leading, spacing: 3) {
                Text(v.Name ?? "")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(typeName(v))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.82))
                    if let c = v.RecursiveItemCount, c > 0 {
                        Text("· \(c) 项")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .padding(12)
        }
    }

    private func typeName(_ v: BaseItem) -> String {
        switch v.CollectionType {
        case "movies": return "电影"
        case "tvshows": return "剧集"
        case "music": return "音乐"
        case "books": return "图书"
        case "homevideos": return "家庭视频"
        default: return v.CollectionType ?? "媒体"
        }
    }

    // MARK: - 数据

    private func reload() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let v = client.fetchViews()
            async let r = client.fetchResume()
            async let l = client.fetchLatest()
            let (viewsResult, resumeResult, latestResult) = try await (v, r, l)
            views = viewsResult
            resumeItems = resumeResult
            latestItems = latestResult
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    private func open(_ item: BaseItem) {
        if item.isEpisode, let seriesId = item.SeriesId {
            Task {
                guard let client else { return }
                let eps = try? await client.fetchEpisodes(seriesId: seriesId)
                playingItem = PlayRequest(item: item,
                                          playlist: eps ?? [item],
                                          startSeconds: item.resumeSeconds)
            }
        } else {
            playingItem = PlayRequest(item: item, playlist: [item], startSeconds: item.resumeSeconds)
        }
    }
}

// MARK: - 媒体库网格

struct LibraryGridView: View {
    @EnvironmentObject private var appState: AppState
    let view: BaseItem

    @State private var items: [BaseItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var sortAscending = true
    @State private var addTarget: BaseItem?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 14)]

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            Group {
                if isLoading {
                    ProgressView("加载中…")
                } else if items.isEmpty {
                    EmptyStateView(systemImage: "square.grid.2x2",
                                   title: "这个库里还没有内容",
                                   subtitle: nil)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(items) { item in
                                NavigationLink {
                                    ItemDetailView(item: item)
                                } label: {
                                    PosterCard(item: item, client: appState.client!)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .navigationTitle(view.Name ?? "媒体库")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    sortAscending.toggle()
                    Task { await load() }
                } label: {
                    Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                }
            }
        }
        .task { await load() }
        .sheet(item: $addTarget) { item in
            AddToPlaylistSheet(item: item)
        }
        .alert("出错了", isPresented: Binding(get: { errorMessage != nil },
                                              set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let r = try await client.fetchItems(parentId: view.id,
                                                recursive: true,
                                                sortBy: ["SortName"],
                                                sortOrder: sortAscending ? "Ascending" : "Descending",
                                                limit: 500)
            items = r.Items ?? []
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }
}
