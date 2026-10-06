//
//  LocalStore.swift
//  EmbyDanmaku
//
//  本地持久化：播放进度兜底、弹幕库绑定缓存、弹幕时间偏移、最近搜索等。
//  数据以 JSON 存放在 Application Support 目录。
//

import Foundation

final class LocalStore {

    static let shared = LocalStore()

    struct Record: Codable {
        var resumeSeconds: Double = 0
        /// 已绑定的弹幕库 episodeId（弹弹play 节目编号）
        var danmakuEpisodeId: Int64?
        var danmakuTitle: String?
        var danmakuEpisodeTitle: String?
        /// 弹幕时间偏移（秒，正数表示弹幕延后）
        var danmakuOffset: Double = 0
        /// 本地弹幕文件名
        var localDanmakuFile: String?
        var updatedAt: Date = Date()
    }

    private var records: [String: Record] = [:]
    private let fileURL: URL
    private let queue = DispatchQueue(label: "cn.emby.danmaku.localstore", qos: .utility)

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = dir.appendingPathComponent("EmbyDanmaku", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("library.json")
        load()
    }

    // MARK: - 读写

    func record(for itemId: String) -> Record? { records[itemId] }

    func update(_ itemId: String, mutate: (inout Record) -> Void) {
        var r = records[itemId] ?? Record()
        mutate(&r)
        r.updatedAt = Date()
        records[itemId] = r
        saveAsync()
    }

    func setResume(_ itemId: String, seconds: Double) {
        // 距离结尾 15 秒内视为看完，清零进度
        update(itemId) { $0.resumeSeconds = seconds }
    }

    func bindDanmaku(_ itemId: String, episodeId: Int64, animeTitle: String?, episodeTitle: String?) {
        update(itemId) {
            $0.danmakuEpisodeId = episodeId
            $0.danmakuTitle = animeTitle
            $0.danmakuEpisodeTitle = episodeTitle
        }
    }

    func clearDanmakuBinding(_ itemId: String) {
        update(itemId) {
            $0.danmakuEpisodeId = nil
            $0.danmakuTitle = nil
            $0.danmakuEpisodeTitle = nil
        }
    }

    func setDanmakuOffset(_ itemId: String, offset: Double) {
        update(itemId) { $0.danmakuOffset = offset }
    }

    func setLocalDanmakuFile(_ itemId: String, fileName: String?) {
        update(itemId) { $0.localDanmakuFile = fileName }
    }

    // MARK: - 持久化

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([String: Record].self, from: data) {
            records = decoded
        }
    }

    private func saveAsync() {
        let snapshot = records
        let url = fileURL
        queue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - 本地弹幕文件目录

    var danmakuDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = dir.appendingPathComponent("EmbyDanmaku/Danmaku", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func localDanmakuFiles() -> [URL] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: danmakuDirectory, includingPropertiesForKeys: nil) else { return [] }
        return items.filter { ["xml", "json"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
