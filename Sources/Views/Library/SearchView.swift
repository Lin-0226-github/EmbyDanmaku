//
//  SearchView.swift
//  EmbyDanmaku
//
//  搜索：一次并行搜索所有已添加（已登录）服务器的媒体内容，结果按服务器分组展示。
//

import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var store = PlaylistStore.shared

    struct ServerGroup: Identifiable {
        let id: String
        let server: EmbyServer
        let client: EmbyClient
        let items: [BaseItem]
    }

    @State private var keyword = ""
    @State private var groups: [ServerGroup] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var hasSearched = false
    @State private var searchTask: Task<Void, Never>?
    @State private var addTarget: BaseItem?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 14)]

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                Group {
                    if isSearching {
                        ProgressView("搜索中…")
                    } else if groups.isEmpty {
                        EmptyStateView(systemImage: "magnifyingglass",
                                       title: hasSearched ? "所有服务器都没有找到" : "搜索媒体库",
                                       subtitle: hasSearched ? "换个关键词试试" : "同时搜索所有已登录服务器，输入电影或剧集名称")
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                ForEach(groups) { g in
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack(spacing: 7) {
                                            Image(systemName: "server.rack")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(AppTheme.accent)
                                            Text(g.server.name)
                                                .font(.system(size: 15, weight: .bold))
                                                .foregroundStyle(AppTheme.textPrimary)
                                            Text("\(g.items.count) 个结果")
                                                .font(.system(size: 11))
                                                .foregroundStyle(AppTheme.textTertiary)
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.horizontal, 16)

                                        LazyVGrid(columns: columns, spacing: 18) {
                                            ForEach(g.items) { item in
                                                NavigationLink {
                                                    ItemDetailView(item: item,
                                                                   clientOverride: g.client,
                                                                   serverNameOverride: g.server.name)
                                                } label: {
                                                    PosterCard(item: item, client: g.client)
                                                }
                                                .buttonStyle(.plain)
                                                .contextMenu {
                                                    Button {
                                                        let serverId = g.server.id
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
                                Color.clear.frame(height: 12)
                            }
                            .padding(.top, 8)
                        }
                    }
                }
            }
            .navigationTitle("搜索")
            .searchable(text: $keyword, prompt: "电影 / 剧集（搜索所有服务器）")
            .onSubmit(of: .search) { performSearch() }
            .onChange(of: keyword) { _ in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { performSearch() }
                }
            }
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

    private func performSearch() {
        let q = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 1 else {
            groups = []
            hasSearched = false
            return
        }

        // 当前服务器排最前，其余按列表顺序；只搜已登录（有凭据）的
        var targets: [(EmbyServer, EmbyClient)] = []
        if let cur = appState.currentServer, let c = appState.client {
            targets.append((cur, c))
        }
        for s in appState.servers where s.id != appState.currentServer?.id {
            if let c = appState.client(for: s) { targets.append((s, c)) }
        }

        guard !targets.isEmpty else {
            groups = []
            hasSearched = false
            errorMessage = "当前没有可搜索的服务器"
            return
        }

        isSearching = true
        hasSearched = true
        Task {
            defer { isSearching = false }
            let result = await withTaskGroup(of: ServerGroup?.self) { group -> [ServerGroup] in
                for (server, client) in targets {
                    group.addTask {
                        let items = (try? await client.search(term: q, limit: 30)) ?? []
                        guard !items.isEmpty else { return nil }
                        return ServerGroup(id: server.id, server: server, client: client, items: items)
                    }
                }
                var out: [ServerGroup] = []
                for await g in group { if let g { out.append(g) } }
                return out
            }
            groups = result
        }
    }
}
