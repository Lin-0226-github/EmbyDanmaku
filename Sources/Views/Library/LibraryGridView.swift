//
//  LibraryGridView.swift
//  EmbyDanmaku
//
//  单个媒体库（如「电影」「电视剧」）的内容网格：海报 + 标题，支持排序切换。
//

import SwiftUI

struct LibraryGridView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var store = PlaylistStore.shared

    /// 上级媒体库（Emby 的 Views 条目）
    let view: BaseItem

    @State private var items: [BaseItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var sortAscending = true
    @State private var addTarget: BaseItem?

    private var client: EmbyClient? { appState.client }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            if isLoading && items.isEmpty {
                Spacer()
                ProgressView("加载中…")
                Spacer()
            } else if items.isEmpty && !isLoading {
                Spacer()
                EmptyStateView(systemImage: "square.grid.2x2",
                               title: "这个库里还没有内容",
                               subtitle: "下拉刷新试试")
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
        .appBackground()
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
        .task { if items.isEmpty { await load() } }
        .refreshable { await load() }
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
        guard let client else { return }
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
