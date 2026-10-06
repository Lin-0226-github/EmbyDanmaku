//
//  AddToPlaylistSheet.swift
//  EmbyDanmaku
//
//  把当前条目（或整季剧集）加入 / 移出播放清单。
//

import SwiftUI

struct AddToPlaylistSheet: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var store = PlaylistStore.shared
    @Environment(\.dismiss) private var dismiss

    /// 主条目
    let item: BaseItem
    /// 可选：剧集列表，用于「整季加入」
    var episodes: [BaseItem] = []

    @State private var showNewPlaylist = false
    @State private var newName = ""
    @State private var toast: String?

    private var serverId: String {
        appState.currentServer?.id ?? ""
    }

    private var entry: PlaylistEntry {
        PlaylistEntry.make(from: item, serverId: serverId)
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        headerCard

                        SectionHeader(title: "选择清单", systemImage: "list.bullet")

                        VStack(spacing: 10) {
                            ForEach(store.playlists) { p in
                                Button {
                                    toggle(p)
                                } label: {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 11, style: .continuous)
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
                                        Image(systemName: isMember(p) ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 21))
                                            .foregroundStyle(isMember(p) ? AppTheme.accent : AppTheme.textTertiary)
                                    }
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppTheme.card))
                                }
                                .buttonStyle(.plain)
                            }

                            Button { showNewPlaylist = true } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 19))
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
                        .padding(.horizontal, 16)

                        Color.clear.frame(height: 20)
                    }
                    .padding(.top, 10)
                }
            }
            .navigationTitle("加入清单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("新建清单", isPresented: $showNewPlaylist) {
                TextField("清单名称", text: $newName)
                Button("取消", role: .cancel) { newName = "" }
                Button("创建并加入") {
                    let p = store.create(name: newName)
                    add(to: p.id)
                    newName = ""
                }
            }
            .overlay(alignment: .bottom) {
                if let t = toast {
                    Text(t)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(AppTheme.elevated))
                        .padding(.bottom, 30)
                        .transition(.opacity)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - UI

    private var headerCard: some View {
        HStack(spacing: 12) {
            RemoteImageView(url: posterURL, placeholderSystemImage: item.isEpisode ? "tv" : "film")
                .frame(width: 56, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.Name ?? "")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                if let s = item.subtitleText {
                    Text(s).font(.system(size: 13)).foregroundStyle(AppTheme.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppTheme.card))
        .padding(.horizontal, 16)
    }

    private var posterURL: URL? {
        guard let c = appState.client else { return nil }
        return c.imageURL(itemId: item.id, tag: item.primaryImageTag, maxWidth: 300)
    }

    // MARK: - 操作

    /// 剧集模式下按「整季是否都在」判断归属
    private func isMember(_ p: UserPlaylist) -> Bool {
        if !episodes.isEmpty {
            let ids = Set(p.items.map { $0.itemId })
            return episodes.allSatisfy { ids.contains($0.id) }
        }
        return store.contains(item.id, inPlaylist: p.id)
    }

    private func toggle(_ p: UserPlaylist) {
        if isMember(p) {
            if episodes.isEmpty {
                store.remove(itemId: item.id, from: p.id)
            } else {
                for e in episodes { store.remove(itemId: e.id, from: p.id) }
            }
            showToast("已从「\(p.name)」移出")
        } else {
            add(to: p.id)
            showToast("已加入「\(p.name)」")
        }
    }

    private func add(to id: String) {
        if !episodes.isEmpty {
            let entries = episodes.map { PlaylistEntry.make(from: $0, serverId: serverId) }
            store.add(entries, to: id)
        } else {
            store.add(entry, to: id)
        }
    }

    private func showToast(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            toast = nil
        }
    }
}
