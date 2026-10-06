//
//  DanmakuCanvasView.swift
//  EmbyDanmaku
//
//  弹幕渲染层。为保证大弹幕量下的流畅度，使用 UIKit + CADisplayLink + 视图复用池，
//  而不是 SwiftUI 的声明式刷新。
//

import UIKit
import SwiftUI

// MARK: - 单条弹幕标签

private final class DanmakuLabel: UILabel {

    private var edgeLayer: CALayer?

    /// 复用前重置样式
    func configure(sprite: DanmakuSprite, config: DanmakuConfiguration) {
        alpha = CGFloat(config.opacity)
        numberOfLines = 1
        lineBreakMode = .byClipping
        textAlignment = .center
        clearsContextBeforeDrawing = true

        let stroke = CGFloat(config.strokeWidth)
        var attrs: [NSAttributedString.Key: Any] = [
            .font: sprite.font,
            .foregroundColor: sprite.item.color
        ]
        if stroke > 0 {
            attrs[.strokeColor] = UIColor.black.withAlphaComponent(0.85)
            // 负值 = 描边 + 填充同时生效
            attrs[.strokeWidth] = -stroke
        }
        attributedText = NSAttributedString(string: sprite.item.text, attributes: attrs)

        // 自己发出的弹幕加一圈高亮描边
        if sprite.item.isSelf {
            layer.borderColor = UIColor.systemYellow.cgColor
            layer.borderWidth = 1.5
            layer.cornerRadius = 3
        } else {
            layer.borderWidth = 0
            layer.cornerRadius = 0
        }
    }

    func prepareForReuse() {
        attributedText = nil
        layer.borderWidth = 0
        alpha = 1
    }
}

// MARK: - 画布

final class DanmakuCanvasUIView: UIView {

    var engine: DanmakuEngine?
    /// 由播放器提供的当前播放时间
    var timeProvider: (() -> Double)?
    /// 是否正在渲染（暂停时关闭，省电）
    var isRunning: Bool = false {
        didSet {
            if isRunning { startLink() } else { stopLink() }
        }
    }

    private var displayLink: CADisplayLink?
    private var active: [Int64: DanmakuLabel] = [:]
    private var pool: [DanmakuLabel] = []
    private var lastTime: Double = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        clipsToBounds = true
    }

    deinit {
        stopLink()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        engine?.canvasSize = bounds.size
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            stopLink()
        } else if isRunning {
            startLink()
        }
    }

    // MARK: - 驱动

    private func startLink() {
        guard displayLink == nil, window != nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.preferredFramesPerSecond = 60
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let engine else { return }
        let time = timeProvider?() ?? lastTime
        lastTime = time
        engine.tick(currentTime: time)
        sync(sprites: engine.sprites, time: time, rowHeight: engine.rowHeight)
    }

    /// 强制刷新一帧（例如刚 seek 完、暂停时也要显示当前弹幕）
    func renderOnce() {
        guard let engine else { return }
        let time = timeProvider?() ?? lastTime
        lastTime = time
        engine.tick(currentTime: time)
        sync(sprites: engine.sprites, time: time, rowHeight: engine.rowHeight)
    }

    private func sync(sprites: [DanmakuSprite], time: Double, rowHeight: CGFloat) {
        guard let engine else { return }
        var seen = Set<Int64>(minimumCapacity: sprites.count)

        for s in sprites {
            seen.insert(s.id)
            let label: DanmakuLabel
            if let existing = active[s.id] {
                label = existing
            } else {
                label = dequeue()
                label.configure(sprite: s, config: engine.configuration)
                addSubview(label)
                active[s.id] = label
            }
            let x = engine.xPosition(for: s, at: time)
            let frame = CGRect(x: x, y: s.y, width: s.width, height: rowHeight)
            if label.frame != frame { label.frame = frame }
        }

        if active.count != seen.count {
            for (id, label) in active where !seen.contains(id) {
                label.removeFromSuperview()
                label.prepareForReuse()
                if pool.count < 300 { pool.append(label) }
                active.removeValue(forKey: id)
            }
        }
    }

    private func dequeue() -> DanmakuLabel {
        if let l = pool.popLast() { return l }
        return DanmakuLabel()
    }

    /// 清空屏幕
    func flush() {
        for (_, label) in active {
            label.removeFromSuperview()
            label.prepareForReuse()
            if pool.count < 300 { pool.append(label) }
        }
        active.removeAll()
    }
}

// MARK: - SwiftUI 包装

struct DanmakuCanvasView: UIViewRepresentable {

    let engine: DanmakuEngine
    var isRunning: Bool
    var timeProvider: () -> Double

    func makeUIView(context: Context) -> DanmakuCanvasUIView {
        let v = DanmakuCanvasUIView(frame: .zero)
        v.engine = engine
        v.timeProvider = timeProvider
        return v
    }

    func updateUIView(_ uiView: DanmakuCanvasUIView, context: Context) {
        uiView.engine = engine
        uiView.timeProvider = timeProvider
        uiView.isRunning = isRunning
        if !engine.configuration.enabled {
            uiView.flush()
        }
    }

    static func dismantleUIView(_ uiView: DanmakuCanvasUIView, coordinator: ()) {
        uiView.isRunning = false
        uiView.flush()
    }
}
