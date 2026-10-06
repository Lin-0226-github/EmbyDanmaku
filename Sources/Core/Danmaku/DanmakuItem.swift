//
//  DanmakuItem.swift
//  EmbyDanmaku
//
//  弹幕数据模型与样式计算。
//

import Foundation
import UIKit

/// 弹幕显示模式（兼容 B 站 / 弹弹play 的类型编号）
enum DanmakuMode: Int, CaseIterable {
    case scroll = 1     // 从右向左滚动
    case bottom = 4     // 底部固定
    case top = 5        // 顶部固定
    case reverse = 6    // 从左向右滚动（少见）
    case special = 7    // 特殊/定位弹幕（按滚动处理）

    var isScroll: Bool { self == .scroll || self == .reverse || self == .special }
    var isFixedTop: Bool { self == .top }
    var isFixedBottom: Bool { self == .bottom }
}

/// 一条弹幕
struct DanmakuItem: Hashable, Identifiable {
    let id: Int64
    /// 出现时间（秒，相对视频时间轴）
    let time: Double
    let mode: DanmakuMode
    /// 原始字号（25 = 标准，18 = 小）
    let fontSize: Int
    let color: UIColor
    let text: String
    /// 弹幕发送时间戳（Unix 秒）
    let timestamp: Int
    /// 弹幕池（0 普通，1 字幕，2 特殊）
    let pool: Int
    /// 是否为本机发出的弹幕
    var isSelf: Bool

    init(id: Int64,
         time: Double,
         mode: DanmakuMode,
         fontSize: Int,
         color: UIColor,
         text: String,
         timestamp: Int = 0,
         pool: Int = 0,
         isSelf: Bool = false) {
        self.id = id
        self.time = time
        self.mode = mode
        self.fontSize = fontSize
        self.color = color
        self.text = text
        self.timestamp = timestamp
        self.pool = pool
        self.isSelf = isSelf
    }

    /// 由 RGB 十进制色值（如 16777215）构造 UIColor
    static func color(fromDecimal value: Int) -> UIColor {
        let v = UInt32(max(0, min(0xFFFFFF, value)))
        let r = CGFloat((v >> 16) & 0xFF) / 255.0
        let g = CGFloat((v >> 8) & 0xFF) / 255.0
        let b = CGFloat(v & 0xFF) / 255.0
        // 纯黑在视频上看不见，提亮为深灰
        if r < 0.02 && g < 0.02 && b < 0.02 {
            return UIColor(white: 0.35, alpha: 1)
        }
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    /// 字号倍率：25 为标准，18 为小字
    var fontSizeRatio: CGFloat {
        fontSize <= 0 ? 1 : CGFloat(fontSize) / 25.0
    }
}

// MARK: - 正在屏幕上飞行的弹幕

struct DanmakuSprite: Identifiable {
    let id: Int64
    let item: DanmakuItem
    /// 轨道序号（0 起，顶部算起）
    let track: Int
    /// 进入屏幕的时间（视频时间轴，秒）
    let startTime: Double
    /// 在屏幕上的总停留时长
    let duration: Double
    /// 弹幕实际渲染宽度
    let width: CGFloat
    /// 基线 Y 坐标
    let y: CGFloat
    /// 渲染字号
    let font: UIFont
    /// 滚动方向
    let reversed: Bool

    var endTime: Double { startTime + duration }

    /// 当前进度 0~1
    func progress(at time: Double) -> Double {
        guard duration > 0 else { return 1 }
        return max(0, min(1, (time - startTime) / duration))
    }
}
