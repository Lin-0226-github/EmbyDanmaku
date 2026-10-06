//
//  PlayerViewModel.swift
//  EmbyDanmaku
//
//  播放器核心：AVPlayer 控制、音轨/字幕切换、进度上报、选集、定时关闭联动。
//

import Foundation
import AVFoundation
import AVKit
import UIKit
import MediaPlayer
import Combine

/// 一个可选择的轨道（音轨或字幕）
struct TrackChoice: Identifiable {
    let id: String
    let title: String
    /// AVPlayer 原生媒体选择项（转码音视频轨 / 内嵌字幕）
    let nativeOption: AVMediaSelectionOption?
    /// 外挂字幕轨序号（客户端自渲染）
    let externalIndex: Int?

    var isNone: Bool { id == "none" }

    static let none = TrackChoice(id: "none", title: "关闭", nativeOption: nil, externalIndex: nil)
}

@MainActor
final class PlayerViewModel: ObservableObject {

    // MARK: - 输入

    let client: EmbyClient
    /// 当前正在播放的条目
    @Published private(set) var item: BaseItem
    /// 同季/同系列的剧集列表，用于选集与自动连播
    @Published private(set) var playlist: [BaseItem]

    // MARK: - 播放状态

    let player = AVPlayer()
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isBuffering: Bool = true
    @Published private(set) var isReady: Bool = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var loadedDuration: Double = 0
    @Published private(set) var playbackRate: Float = 1.0
    @Published var errorMessage: String?
    @Published private(set) var plan: PlaybackPlan?
    @Published var videoGravity: AVLayerVideoGravity = .resizeAspect
    /// 定时关闭触发后的提示文案（非空即弹提示）
    @Published var sleepFiredMessage: String?

    // MARK: - 轨道

    @Published private(set) var audioChoices: [TrackChoice] = []
    @Published private(set) var subtitleChoices: [TrackChoice] = []
    @Published var selectedAudioID: String? {
        didSet { applyAudioSelection() }
    }
    @Published var selectedSubtitleID: String? {
        didSet { applySubtitleSelection() }
    }
    /// 客户端自渲染字幕的当前文本
    @Published private(set) var currentSubtitleText: String?
    @Published var subtitleFontSize: CGFloat = 20

    // MARK: - 连播 / 进度

    @Published var autoPlayNext: Bool = true
    private(set) var startPositionTicks: Int64 = 0

    // MARK: - 弹幕与定时

    let danmakuManager: DanmakuManager
    let sleepTimer = SleepTimer()

    /// 弹幕引擎由管理器持有，避免重复实例
    var engine: DanmakuEngine { danmakuManager.engine }

    // MARK: - 内部

    private var timeObserverToken: Any?
    private var periodicTask: Task<Void, Never>?
    private var reporter: PlaybackReporter?
    private var lastReportTime: Date = Date()
    private var externalCues: [SubtitleCue] = []
    private var currentExternalIndex: Int?
    private var subtitleLoadTask: Task<Void, Never>?
    private var endObserver: NSObjectProtocol?
    private var rateObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?
    private var bufferObservation: NSKeyValueObservation?
    private var cancellables = Set<AnyCancellable>()
    private var hasReportedStart = false
    /// 定时关闭倒计时剩余文本 / 是否激活（镜像 SleepTimer，便于 SwiftUI 观察）
    @Published private(set) var sleepRemainingText: String?
    @Published private(set) var sleepActive: Bool = false

    // MARK: - 初始化

    init(client: EmbyClient, item: BaseItem, playlist: [BaseItem] = [], startSeconds: Double? = nil) {
        self.client = client
        self.item = item
        self.playlist = playlist.isEmpty ? [item] : playlist
        self.danmakuManager = DanmakuManager(settings: .shared)
        self.subtitleFontSize = CGFloat(AppSettings.shared.subtitleSize)

        configureAudioSession()
        setupRemoteCommands()
        bindSleepTimer()
        bindDanmaku()

        Task {
            if let startSeconds, startSeconds > 1 {
                self.pendingStartSeconds = startSeconds
            } else {
                self.pendingStartSeconds = nil
            }
            await load()
        }
    }

    deinit {
        // deinit 处于非隔离上下文，不能访问 MainActor 隔离成员。
        // 播放资源统一在 onDisappear() 中释放；这里不做额外操作。
    }

    private var pendingStartSeconds: Double?

    // MARK: - 加载

    func load() async {
        isBuffering = true
        errorMessage = nil
        isReady = false

        do {
            let info = try await client.fetchPlaybackInfo(itemId: item.id, maxBitrate: AppSettings.shared.maxBitrate)
            guard let plan = PlaybackDecision.plan(client: client,
                                                   itemId: item.id,
                                                   info: info,
                                                   preferDirect: AppSettings.shared.preferDirectPlay) else {
                throw EmbyError.playbackUnavailable
            }
            self.plan = plan

            var options: [String: Any] = [:]
            if !plan.httpHeaders.isEmpty {
                options["AVURLAssetHTTPHeaderFieldsKey"] = plan.httpHeaders
            }
            let asset = AVURLAsset(url: plan.url, options: options)
            let playerItem = AVPlayerItem(asset: asset)
            installObservers(for: playerItem)
            player.replaceCurrentItem(with: playerItem)

            // 等待时长可读取，同时枚举轨道
            async let durationLoad: Void = loadDuration(asset)
            async let tracksLoad: Void = loadTracks(asset)
            _ = try await (durationLoad, tracksLoad)

            // 字幕轨（客户端自渲染）
            buildSubtitleChoices()

            // 进度上报器
            let r = PlaybackReporter(client: client)
            self.reporter = r
            self.hasReportedStart = false

            isReady = true
            isBuffering = false

            // 续播
            var startSec = pendingStartSeconds ?? 0
            if startSec <= 1, AppSettings.shared.autoResume {
                startSec = LocalStore.shared.record(for: item.id)?.resumeSeconds ?? item.resumeSeconds
                // 距离结尾 15 秒以内视为已看完
                if duration > 0, startSec > duration - 15 { startSec = 0 }
            }
            pendingStartSeconds = nil
            if startSec > 1 {
                await seek(to: startSec, report: false)
            }

            // 弹幕
            danmakuManager.prepare(for: item, fileName: plan.fileName ?? item.Name)

            play()
            reportStartIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
            isBuffering = false
        }
    }

    private func loadDuration(_ asset: AVAsset) async throws {
        try await asset.loadValuesAsync(forKeys: ["duration"])
        let d = asset.duration
        if d.isNumeric, d.seconds.isFinite {
            duration = max(0, d.seconds)
        } else if let ticks = plan?.durationTicks, ticks > 0 {
            duration = Double(ticks) / 10_000_000.0
        } else {
            duration = item.durationSeconds
        }
    }

    private func loadTracks(_ asset: AVAsset) async throws {
        try await asset.loadValuesAsync(forKeys: ["availableMediaCharacteristicsWithMediaSelectionOptions"])
        let chars = asset.availableMediaCharacteristicsWithMediaSelectionOptions
        var audios: [TrackChoice] = []
        var subs: [TrackChoice] = [.none]

        for ch in chars where ch == .audible || ch == .legible {
            guard let group = asset.mediaSelectionGroup(forMediaCharacteristic: ch) else { continue }
            let options = group.options
            for (idx, opt) in options.enumerated() {
                let title = opt.displayName
                let id = "\(ch == .audible ? "a" : "s")\(idx)"
                if ch == .audible {
                    audios.append(TrackChoice(id: id, title: title, nativeOption: opt, externalIndex: nil))
                } else {
                    subs.append(TrackChoice(id: id, title: title, nativeOption: opt, externalIndex: nil))
                }
            }
        }

        if audios.isEmpty, let plan {
            // 直连时若无原生音轨组（少见），退化为展示服务器返回的音轨信息
            audios = plan.audioTracks.enumerated().map { i, s in
                TrackChoice(id: "info\(i)", title: s.displayName, nativeOption: nil, externalIndex: nil)
            }
        }
        audioChoices = audios
        if selectedAudioID == nil { selectedAudioID = audios.first?.id }
        // subs 首项是「关闭」，合并到最终列表时保留
        nativeSubtitleChoices = subs
    }

    /// 媒体内嵌 / 转码 HLS 自带的字幕轨（首项为「关闭」）
    private var nativeSubtitleChoices: [TrackChoice] = [.none]

    private func buildSubtitleChoices() {
        var list = nativeSubtitleChoices
        // 外挂字幕或服务器提取出的文本字幕（客户端自渲染）
        if let plan {
            for t in plan.subtitleTracks where t.url != nil {
                let suffix = t.isExternal ? "" : " · 提取"
                list.append(TrackChoice(id: "ext\(t.index)",
                                        title: t.displayTitle + suffix,
                                        nativeOption: nil,
                                        externalIndex: t.index))
            }
        }
        subtitleChoices = list

        // 默认选中：服务器指定的默认字幕，否则第一条中文字幕
        if selectedSubtitleID == nil {
            if let def = plan?.subtitleTracks.first(where: { $0.isDefault && $0.url != nil }) {
                selectedSubtitleID = "ext\(def.index)"
            } else if let zh = plan?.subtitleTracks.first(where: { ($0.language ?? "").contains("中文") && $0.url != nil }) {
                selectedSubtitleID = "ext\(zh.index)"
            }
        }
    }

    // MARK: - 观察者

    private func installObservers(for playerItem: AVPlayerItem) {
        // 切换剧集时会重新装载，先清理上一轮的观察者，避免累积
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }

        // 播放进度
        let interval = CMTime(value: 1, timescale: 5)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            guard let strongSelf = self, let item = strongSelf.player.currentItem else { return }
            let t = item.currentTime()
            guard t.isNumeric, t.seconds.isFinite else { return }
            Task { @MainActor in
                strongSelf.currentTime = t.seconds
                strongSelf.updateExternalSubtitle(at: t.seconds)
                strongSelf.maybeReportProgress(at: t.seconds)
            }
        }

        statusObservation = playerItem.observe(\.status) { [weak self] item, _ in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    strongSelf.isBuffering = false
                case .failed:
                    strongSelf.isBuffering = false
                    strongSelf.errorMessage = item.error?.localizedDescription ?? "播放失败"
                default:
                    strongSelf.isBuffering = true
                }
            }
        }

        bufferObservation = playerItem.observe(\.loadedTimeRanges) { [weak self] item, _ in
            guard let strongSelf = self, let range = item.loadedTimeRanges.first?.timeRangeValue else { return }
            let end = range.start + range.duration
            Task { @MainActor in
                strongSelf.loadedDuration = end.seconds
            }
        }

        rateObservation = player.observe(\.rate) { [weak self] p, _ in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.isPlaying = p.rate > 0
            }
        }

        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                             object: playerItem,
                                                             queue: .main) { [weak self] _ in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.handlePlaybackEnd()
            }
        }
    }

    private func handlePlaybackEnd() {
        // 标记已看完并上报停止
        let ticks = Int64(duration * 10_000_000)
        Task {
            await reporter?.stopped(positionTicks: ticks)
            try? await client.markPlayed(item.id)
            LocalStore.shared.setResume(item.id, seconds: 0)
        }

        sleepTimer.playbackDidEnd()

        if autoPlayNext, let next = nextItem() {
            Task { await switchTo(next) }
        } else {
            isPlaying = false
        }
    }

    // MARK: - 控制

    func play() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { }
        player.play()
        player.rate = playbackRate
    }

    func pause() {
        player.pause()
        Task { await reporter?.paused(positionTicks: ticks(from: currentTime)) }
        LocalStore.shared.setResume(item.id, seconds: currentTime)
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func seek(to seconds: Double, report: Bool = true) async {
        let clamped = max(0, min(seconds, max(duration, 0)))
        let t = CMTime(seconds: clamped, preferredTimescale: 600)
        await player.seekCompat(to: t)
        currentTime = clamped
        updateExternalSubtitle(at: clamped)
        engine.seek(to: clamped)
        if report {
            Task { await reporter?.progress(positionTicks: ticks(from: clamped), isPaused: !isPlaying) }
        }
    }

    func seek(by delta: Double) {
        Task { await seek(to: currentTime + delta) }
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        guard isPlaying else { return }
        player.rate = rate
    }

    func toggleGravity() {
        videoGravity = (videoGravity == .resizeAspect) ? .resizeAspectFill : .resizeAspect
    }

    // MARK: - 轨道选择

    private func applyAudioSelection() {
        guard let id = selectedAudioID,
              let choice = audioChoices.first(where: { $0.id == id }) else { return }
        guard let asset = player.currentItem?.asset else { return }
        Task {
            try? await asset.loadValuesAsync(forKeys: ["availableMediaCharacteristicsWithMediaSelectionOptions"])
            guard let group = asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else { return }
            player.currentItem?.select(choice.nativeOption, in: group)
        }
    }

    private func applySubtitleSelection() {
        guard let id = selectedSubtitleID else { return }
        let choice = subtitleChoices.first { $0.id == id }
        currentExternalIndex = nil
        externalCues = []
        currentSubtitleText = nil

        // 选中外挂轨时，nativeOption 为 nil 即取消内嵌字幕；选中内嵌轨时正常切换
        if let asset = player.currentItem?.asset {
            let option = choice?.nativeOption
            Task {
                try? await asset.loadValuesAsync(forKeys: ["availableMediaCharacteristicsWithMediaSelectionOptions"])
                guard let group = asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return }
                player.currentItem?.select(option, in: group)
            }
        }

        if let idx = choice?.externalIndex,
           let track = plan?.subtitleTracks.first(where: { $0.index == idx }),
           let url = track.url {
            currentExternalIndex = idx
            subtitleLoadTask?.cancel()
            subtitleLoadTask = Task { [weak self] in
                guard let strongSelf = self else { return }
                let cues = await SubtitleParser.parse(url: url)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    strongSelf.externalCues = cues
                    strongSelf.updateExternalSubtitle(at: strongSelf.currentTime)
                }
            }
        }
    }

    private func updateExternalSubtitle(at time: Double) {
        guard !externalCues.isEmpty else {
            if currentSubtitleText != nil { currentSubtitleText = nil }
            return
        }
        let text = SubtitleParser.cue(at: time, in: externalCues)?.text
        if text != currentSubtitleText { currentSubtitleText = text }
    }

    // MARK: - 选集

    func nextItem() -> BaseItem? {
        guard let i = playlist.firstIndex(where: { $0.id == item.id }), i + 1 < playlist.count else { return nil }
        return playlist[i + 1]
    }

    func previousItem() -> BaseItem? {
        guard let i = playlist.firstIndex(where: { $0.id == item.id }), i > 0 else { return nil }
        return playlist[i - 1]
    }

    /// 切换到另一集（保留当前弹幕绑定策略）
    func switchTo(_ newItem: BaseItem) async {
        Task { await reporter?.stopped(positionTicks: ticks(from: currentTime)) }
        LocalStore.shared.setResume(item.id, seconds: currentTime)
        item = newItem
        isPlaying = false
        hasReportedStart = false
        engine.clear()
        externalCues = []
        currentSubtitleText = nil
        selectedSubtitleID = nil
        selectedAudioID = nil
        await load()
        setupNowPlaying()
    }

    func playNext() {
        guard let n = nextItem() else { return }
        Task { await switchTo(n) }
    }

    func playPrevious() {
        guard let p = previousItem() else { return }
        Task { await switchTo(p) }
    }

    // MARK: - 进度上报

    private func ticks(from seconds: Double) -> Int64 {
        Int64(max(0, seconds) * 10_000_000)
    }

    private func reportStartIfNeeded() {
        guard !hasReportedStart, let plan else { return }
        hasReportedStart = true
        let durTicks = plan.durationTicks > 0 ? plan.durationTicks : ticks(from: duration)
        startPositionTicks = ticks(from: currentTime)
        Task {
            await reporter?.start(itemId: item.id,
                                  mediaSourceId: plan.mediaSourceId,
                                  playSessionId: plan.playSessionId,
                                  runTimeTicks: durTicks,
                                  playMethod: plan.method,
                                  startTicks: startPositionTicks)
        }
        setupNowPlaying()
    }

    private func maybeReportProgress(at seconds: Double) {
        let now = Date()
        guard now.timeIntervalSince(lastReportTime) >= PlaybackReporter.minInterval else { return }
        lastReportTime = now
        LocalStore.shared.setResume(item.id, seconds: seconds)
        Task {
            await reporter?.progress(positionTicks: ticks(from: seconds), isPaused: !isPlaying)
            updateNowPlayingTime(seconds)
        }
    }

    // MARK: - 弹幕

    private func bindDanmaku() {
        engine.configuration.update(from: AppSettings.shared)
        // 弹幕管理器状态变化（匹配结果、条数）需要驱动 UI 刷新
        danmakuManager.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// 供弹幕画布取当前播放时间（比 0.2s 定时刷新更精确）
    func danmakuCurrentTime() -> Double {
        if let t = player.currentItem?.currentTime(), t.isNumeric, t.seconds.isFinite {
            return t.seconds
        }
        return currentTime
    }

    func refreshDanmakuSettings() {
        engine.configuration.update(from: AppSettings.shared)
        danmakuManager.refreshSettings(AppSettings.shared)
    }

    // MARK: - 定时关闭

    private func bindSleepTimer() {
        // 把 SleepTimer 的状态变化转发给本对象的 ObjectWillChange，让 UI 能观察到
        sleepTimer.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let strongSelf = self else { return }
                strongSelf.sleepActive = strongSelf.sleepTimer.isActive
                strongSelf.sleepRemainingText = strongSelf.sleepTimer.isActive ? strongSelf.sleepTimer.remainingText : nil
                strongSelf.objectWillChange.send()
            }
            .store(in: &cancellables)

        sleepTimer.onFire = { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.pause()
            let feedback = UIImpactFeedbackGenerator(style: .medium)
            feedback.impactOccurred()
            strongSelf.sleepFiredMessage = strongSelf.sleepTimer.lastFiredDescription
        }
    }

    // MARK: - 音效会话与锁屏控制

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            let category: AVAudioSession.Category = AppSettings.shared.backgroundPlayback ? .playback : .soloAmbient
            try session.setCategory(category, mode: .moviePlayback, options: [.allowAirPlay])
        } catch { }
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlay() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playNext() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playPrevious() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in await self?.seek(to: e.positionTime) }
            return .success
        }
    }

    private func setupNowPlaying() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.displayTitle,
            MPMediaItemPropertyPlaybackDuration: duration
        ]
        info[MPMediaItemPropertyAlbumTitle] = item.SeriesName ?? item.Name ?? ""
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = Double(player.rate)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        if let url = client.imageURL(itemId: item.id, imageType: "Primary", tag: item.primaryImageTag, maxWidth: 600) {
            Task {
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let image = UIImage(data: data) else { return }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                updated[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
            }
        }
    }

    private func updateNowPlayingTime(_ seconds: Double) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = seconds
        info[MPNowPlayingInfoPropertyPlaybackRate] = Double(player.rate)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - 生命周期

    func onDisappear() {
        Task { await reporter?.stopped(positionTicks: ticks(from: currentTime)) }
        LocalStore.shared.setResume(item.id, seconds: currentTime)
        player.pause()
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        NotificationCenter.default.removeObserver(self)
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}

// MARK: - iOS 15 兼容的 AVFoundation 异步封装

extension AVAsset {
    /// iOS 16 的 `load(_:)` 需要 iOS 16，这里用 `loadValuesAsynchronously` 包装出等价的 async 版本
    func loadValuesAsync(forKeys keys: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            self.loadValuesAsynchronously(forKeys: keys) {
                objc_sync_enter(self)
                defer { objc_sync_exit(self) }
                guard !resumed else { return }
                resumed = true
                for key in keys {
                    var err: NSError?
                    if self.statusOfValue(forKey: key, error: &err) == .failed {
                        continuation.resume(throwing: err ?? NSError(domain: "AVAsset", code: -1,
                                                                    userInfo: [NSLocalizedDescriptionKey: "媒体属性加载失败"]))
                        return
                    }
                }
                continuation.resume(returning: ())
            }
        }
    }
}

extension AVPlayer {
    /// iOS 15 上没有 `seek(to:toleranceBefore:toleranceAfter:)` 的 async 版本，用完成回调包装
    func seekCompat(to time: CMTime) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false
            self.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                objc_sync_enter(self)
                defer { objc_sync_exit(self) }
                guard !resumed else { return }
                resumed = true
                continuation.resume()
            }
        }
    }
}

// MARK: - 便捷格式化

extension PlayerViewModel {
    /// 00:00 / 1:02:03 形式的时间文本
    static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}
