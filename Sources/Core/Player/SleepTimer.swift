//
//  SleepTimer.swift
//  EmbyDanmaku
//
//  定时关闭：按固定时长倒计时，或播完当前这一集后停止。
//

import Foundation
import SwiftUI

/// - Important: 状态更新均发生在主线程（Timer 在主 RunLoop），UI 可直接绑定。
final class SleepTimer: ObservableObject {

    enum Mode: Equatable, Hashable {
        case off
        case countdown(TimeInterval)
        case endOfEpisode

        var label: String {
            switch self {
            case .off: return "关闭"
            case .countdown(let t): return String(format: "%.0f 分钟", t / 60)
            case .endOfEpisode: return "本集播完"
            }
        }
    }

    /// 预设档位（分钟）
    static let presets: [Int] = [10, 15, 30, 45, 60, 90, 120]

    @Published private(set) var mode: Mode = .off
    @Published private(set) var remaining: TimeInterval = 0
    /// 触发后回调（由播放器注入：暂停 + 提示），始终在主线程调用
    var onFire: (@MainActor () -> Void)?

    private var timer: Timer?
    private var deadline: Date?

    var isActive: Bool { mode != .off }

    var remainingText: String {
        guard remaining > 0 else { return "" }
        let total = Int(ceil(remaining))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    deinit {
        // deinit 中不能触碰 MainActor 隔离的属性，直接置空即可
        timer?.invalidate()
    }

    // MARK: - 控制

    func start(minutes: Int) {
        start(seconds: TimeInterval(minutes * 60))
    }

    func start(seconds: TimeInterval) {
        cancel()
        guard seconds > 0 else { return }
        mode = .countdown(seconds)
        remaining = seconds
        deadline = Date().addingTimeInterval(seconds)

        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        t.tolerance = 0.4
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func startEndOfEpisode() {
        cancel()
        mode = .endOfEpisode
        remaining = 0
    }

    /// 播放结束时由播放器调用（endOfEpisode 模式才会真正触发）
    @MainActor
    func playbackDidEnd() {
        guard mode == .endOfEpisode else { return }
        fire()
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        deadline = nil
        mode = .off
        remaining = 0
    }

    private func tick() {
        guard let deadline else { return }
        let left = deadline.timeIntervalSinceNow
        if left <= 0 {
            remaining = 0
            fire()
        } else {
            remaining = left
        }
    }

    private func fire() {
        timer?.invalidate()
        timer = nil
        deadline = nil
        let firedMode = mode
        mode = .off
        remaining = 0
        let callback = onFire
        let desc = (firedMode == .endOfEpisode) ? "本集播放结束，已暂停播放" : "定时关闭时间已到，已暂停播放"
        Task { @MainActor in
            self.lastFiredDescription = desc
            self.showFiredAlert = true
            callback?()
        }
    }

    /// 触发后的提示状态
    @Published var showFiredAlert: Bool = false
    @Published var lastFiredDescription: String = ""
}
