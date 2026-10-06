//
//  AppSettings.swift
//  EmbyDanmaku
//
//  全局用户设置，持久化到 UserDefaults。
//

import Foundation
import Combine

final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    private let ud = UserDefaults.standard

    // MARK: - 弹幕通用

    @Published var danmakuEnabled: Bool {
        didSet { ud.set(danmakuEnabled, forKey: Keys.danmakuEnabled) }
    }
    /// 弹幕透明度 0.1 ~ 1.0
    @Published var danmakuOpacity: Double {
        didSet { ud.set(danmakuOpacity, forKey: Keys.danmakuOpacity) }
    }
    /// 弹幕字号倍率 0.6 ~ 2.0
    @Published var danmakuScale: Double {
        didSet { ud.set(danmakuScale, forKey: Keys.danmakuScale) }
    }
    /// 滚动速度倍率 0.5 ~ 2.0，越大越快
    @Published var danmakuSpeed: Double {
        didSet { ud.set(danmakuSpeed, forKey: Keys.danmakuSpeed) }
    }
    /// 纵向显示区域占比 0.25 / 0.5 / 0.75 / 1.0
    @Published var danmakuArea: Double {
        didSet { ud.set(danmakuArea, forKey: Keys.danmakuArea) }
    }
    /// 同屏最大弹幕数（超出则丢弃，保护性能）
    @Published var danmakuLimit: Int {
        didSet { ud.set(danmakuLimit, forKey: Keys.danmakuLimit) }
    }
    /// 弹幕描边粗细
    @Published var danmakuStroke: Double {
        didSet { ud.set(danmakuStroke, forKey: Keys.danmakuStroke) }
    }
    /// 是否显示顶部弹幕
    @Published var showTopDanmaku: Bool {
        didSet { ud.set(showTopDanmaku, forKey: Keys.showTop) }
    }
    /// 是否显示底部弹幕
    @Published var showBottomDanmaku: Bool {
        didSet { ud.set(showBottomDanmaku, forKey: Keys.showBottom) }
    }
    /// 是否显示滚动弹幕
    @Published var showScrollDanmaku: Bool {
        didSet { ud.set(showScrollDanmaku, forKey: Keys.showScroll) }
    }
    /// 屏蔽关键词（逗号分隔）
    @Published var blockedWords: String {
        didSet { ud.set(blockedWords, forKey: Keys.blockedWords) }
    }

    var blockedWordList: [String] {
        blockedWords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    // MARK: - 弹幕源

    /// 弹幕 API 根地址（兼容弹弹play v2 规范，可换成自建服务器）
    @Published var danmakuAPIBase: String {
        didSet { ud.set(danmakuAPIBase, forKey: Keys.apiBase) }
    }
    @Published var dandanAppId: String {
        didSet { ud.set(dandanAppId, forKey: Keys.appId) }
    }
    @Published var dandanAppSecret: String {
        didSet { ud.set(dandanAppSecret, forKey: Keys.appSecret) }
    }
    /// 是否优先用文件名搜索匹配（否则只用文件名 hash 匹配，网络流无法计算 hash）
    @Published var danmakuAutoMatch: Bool {
        didSet { ud.set(danmakuAutoMatch, forKey: Keys.autoMatch) }
    }

    var danmakuSourceConfigured: Bool {
        !dandanAppId.isEmpty || !danmakuAPIBase.isEmpty
    }

    // MARK: - 播放

    /// 转码码率上限（bps）
    @Published var maxBitrate: Int {
        didSet { ud.set(maxBitrate, forKey: Keys.maxBitrate) }
    }
    /// 是否优先直连（关闭则总是走服务器转码）
    @Published var preferDirectPlay: Bool {
        didSet { ud.set(preferDirectPlay, forKey: Keys.preferDirect) }
    }
    /// 启动时是否从上次进度续播
    @Published var autoResume: Bool {
        didSet { ud.set(autoResume, forKey: Keys.autoResume) }
    }
    /// 手势：亮度 / 音量 / 快进
    @Published var gesturesEnabled: Bool {
        didSet { ud.set(gesturesEnabled, forKey: Keys.gestures) }
    }
    /// 锁屏后是否继续播放声音
    @Published var backgroundPlayback: Bool {
        didSet { ud.set(backgroundPlayback, forKey: Keys.background) }
    }
    /// 字幕字号（播放器内自渲染字幕）
    @Published var subtitleSize: Double {
        didSet { ud.set(subtitleSize, forKey: Keys.subtitleSize) }
    }
    /// 默认定时关闭时长（分钟，0 表示关闭）
    @Published var defaultSleepMinutes: Int {
        didSet { ud.set(defaultSleepMinutes, forKey: Keys.sleepMinutes) }
    }

    // MARK: - 初始化

    private init() {
        let d = UserDefaults.standard
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            d.object(forKey: key) == nil ? fallback : d.bool(forKey: key)
        }
        func dbl(_ key: String, _ fallback: Double) -> Double {
            d.object(forKey: key) == nil ? fallback : d.double(forKey: key)
        }
        func int(_ key: String, _ fallback: Int) -> Int {
            d.object(forKey: key) == nil ? fallback : d.integer(forKey: key)
        }

        danmakuEnabled = bool(Keys.danmakuEnabled, true)
        danmakuOpacity = dbl(Keys.danmakuOpacity, 0.85)
        danmakuScale = dbl(Keys.danmakuScale, 1.0)
        danmakuSpeed = dbl(Keys.danmakuSpeed, 1.0)
        danmakuArea = dbl(Keys.danmakuArea, 0.5)
        danmakuLimit = int(Keys.danmakuLimit, 220)
        danmakuStroke = dbl(Keys.danmakuStroke, 1.0)
        showTopDanmaku = bool(Keys.showTop, true)
        showBottomDanmaku = bool(Keys.showBottom, true)
        showScrollDanmaku = bool(Keys.showScroll, true)
        blockedWords = d.string(forKey: Keys.blockedWords) ?? ""

        danmakuAPIBase = d.string(forKey: Keys.apiBase) ?? "https://api.dandanplay.net"
        dandanAppId = d.string(forKey: Keys.appId) ?? ""
        dandanAppSecret = d.string(forKey: Keys.appSecret) ?? ""
        danmakuAutoMatch = bool(Keys.autoMatch, true)

        maxBitrate = int(Keys.maxBitrate, 60_000_000)
        preferDirectPlay = bool(Keys.preferDirect, true)
        autoResume = bool(Keys.autoResume, true)
        gesturesEnabled = bool(Keys.gestures, true)
        backgroundPlayback = bool(Keys.background, true)
        subtitleSize = dbl(Keys.subtitleSize, 20)
        defaultSleepMinutes = int(Keys.sleepMinutes, 0)
    }

    private enum Keys {
        static let danmakuEnabled = "dm.enabled"
        static let danmakuOpacity = "dm.opacity"
        static let danmakuScale = "dm.scale"
        static let danmakuSpeed = "dm.speed"
        static let danmakuArea = "dm.area"
        static let danmakuLimit = "dm.limit"
        static let danmakuStroke = "dm.stroke"
        static let showTop = "dm.showTop"
        static let showBottom = "dm.showBottom"
        static let showScroll = "dm.showScroll"
        static let blockedWords = "dm.blocked"
        static let apiBase = "dm.apiBase"
        static let appId = "dm.appId"
        static let appSecret = "dm.appSecret"
        static let autoMatch = "dm.autoMatch"
        static let maxBitrate = "pl.maxBitrate"
        static let preferDirect = "pl.preferDirect"
        static let autoResume = "pl.autoResume"
        static let gestures = "pl.gestures"
        static let background = "pl.background"
        static let subtitleSize = "pl.subtitleSize"
        static let sleepMinutes = "pl.sleepMinutes"
    }
}
