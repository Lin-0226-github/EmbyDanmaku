//
//  HomeView.swift
//  EmbyDanmaku
//
//  首页：继续观看、最近加入、媒体库入口。
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState

    @State private var views: [BaseItem] = []
    @State private var resumeItems: [BaseItem] = []
    @State private var latestItems: [BaseItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var playingItem: PlayRequest?

    struct PlayRequest: Identifiable {
        var id: String { item.id }
        let item: BaseItem
        let playlist: [BaseItem]
        let startSeconds: Double?
    }

    private var client: EmbyClient? { appState.client }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !resumeItems.isEmpty {
                        sectionHeader("继续观看", systemImage: "clock.arrow.circlepath")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(resumeItems) { item in
                                    Button { open(item) } label: {
                                        WideCard(item: item, client: client!)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    if !latestItems.isEmpty {
                        sectionHeader("最近加入", systemImage: "sparkles")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(latestItems) { item in
                                    NavigationLink {
                                        ItemDetailView(item: item)
                                    } label: {
                                        PosterCard(item: item, client: client!)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    sectionHeader("媒体库", systemImage: "square.grid.2x2")
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
                }
                .padding(.vertical, 12)
            }
            .navigationTitle(appState.currentServer?.name ?? "媒体库")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            appState.switchServer()
                        } label: {
                            Label("切换服务器", systemImage: "server.rack")
                        }
                    } label: {
                        Image(systemName: "person.circle")
                    }
                }
            }
            .refreshable { await reload() }
            .overlay {
                if isLoading && resumeItems.isEmpty && views.isEmpty {
                    ProgressView("加载中…")
                }
            }
            .task { await reload() }
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

    // MARK: - 视图组件

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.headline)
        }
        .padding(.horizontal, 16)
    }

    private func libraryTile(_ v: BaseItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [.accentColor.opacity(0.85), .accentColor.opacity(0.45)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(height: 76)
            VStack(alignment: .leading, spacing: 2) {
                Text(v.Name ?? "")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let type = v.CollectionType {
                    Text(type == "movies" ? "电影" : (type == "tvshows" ? "剧集" : type))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(12)
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

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载中…")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
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
