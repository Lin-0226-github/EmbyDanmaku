//
//  SearchView.swift
//  EmbyDanmaku
//
//  搜索媒体库。
//

import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var appState: AppState

    @State private var keyword = ""
    @State private var results: [BaseItem] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var hasSearched = false
    @State private var searchTask: Task<Void, Never>?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        NavigationView {
            Group {
                if isSearching {
                    ProgressView("搜索中…")
                } else if results.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text(hasSearched ? "没有找到结果" : "搜索媒体库")
                            .font(.headline)
                        Text(hasSearched ? "换个关键词试试" : "输入电影或剧集名称")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(results) { item in
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
            .navigationTitle("搜索")
            .searchable(text: $keyword,
                        prompt: "电影 / 剧集")
            .onSubmit(of: .search) { performSearch() }
            .onChange(of: keyword) { _ in
                // 输入防抖
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { performSearch() }
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

    private func performSearch() {
        let q = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 1, let client = appState.client else {
            results = []
            hasSearched = false
            return
        }
        isSearching = true
        hasSearched = true
        Task {
            defer { isSearching = false }
            do {
                results = try await client.search(term: q)
            } catch {
                if error.isCancellation { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}
