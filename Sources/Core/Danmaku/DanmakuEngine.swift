//
//  DanmakuEngine.swift
//  EmbyDanmaku
//
//  弹幕时间轴与轨道调度引擎。
//  引擎只负责计算「屏幕上此刻应该有哪些弹幕、各自在什么位置」，
//  具体绘制交给 DanmakuCanvasView。
//

import Foundation
import UIKit
import Combine

/// 弹幕渲染配置
struct DanmakuConfiguration {
    var enabled: Bool = true
    var opacity: Double = 0.85
    var scale: Double = 1.0
    var speed: Double = 1.0
    var area: Double = 0.5
    var limit: Int = 220
    var strokeWidth: Double = 1.0
    var showTop: Bool = true
    var showBottom: Bool = true
    var showScroll: Bool = true
    var blockedWords: [String] = []

    /// 基准字号：约屏幕高度的 4.5%，再乘以倍率
    func baseFontSize(canvasHeight: CGFloat) -> CGFloat {
        max(12, min(34, canvasHeight * 0.045)) * CGFloat(scale)
    }

    /// 滚动弹幕穿过一屏所需时间（1x 速度约 8 秒）
    var baseDuration: Double {
        8.0 / max(0.2, speed)
    }

    /// 固定弹幕（顶部 / 底部）停留时间
    var fixedDuration: Double {
        4.0
    }
}

/// - Important: 该类的所有方法必须在主线程调用（由 CADisplayLink 每帧驱动）。
final class DanmakuEngine: ObservableObject {

    // MARK: - 状态

    private(set) var items: [DanmakuItem] = []
    private var nextIndex: Int = 0
    /// 当前正在屏幕上飞行的弹幕
    private(set) var sprites: [DanmakuSprite] = []

    var configuration = DanmakuConfiguration()
    var canvasSize: CGSize = .zero {
        didSet { if oldValue != canvasSize { rebuildTracks() } }
    }

    /// 每行轨道的「最早可再次使用的时间」
    private var occupiedUntil: [Double] = []
    private var trackCount: Int = 0
    /// 单条弹幕的行高（渲染层布局用）
    private(set) var rowHeight: CGFloat = 24

    /// 总弹幕数（供 UI 展示）
    var totalCount: Int { items.count }

    // MARK: - 装载数据

    func setItems(_ newItems: [DanmakuItem]) {
        items = newItems.sorted { $0.time < $1.time }
        nextIndex = 0
        sprites.removeAll()
        rebuildTracks()
        resetTracks()
    }

    func appendItems(_ extra: [DanmakuItem]) {
        let merged = items + extra
        setItems(merged)
    }

    /// 插入一条本地发出的弹幕（立即显示）
    func insertLocal(_ item: DanmakuItem, currentTime: Double) {
        var arr = items
        let insertAt = arr.firstIndex { $0.time > item.time } ?? arr.count
        arr.insert(item, at: insertAt)
        items = arr
        // nextIndex 可能因此后移，重新定位
        nextIndex = items.firstIndex { $0.time > currentTime } ?? items.count
        emit(item, at: currentTime)
    }

    func clear() {
        items.removeAll()
        sprites.removeAll()
        nextIndex = 0
        resetTracks()
    }

    // MARK: - 时间轴

    /// 跳转到指定时间：丢弃所有在飞的弹幕，重新定位发射游标
    func seek(to time: Double) {
        sprites.removeAll()
        resetTracks()
        nextIndex = items.firstIndex { $0.time >= time } ?? items.count
    }

    /// 时间更新（由 CADisplayLink 每帧调用）
    /// - Parameter time: 当前视频播放时间（秒）
    func tick(currentTime: Double) {
        guard configuration.enabled, canvasSize.width > 0, canvasSize.height > 0 else {
            if !sprites.isEmpty { sprites.removeAll() }
            return
        }

        // 1. 回收已播完的弹幕
        if !sprites.isEmpty {
            sprites.removeAll { currentTime > $0.endTime + 0.05 }
        }

        // 2. 发射新弹幕。若一次跳跃太多（快进/拖进度条），只发射落在窗口内的，
        //    避免瞬间涌入成百上千条。
        let windowStart = currentTime - 0.8
        while nextIndex < items.count {
            let item = items[nextIndex]
            if item.time > currentTime { break }
            if item.time >= windowStart {
                emit(item, at: currentTime)
            }
            nextIndex += 1
        }

        // 3. 播放位置回退（例如循环播放）时重置游标
        if nextIndex > 0, let first = items.first, currentTime < first.time - 1 {
            seek(to: currentTime)
        }
    }

    // MARK: - 轨道管理

    private func rebuildTracks() {
        guard canvasSize.height > 0 else { return }
        let base = configuration.baseFontSize(canvasHeight: canvasSize.height)
        rowHeight = base * 1.35
        let usable = canvasSize.height * CGFloat(configuration.area)
        trackCount = max(1, Int(usable / rowHeight))
        occupiedUntil = Array(repeating: -1, count: trackCount)
    }

    private func resetTracks() {
        occupiedUntil = Array(repeating: -1, count: max(1, trackCount))
    }

    private func isBlocked(_ text: String) -> Bool {
        guard !configuration.blockedWords.isEmpty else { return false }
        for w in configuration.blockedWords where text.localizedCaseInsensitiveContains(w) {
            return true
        }
        return false
    }

    private func emit(_ item: DanmakuItem, at currentTime: Double) {
        guard configuration.enabled else { return }
        guard !isBlocked(item.text) else { return }
        switch item.mode {
        case .top where !configuration.showTop: return
        case .bottom where !configuration.showBottom: return
        default:
            if item.mode.isScroll && !configuration.showScroll { return }
        }
        guard sprites.count < configuration.limit else { return }
        guard trackCount > 0 else { return }

        let fontSize = configuration.baseFontSize(canvasHeight: canvasSize.height) * item.fontSizeRatio
        let font = UIFont.boldSystemFont(ofSize: fontSize)
        let text = item.text as NSString
        let width = ceil(text.boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: rowHeight),
                                           options: [.usesLineFragmentOrigin],
                                           attributes: [.font: font],
                                           context: nil).width) + 12

        // 选择轨道：底部弹幕自下而上，其余自上而下
        var track: Int? = nil
        if item.mode.isFixedBottom {
            var i = trackCount - 1
            while i >= 0 {
                if occupiedUntil[i] <= item.time { track = i; break }
                i -= 1
            }
        } else {
            for i in 0..<trackCount where occupiedUntil[i] <= item.time {
                track = i
                break
            }
        }
        guard let t = track else { return } // 没有空轨道，丢弃

        let duration: Double
        if item.mode.isScroll {
            let speed = canvasSize.width / configuration.baseDuration
            duration = (canvasSize.width + width) / max(1, speed)
            // 该轨道下一次可用的时间：本条弹幕尾部完全进入屏幕 + 0.15s 间隙
            occupiedUntil[t] = item.time + Double(width) / max(1, speed) + 0.15
        } else {
            duration = configuration.fixedDuration
            occupiedUntil[t] = item.time + duration + 0.1
        }

        // 已经飞过头的（例如 seek 回退）不再显示
        guard item.time + duration > currentTime else { return }

        let y: CGFloat
        if item.mode.isFixedBottom {
            let usableTop = canvasSize.height * CGFloat(configuration.area)
            y = usableTop - CGFloat(trackCount - t) * rowHeight
        } else {
            y = CGFloat(t) * rowHeight
        }

        let sprite = DanmakuSprite(id: item.id,
                                   item: item,
                                   track: t,
                                   startTime: item.time,
                                   duration: duration,
                                   width: width,
                                   y: y,
                                   font: font,
                                   reversed: item.mode == .reverse)
        sprites.append(sprite)
    }

    /// 计算某条弹幕在当前时间的左边缘 X 坐标
    func xPosition(for sprite: DanmakuSprite, at time: Double) -> CGFloat {
        let p = sprite.progress(at: time)
        if sprite.item.mode.isScroll {
            let total = canvasSize.width + sprite.width
            if sprite.reversed {
                return -sprite.width + CGFloat(p) * total
            }
            return canvasSize.width - CGFloat(p) * total
        }
        // 固定弹幕居中
        return (canvasSize.width - sprite.width) / 2
    }
}
