//
//  HomeView.swift
//  EmbyDanmaku
//
//  首页：全屏海报轮播 + 「我的媒体」入口。深色沉浸风格。
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var store = PlaylistStore.shared

    @State private var views: [BaseItem] = []
    @State private var latestItems: [BaseItem] = []
    @State private var heroIndex = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var addTarget: BaseItem?

    private var client: EmbyClient? { appState.client }

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !latestItems.isEmpty {
                            heroCarousel
                        } else if isLoading {
                            RoundedRectangle(cornerRadius: 0, style: .continuous)
                                .fill(AppTheme.card)
                                .frame(height: 430)
                                .overlay(ProgressView())
                        }

                        myMediaSection
                            .padding(.top, 18)

                        Color.clear.frame(height: 16)
                    }
                }
            }
            .navigationBarHidden(true)
            .refreshable { await reload() }
            .task { await reload() }
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
        .navigationViewStyle(.stack)
    }

    // MARK: - 海报轮播

    private var heroCarousel: some View {
        VStack(spacing: 10) {
            TabView(selection: $heroIndex) {
                ForEach(Array(latestItems.prefix(8).enumerated()), id: \.element.id) { idx, item in
                    NavigationLink {
                        ItemDetailView(item: item)
                    } label: {
                        heroCard(item)
                    }
                    .buttonStyle(.plain)
                    .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 430)

            // 自绘页点
            HStack(spacing: 7) {
                let count = min(8, latestItems.count)
                ForEach(0..<max(count, 1), id: \.self) { i in
                    Capsule()
                        .fill(i == heroIndex ? AppTheme.accent : Color.white.opacity(0.25))
                        .frame(width: i == heroIndex ? 16 : 6, height: 6)
                        .animation(.easeOut(duration: 0.2), value: heroIndex)
                }
            }
        }
    }

    private func heroCard(_ item: BaseItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImageView(url: backdropURL(item),
                            placeholderSystemImage: "photo")
                .frame(height: 430)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(
                    LinearGradient(colors: [.clear, .clear, AppTheme.background.opacity(0.75), AppTheme.background],
                                   startPoint: .top, endPoint: .bottom)
                )

            // 左上角 App 标识
            VStack {
                HStack {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(AppTheme.success)
                            .frame(width: 15, height: 15)
                        Text("Lplayers")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.black.opacity(0.42)))
                    .padding(.leading, 14)
                    .padding(.top, 6)
                    Spacer(minLength: 0)
                }
                Spacer()
            }

            // 底部信息
            VStack(alignment: .leading, spacing: 8) {
                Text(item.Name ?? "")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    if let r = item.CommunityRating {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.accent)
                            Text(String(format: "%.1f", r))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    if let g = item.Genres?.names.first {
                        Text(g)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    if let y = item.ProductionYear {
                        Text(String(y))
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }

                if let ov = item.Overview, !ov.isEmpty {
                    Text(ov)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(2)
                        .lineSpacing(3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .contextMenu { itemMenu(item) }
    }

    // MARK: - 我的媒体

    private var myMediaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "我的媒体", systemImage: "square.grid.2x2.fill")
                .padding(.horizontal, 16)

            if views.isEmpty && isLoading {
                HStack {
                    ProgressView()
                    Text("正在读取媒体库…")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(views) { v in
                        NavigationLink {
                            LibraryGridView(view: v)
                        } label: {
                            mediaTile(v)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func mediaTile(_ v: BaseItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImageView(url: backdropURL(v), placeholderSystemImage: "square.grid.2x2")
                .frame(height: 110)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(
                    LinearGradient(colors: [.clear, .black.opacity(0.62)],
                                   startPoint: .center, endPoint: .bottom)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.hairline, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(v.Name ?? "")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let c = v.RecursiveItemCount, c > 0 {
                    Text("\(c) 项")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .padding(10)
        }
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

    // MARK: - 数据

    private func backdropURL(_ item: BaseItem) -> URL? {
        guard let client else { return nil }
        if let tag = item.backdropImageTag {
            return client.backdropURL(itemId: item.id, tag: tag, maxWidth: 1000)
        }
        return client.imageURL(itemId: item.id, tag: item.primaryImageTag, maxWidth: 800)
    }

    private func reload() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let v = client.fetchViews()
            async let l = client.fetchLatest()
            let (viewsResult, latestResult) = try await (v, l)
            views = viewsResult
            latestItems = latestResult
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - 媒体库 Tab（选库 + 网格）

struct LibraryTabView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var store = PlaylistStore.shared

    @State private var views: [BaseItem] = []
    @State private var items: [BaseItem] = []
    @State private var selectedId: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var sortAscending = true
    @State private var addTarget: BaseItem?

    private var client: EmbyClient? { appState.client }

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    if views.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(views) { v in
                                    CapsuleButton(title: v.Name ?? "",
                                                  isActive: selectedId == v.id) {
                                        select(v)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                    }

                    if isLoading && items.isEmpty {
                        Spacer()
                        ProgressView("加载中…")
                        Spacer()
                    } else if items.isEmpty {
                        Spacer()
                        EmptyStateView(systemImage: "square.grid.2x2",
                                       title: "这个库里还没有内容",
                                       subtitle: nil)
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 106), spacing: 14)], spacing: 18) {
                                ForEach(items) { item in
                                    NavigationLink {
                                        ItemDetailView(item: item)
                                    } label: {
                                        PosterCard(item: item, client: client!)
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
                            .padding(.vertical, 14)
                        }
                    }
                }
            }
            .navigationTitle("媒体库")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        sortAscending.toggle()
                        Task { await loadItems() }
                    } label: {
                        Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                    }
                }
            }
            .task { await loadViews() }
            .refreshable { await loadViews() }
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
        .navigationViewStyle(.stack)
    }

    private func select(_ v: BaseItem) {
        selectedId = v.id
        Task { await loadItems() }
    }

    private func loadViews() async {
        guard let client else { return }
        do {
            views = try await client.fetchViews()
            if selectedId == nil {
                selectedId = views.first?.id
            }
            await loadItems()
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    private func loadItems() async {
        guard let client, let id = selectedId else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let r = try await client.fetchItems(parentId: id,
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
