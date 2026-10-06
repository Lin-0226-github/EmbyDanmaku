//
//  PlaylistStore.swift
//  EmbyDanmaku
//
//  播放清单：本地自建清单 / 稍后再看 / 播放历史。
//  数据为纯本地（Application Support/EmbyDanmaku/playlists.json），不依赖服务器，
//  换服务器或离线时依然可用。服务器自带的播放列表走 EmbyClient 实时拉取，见 PlaylistHubView。
//

import Foundation
import SwiftUI

// MARK: - 模型

/// 清单里的一条记录。只保存展示与定位所需的最小信息，播放时再用 itemId 向服务器取完整数据。
struct PlaylistEntry: Codable, Identifiable, Hashable {
    var id: String { itemId }
    let itemId: String
    /// 归属服务器（url 小写），用于切换服务器后过滤
    let serverId: String
    var title: String
    var subtitle: String?
    var itemType: String?          // Movie / Series / Episode / Season
    var imageTag: String?
    var seriesId: String?
    var seriesName: String?
    var indexNumber: Int?
    var parentIndexNumber: Int?
    var runtimeTicks: Int64?
    var productionYear: Int?
    var addedAt: Date

    var isEpisode: Bool { itemType == "Episode" }
    var isSeries: Bool { itemType == "Series" }

    /// 展示标题：剧集显示 S01E05
    var displayTitle: String {
        if isEpisode, let s = parentIndexNumber, let e = indexNumber {
            return String(format: "S%02dE%02d %@", s, e, title)
        }
        return title
    }

    var displaySubtitle: String? {
        if isEpisode { return seriesName ?? subtitle }
        return subtitle
    }

    var durationText: String? {
        guard let t = runtimeTicks, t > 0 else { return nil }
        let m = Int(Double(t) / 10_000_000 / 60)
        return m > 0 ? "\(m) 分钟" : nil
    }
}

/// 一个用户清单
struct UserPlaylist: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var symbol: String        // SF Symbol 名
    var isBuiltIn: Bool
    var items: [PlaylistEntry]
    var createdAt: Date
    var updatedAt: Date

    var countText: String {
        items.isEmpty ? "空" : "\(items.count) 项"
    }
}

// MARK: - 从 BaseItem 生成

extension PlaylistEntry {
    static func make(from item: BaseItem, serverId: String) -> PlaylistEntry {
        PlaylistEntry(
            itemId: item.id,
            serverId: serverId,
            title: item.Name ?? "未命名",
            subtitle: item.ProductionYear.map(String.init),
            itemType: item.ItemType,
            imageTag: item.primaryImageTag,
            seriesId: item.SeriesId,
            seriesName: item.SeriesName,
            indexNumber: item.IndexNumber,
            parentIndexNumber: item.ParentIndexNumber,
            runtimeTicks: item.RunTimeTicks,
            productionYear: item.ProductionYear,
            addedAt: Date()
        )
    }

    /// 用服务器返回的最新数据刷新展示信息（不改动加入时间）
    func refreshed(with item: BaseItem) -> PlaylistEntry {
        var e = self
        e.title = item.Name ?? title
        e.subtitle = item.ProductionYear.map(String.init)
        e.itemType = item.ItemType ?? itemType
        e.imageTag = item.primaryImageTag ?? imageTag
        e.seriesId = item.SeriesId ?? seriesId
        e.seriesName = item.SeriesName ?? seriesName
        e.indexNumber = item.IndexNumber ?? indexNumber
        e.parentIndexNumber = item.ParentIndexNumber ?? parentIndexNumber
        e.runtimeTicks = item.RunTimeTicks ?? runtimeTicks
        e.productionYear = item.ProductionYear ?? productionYear
        return e
    }
}

// MARK: - 存储

final class PlaylistStore: ObservableObject {

    static let shared = PlaylistStore()

    /// 内置清单：稍后再看
    static let watchLaterId = "builtin.watchlater"

    /// 当前服务器标识。
    /// AppState 会把服务器列表存在 UserDefaults 里，这里直接从 UserDefaults 取，
    /// 这样播放器等跨层级视图不必依赖 environmentObject 也能记录清单。
    static var currentServerId: String {
        let ud = UserDefaults.standard
        guard let data = ud.data(forKey: "EmbyDanmaku.servers"),
              let list = try? JSONDecoder().decode([EmbyServer].self, from: data) else { return "" }
        if let s = list.first(where: { !($0.lastUserId ?? "").isEmpty }) { return s.id }
        return list.first?.id ?? ""
    }

    @Published private(set) var playlists: [UserPlaylist] = []
    @Published private(set) var history: [PlaylistEntry] = []

    private static let historyLimit = 200

    private let fileURL: URL
    private let queue = DispatchQueue(label: "cn.emby.danmaku.playlists", qos: .utility)

    private struct Snapshot: Codable {
        var playlists: [UserPlaylist]
        var history: [PlaylistEntry]
    }

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = dir.appendingPathComponent("EmbyDanmaku", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("playlists.json")
        load()
        ensureBuiltIns()
    }

    // MARK: 读写

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        playlists = snap.playlists
        history = snap.history
    }

    private func save() {
        let snap = Snapshot(playlists: playlists, history: history)
        let url = fileURL
        queue.async {
            guard let data = try? JSONEncoder().encode(snap) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func ensureBuiltIns() {
        if playlists.first(where: { $0.id == Self.watchLaterId }) == nil {
            let p = UserPlaylist(id: Self.watchLaterId,
                                 name: "稍后再看",
                                 symbol: "bookmark.fill",
                                 isBuiltIn: true,
                                 items: [],
                                 createdAt: Date(),
                                 updatedAt: Date())
            playlists.insert(p, at: 0)
            save()
        }
    }

    var watchLater: UserPlaylist {
        playlists.first(where: { $0.id == Self.watchLaterId })
            ?? UserPlaylist(id: Self.watchLaterId, name: "稍后再看", symbol: "bookmark.fill",
                            isBuiltIn: true, items: [], createdAt: Date(), updatedAt: Date())
    }

    /// 用户自建（不含内置）
    var customPlaylists: [UserPlaylist] {
        playlists.filter { !$0.isBuiltIn }
    }

    func playlist(id: String) -> UserPlaylist? {
        playlists.first { $0.id == id }
    }

    // MARK: 增删改

    @discardableResult
    func create(name: String, symbol: String = "list.bullet") -> UserPlaylist {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = UserPlaylist(id: UUID().uuidString,
                             name: trimmed.isEmpty ? "新清单" : trimmed,
                             symbol: symbol,
                             isBuiltIn: false,
                             items: [],
                             createdAt: Date(),
                             updatedAt: Date())
        playlists.append(p)
        save()
        return p
    }

    func rename(id: String, to name: String) {
        guard let idx = playlists.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        playlists[idx].name = trimmed
        playlists[idx].updatedAt = Date()
        save()
    }

    func setSymbol(id: String, symbol: String) {
        guard let idx = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[idx].symbol = symbol
        playlists[idx].updatedAt = Date()
        save()
    }

    func delete(id: String) {
        guard let p = playlists.first(where: { $0.id == id }), !p.isBuiltIn else { return }
        playlists.removeAll { $0.id == id }
        save()
    }

    // MARK: 条目

    func contains(_ itemId: String, inPlaylist id: String) -> Bool {
        playlist(id: id)?.items.contains { $0.itemId == itemId } ?? false
    }

    /// 加入清单（已存在则忽略）
    func add(_ entry: PlaylistEntry, to id: String) {
        guard let idx = playlists.firstIndex(where: { $0.id == id }) else { return }
        guard !playlists[idx].items.contains(where: { $0.itemId == entry.itemId }) else { return }
        playlists[idx].items.append(entry)
        playlists[idx].updatedAt = Date()
        save()
    }

    func add(_ entries: [PlaylistEntry], to id: String) {
        guard let idx = playlists.firstIndex(where: { $0.id == id }) else { return }
        let existing = Set(playlists[idx].items.map { $0.itemId })
        for e in entries where !existing.contains(e.itemId) {
            playlists[idx].items.append(e)
        }
        playlists[idx].updatedAt = Date()
        save()
    }

    func remove(itemId: String, from id: String) {
        guard let idx = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[idx].items.removeAll { $0.itemId == itemId }
        playlists[idx].updatedAt = Date()
        save()
    }

    func move(playlistId: String, from source: IndexSet, to destination: Int) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[idx].items.move(fromOffsets: source, toOffset: destination)
        playlists[idx].updatedAt = Date()
        save()
    }

    /// 清空（内置清单也允许清空）
    func clear(playlistId: String) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[idx].items = []
        playlists[idx].updatedAt = Date()
        save()
    }

    // MARK: 稍后再看

    func isInWatchLater(_ itemId: String) -> Bool {
        contains(itemId, inPlaylist: Self.watchLaterId)
    }

    func toggleWatchLater(_ entry: PlaylistEntry) {
        if isInWatchLater(entry.itemId) {
            remove(itemId: entry.itemId, from: Self.watchLaterId)
        } else {
            add(entry, to: Self.watchLaterId)
        }
    }

    // MARK: 播放历史

    func recordHistory(_ entry: PlaylistEntry) {
        history.removeAll { $0.itemId == entry.itemId }
        var e = entry
        e.addedAt = Date()
        history.insert(e, at: 0)
        if history.count > Self.historyLimit {
            history = Array(history.prefix(Self.historyLimit))
        }
        save()
    }

    func removeHistory(_ itemId: String) {
        history.removeAll { $0.itemId == itemId }
        save()
    }

    func clearHistory() {
        history = []
        save()
    }
}
