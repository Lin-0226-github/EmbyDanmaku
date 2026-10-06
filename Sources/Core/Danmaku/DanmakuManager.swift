//
//  DanmakuManager.swift
//  EmbyDanmaku
//
//  弹幕管理器：自动匹配弹幕库、拉取弹幕、导入本地弹幕、发送弹幕，
//  并把结果喂给 DanmakuEngine。
//

import Foundation
import UIKit
import Combine

enum DanmakuStatus: Equatable {
    case idle
    case loading
    case loaded(Int)
    case noBinding
    case failed(String)
    case disabled

    var message: String {
        switch self {
        case .idle: return "弹幕未加载"
        case .loading: return "正在获取弹幕…"
        case .loaded(let n): return "弹幕 \(n) 条"
        case .noBinding: return "未匹配到弹幕，可手动搜索"
        case .failed(let m): return m
        case .disabled: return "弹幕已关闭"
        }
    }
}

@MainActor
final class DanmakuManager: ObservableObject {

    // MARK: - 对外状态

    let engine = DanmakuEngine()
    @Published private(set) var status: DanmakuStatus = .idle
    @Published var boundEpisodeId: Int64?
    @Published var boundTitle: String?
    @Published var boundEpisodeName: String?
    /// 弹幕整体时间偏移（秒）
    @Published var offset: Double = 0
    @Published var searchResults: [EpisodeSearchResult] = []
    @Published var animeResults: [AnimeSearchResult] = []
    @Published var bangumiEpisodes: [BangumiEpisode] = []

    private var currentItemId: String?
    private var rawItems: [DanmakuItem] = []
    private var api: DanmakuAPI

    init(settings: AppSettings) {
        api = DanmakuAPI(settings: settings)
    }

    func refreshSettings(_ settings: AppSettings) {
        api = DanmakuAPI(settings: settings)
        engine.configuration.update(from: settings)
    }

    // MARK: - 加载流程

    /// 为一个媒体条目准备弹幕
    /// - Parameters:
    ///   - item: Emby 条目
    ///   - fileName: 原始文件名（用于匹配，可为空则退回标题）
    func prepare(for item: BaseItem, fileName: String?) {
        currentItemId = item.id
        let rec = LocalStore.shared.record(for: item.id)
        offset = rec?.danmakuOffset ?? 0
        engine.configuration.update(from: AppSettings.shared)

        guard AppSettings.shared.danmakuEnabled else {
            status = .disabled
            engine.clear()
            return
        }

        Task {
            // 1) 已绑定过 → 直接拉取
            if let eid = rec?.danmakuEpisodeId {
                await load(episodeId: eid, itemId: item.id,
                           title: rec?.danmakuTitle, episodeName: rec?.danmakuEpisodeTitle, persist: false)
                return
            }
            // 2) 本地弹幕文件
            if let file = rec?.localDanmakuFile {
                let url = LocalStore.shared.danmakuDirectory.appendingPathComponent(file)
                importLocalFile(url, itemId: item.id)
                return
            }
            // 3) 自动匹配
            guard AppSettings.shared.danmakuAutoMatch else {
                status = .noBinding
                return
            }
            await autoMatch(item: item, fileName: fileName)
        }
    }

    private func autoMatch(item: BaseItem, fileName: String?) async {
        status = .loading
        let keyword = matchKeyword(for: item, fileName: fileName)
        guard !keyword.isEmpty else {
            status = .noBinding
            return
        }
        guard AppSettings.shared.danmakuSourceConfigured else {
            status = .failed("未配置弹幕服务，请在设置中填写")
            return
        }
        do {
            let eps = try await api.searchEpisodes(keyword: keyword)
            if let first = eps.first {
                await load(episodeId: first.episodeId, itemId: item.id,
                           title: first.animeTitle, episodeName: first.episodeTitle, persist: true)
            } else {
                // 退一步：按番剧名搜索，让用户自己选
                animeResults = try await api.searchAnime(keyword: keyword)
                status = .noBinding
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func load(episodeId: Int64, itemId: String, title: String?, episodeName: String?, persist: Bool) async {
        status = .loading
        boundEpisodeId = episodeId
        boundTitle = title
        boundEpisodeName = episodeName
        do {
            let items = try await api.comments(episodeId: episodeId)
            rawItems = items
            applyItems()
            if persist {
                LocalStore.shared.bindDanmaku(itemId, episodeId: episodeId,
                                              animeTitle: title, episodeTitle: episodeName)
            }
            status = .loaded(items.count)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// 手动搜索弹幕库
    func search(keyword: String) async {
        guard !keyword.isEmpty else { return }
        status = .loading
        do {
            async let eps = api.searchEpisodes(keyword: keyword)
            async let animes = api.searchAnime(keyword: keyword)
            let (e, a) = try await (eps, animes)
            searchResults = e
            animeResults = a
            status = e.isEmpty ? .noBinding : .idle
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// 展开某个番剧的分集
    func loadEpisodes(animeId: Int) async {
        do {
            let d = try await api.bangumi(animeId: animeId)
            bangumiEpisodes = d?.episodes ?? []
        } catch {
            bangumiEpisodes = []
        }
    }

    func choose(episodeId: Int64, title: String?, episodeName: String?) {
        guard let itemId = currentItemId else { return }
        Task { await load(episodeId: episodeId, itemId: itemId, title: title, episodeName: episodeName, persist: true) }
    }

    func clearBinding() {
        guard let itemId = currentItemId else { return }
        LocalStore.shared.clearDanmakuBinding(itemId)
        boundEpisodeId = nil
        boundTitle = nil
        boundEpisodeName = nil
        rawItems = []
        engine.clear()
        status = .noBinding
    }

    // MARK: - 本地弹幕

    func importLocalFile(_ url: URL, itemId: String) {
        let items = DanmakuParser.parse(fileURL: url)
        guard !items.isEmpty else {
            status = .failed("本地弹幕文件解析失败")
            return
        }
        rawItems = items
        boundEpisodeId = nil
        boundTitle = url.lastPathComponent
        boundEpisodeName = "本地文件"
        LocalStore.shared.setLocalDanmakuFile(itemId, fileName: url.lastPathComponent)
        applyItems()
        status = .loaded(items.count)
    }

    // MARK: - 偏移

    func setOffset(_ value: Double) {
        offset = value
        guard let itemId = currentItemId else { return }
        LocalStore.shared.setDanmakuOffset(itemId, offset: value)
        applyItems()
    }

    private func applyItems() {
        guard AppSettings.shared.danmakuEnabled else {
            engine.clear()
            status = .disabled
            return
        }
        let shifted: [DanmakuItem]
        if abs(offset) > 0.001 {
            shifted = rawItems.map { item in
                var i = item
                return DanmakuItem(id: i.id,
                                   time: max(0, i.time + offset),
                                   mode: i.mode,
                                   fontSize: i.fontSize,
                                   color: i.color,
                                   text: i.text,
                                   timestamp: i.timestamp,
                                   pool: i.pool,
                                   isSelf: i.isSelf)
            }
        } else {
            shifted = rawItems
        }
        engine.setItems(shifted)
    }

    // MARK: - 发送弹幕

    func send(text: String, at time: Double, color: UIColor = .white, mode: DanmakuMode = .scroll) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = DanmakuItem(id: Int64(Date().timeIntervalSince1970 * 1000),
                               time: time,
                               mode: mode,
                               fontSize: 25,
                               color: color,
                               text: trimmed,
                               timestamp: Int(Date().timeIntervalSince1970),
                               pool: 0,
                               isSelf: true)
        engine.insertLocal(item, currentTime: time)
        rawItems.append(item)
        rawItems.sort { $0.time < $1.time }

        if let eid = boundEpisodeId {
            Task {
                try? await api.postComment(episodeId: eid, text: trimmed, time: time, color: 0xFFFFFF, mode: mode)
            }
        }
    }

    // MARK: - 工具

    /// 生成用于弹幕匹配的关键词
    private func matchKeyword(for item: BaseItem, fileName: String?) -> String {
        let raw = fileName ?? item.Name ?? ""
        var name = (raw as NSString).deletingPathExtension
        // 去掉方括号 / 括号里的压制信息
        name = name.replacingOccurrences(of: "[\\[\\]【】()（）][^\\]\\[）)]*", with: " ", options: .regularExpression)
        // 常见标签
        let junk = ["1080p", "720p", "2160p", "4k", "x264", "x265", "h264", "h265", "hevc",
                    "web-dl", "webrip", "bluray", "bdrip", "hdr", "dv", "aac", "ac3",
                    "10bit", "8bit", "chs", "cht", "gb", "big5", "mp4", "mkv", "remux"]
        var comps = name.components(separatedBy: CharacterSet(charactersIn: "._ -"))
            .map { $0.lowercased() }
            .filter { !$0.isEmpty && !junk.contains($0) }
        // 丢掉尾部明显是集号的片段前先保留：形如 s01e05 / e05 / 第05集
        var keyword = comps.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if keyword.isEmpty {
            keyword = (item.SeriesName ?? item.Name ?? "")
        }
        return keyword
    }

    func toggleEnabled(_ enabled: Bool) {
        AppSettings.shared.danmakuEnabled = enabled
        if enabled {
            applyItems()
            status = rawItems.isEmpty ? .noBinding : .loaded(rawItems.count)
        } else {
            engine.clear()
            status = .disabled
        }
    }
}

// MARK: - 配置桥接

extension DanmakuConfiguration {
    mutating func update(from s: AppSettings) {
        enabled = s.danmakuEnabled
        opacity = s.danmakuOpacity
        scale = s.danmakuScale
        speed = s.danmakuSpeed
        area = s.danmakuArea
        limit = s.danmakuLimit
        strokeWidth = s.danmakuStroke
        showTop = s.showTopDanmaku
        showBottom = s.showBottomDanmaku
        showScroll = s.showScrollDanmaku
        blockedWords = s.blockedWordList
    }
}
