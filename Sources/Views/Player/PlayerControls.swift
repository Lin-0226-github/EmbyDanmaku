//
//  PlayerControls.swift
//  EmbyDanmaku
//
//  播放器控制层（参考 EPlayerX / VidHub 布局）：
//  顶栏：关闭 · 画面比例 · 弹幕开关 · 定时关闭 · 复制链接 ｜ 右侧当前时间
//  中部：后退 10 秒 · 播放/暂停（缓冲时显示加载圈）· 前进 10 秒
//  底部：剧集信息 + 标题 ｜ 右侧功能图标行 → 进度条 → 简介/演职表/选集/切换来源
//

import SwiftUI
import AVFoundation
import UIKit

struct PlayerControls: View {
    @ObservedObject var vm: PlayerViewModel
    @EnvironmentObject private var settings: AppSettings

    var onDismiss: () -> Void
    var onPanel: (PlayerView.PlayerPanel) -> Void
    var onToggleDanmaku: () -> Void
    var onSendDanmaku: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            centerRow
            Spacer()
            bottomBar
        }
        .foregroundStyle(.white)
        .background {
            LinearGradient(colors: [.black.opacity(0.72), .clear, .clear, .black.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        }
        // 注意：这里刻意不设置 contentShape，让空白区域的点击穿透到下层手势层
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack(spacing: 16) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 34)
            }
            .buttonStyle(.plain)

            topButton(vm.videoGravity == .resizeAspect
                      ? "arrow.up.left.and.arrow.down.right" : "aspectratio.fill",
                      "画面") {
                vm.toggleGravity()
            }
            topButton(settings.danmakuEnabled ? "text.bubble.fill" : "text.bubble",
                      "弹幕",
                      tint: settings.danmakuEnabled ? AppTheme.accent : .white) {
                onToggleDanmaku()
            }
            topButton("moon.zzz", "定时", tint: vm.sleepActive ? .yellow : .white) {
                onPanel(.sleep)
            }
            topButton(copied ? "checkmark" : "doc.on.doc",
                      copied ? "已复制" : "链接",
                      tint: copied ? AppTheme.success : .white) {
                copyLink()
            }
            Spacer(minLength: 8)
            TimelineView(.everyMinute) { ctx in
                Text(Self.timeText(ctx.date))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    /// 顶栏按钮：图标 + 小字标签，让每个按钮的功能一目了然
    private func topButton(_ systemImage: String,
                           _ label: String,
                           tint: Color = .white,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(tint)
            .frame(minWidth: 32)
        }
        .buttonStyle(.plain)
    }

    private static func timeText(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func copyLink() {
        UIPasteboard.general.string = vm.plan?.url.absoluteString ?? ""
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    // MARK: - 中部

    private var centerRow: some View {
        HStack(spacing: 64) {
            Button {
                Task { await vm.seek(to: max(0, vm.currentTime - 10)) }
            } label: {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 34, weight: .light))
            }
            .buttonStyle(.plain)

            Group {
                if vm.isBuffering {
                    VStack(spacing: 4) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(1.1)
                    }
                } else {
                    Button { vm.togglePlay() } label: {
                        Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 32, weight: .medium))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 44)

            Button {
                Task { await vm.seek(to: vm.currentTime + 10) }
            } label: {
                Image(systemName: "goforward.10")
                    .font(.system(size: 34, weight: .light))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 底栏

    private var bottomBar: some View {
        VStack(spacing: 12) {
            // 定时关闭倒计时提示
            if vm.sleepActive {
                HStack(spacing: 6) {
                    Image(systemName: "moon.zzz.fill")
                    Text("定时关闭 \(vm.sleepRemainingText ?? "")")
                        .monospacedDigit()
                    Button("取消") { vm.sleepTimer.cancel() }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .accentColor(.white)
                }
                .font(.caption)
                .foregroundStyle(.yellow)
            }

            // 标题行 + 功能图标
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(episodeLine)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                    Text(vm.item.SeriesName ?? vm.item.Name ?? "")
                        .font(.system(size: 22, weight: .bold))
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                HStack(spacing: 16) {
                    if vm.playlist.count > 1 {
                        bottomButton("backward.end.fill", "上一集",
                                     tint: vm.previousItem() == nil ? .white.opacity(0.3) : .white) {
                            vm.playPrevious()
                        }
                        .disabled(vm.previousItem() == nil)
                    }
                    if vm.playlist.count > 1 {
                        bottomButton("forward.end.fill", "下一集",
                                     tint: vm.nextItem() == nil ? .white.opacity(0.3) : .white) {
                            vm.playNext()
                        }
                        .disabled(vm.nextItem() == nil)
                    }
                    bottomButton("speedometer", rateLabel) {
                        cycleRate()
                    }
                    bottomButton("ellipsis.message", "弹幕") {
                        onPanel(.danmaku)
                    }
                    bottomButton("bubble.right", "发弹幕") {
                        onSendDanmaku()
                    }
                    bottomButton("slider.horizontal.3", "设置") {
                        onPanel(.settings)
                    }
                }
            }

            // 进度条
            HStack(spacing: 10) {
                Text(PlayerViewModel.formatTime(vm.currentTime))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                ScrubberView(value: Binding(get: { vm.currentTime },
                                            set: { newValue in Task { await vm.seek(to: newValue) } }),
                             duration: vm.duration,
                             buffered: vm.loadedDuration)
                Text(PlayerViewModel.formatTime(max(0, vm.duration)))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
            }

            // 功能胶囊
            HStack(spacing: 10) {
                pill("简介", isActive: false) { onPanel(.info) }
                pill("演职表", isActive: false) { onPanel(.info) }
                if vm.playlist.count > 1 {
                    pill("选集", isActive: false) { onPanel(.episodes) }
                }
                pill("切换来源", isActive: false) { onPanel(.source) }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func pill(_ title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule().stroke(.white.opacity(0.45), lineWidth: 1)
                        .background(Capsule().fill(.black.opacity(0.25)))
                )
        }
        .buttonStyle(.plain)
    }

    /// 底栏按钮：图标 + 小字标签
    private func bottomButton(_ systemImage: String,
                              _ label: String,
                              tint: Color = .white,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 17))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(tint)
            .frame(minWidth: 30)
        }
        .buttonStyle(.plain)
    }

    // MARK: 倍速快捷循环

    private let cycleRates: [Float] = [1.0, 1.25, 1.5, 2.0, 0.5, 0.75]

    private func cycleRate() {
        let cur = vm.playbackRate
        if let idx = cycleRates.firstIndex(where: { abs($0 - cur) < 0.01 }) {
            vm.setRate(cycleRates[(idx + 1) % cycleRates.count])
        } else {
            vm.setRate(1.0)
        }
    }

    private var rateLabel: String {
        let r = vm.playbackRate
        if abs(r - 1.0) < 0.01 { return "倍速" }
        return String(format: "%.2gx", r)
    }

    private var episodeLine: String {
        if vm.item.isEpisode {
            var parts: [String] = []
            if let s = vm.item.ParentIndexNumber, let e = vm.item.IndexNumber {
                parts.append("S\(s),E\(e)")
            }
            if let s = vm.item.ParentIndexNumber { parts.append("季 \(s)") }
            if let n = vm.item.Name, !n.isEmpty { parts.append(n) }
            return parts.joined(separator: " - ")
        }
        var parts: [String] = []
        if let q = vm.plan?.qualityLabel { parts.append(q) }
        if let m = vm.plan.map({ PlaybackDecision.description(for: $0.method) }) { parts.append(m) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 进度条

struct ScrubberView: View {
    @Binding var value: Double
    let duration: Double
    let buffered: Double

    @GestureState private var isDragging = false
    @State private var localValue: Double?

    private let height: CGFloat = 22
    private let barHeight: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let total = max(1, duration)
            let display = localValue ?? value
            let progress = CGFloat(min(1, max(0, display / total))) * width
            let buffer = CGFloat(min(1, max(0, buffered / total))) * width

            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25)).frame(height: barHeight)
                Capsule().fill(Color.white.opacity(0.45)).frame(width: buffer, height: barHeight)
                Capsule().fill(Color.accentColor).frame(width: progress, height: barHeight)
                Circle()
                    .fill(Color.white)
                    .frame(width: isDragging ? 16 : 11, height: isDragging ? 16 : 11)
                    .offset(x: max(0, progress - (isDragging ? 8 : 5.5)))
                    .animation(.easeOut(duration: 0.12), value: isDragging)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragging) { _, state, _ in state = true }
                    .onChanged { drag in
                        let ratio = min(1, max(0, drag.location.x / max(1, width)))
                        localValue = ratio * total
                    }
                    .onEnded { drag in
                        let ratio = min(1, max(0, drag.location.x / max(1, width)))
                        let target = ratio * total
                        localValue = nil
                        value = target
                    }
            )
            .overlay(alignment: .top) {
                if isDragging, let lv = localValue {
                    Text(PlayerViewModel.formatTime(lv))
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.7), in: Capsule())
                        .offset(y: -22)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: height)
    }
}
