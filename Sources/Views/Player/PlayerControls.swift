//
//  PlayerControls.swift
//  EmbyDanmaku
//
//  播放器控制层：顶栏、底部控制条、进度条。
//

import SwiftUI
import AVFoundation

struct PlayerControls: View {
    @ObservedObject var vm: PlayerViewModel
    @EnvironmentObject private var settings: AppSettings

    var onDismiss: () -> Void
    var onPanel: (PlayerView.PlayerPanel) -> Void
    var onToggleDanmaku: () -> Void
    var onSendDanmaku: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            bottomBar
        }
        .foregroundStyle(.white)
        .background {
            LinearGradient(colors: [.black.opacity(0.7), .clear, .clear, .black.opacity(0.8)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        }
        // 注意：这里刻意不设置 contentShape，让空白区域的点击穿透到下层手势层
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: onDismiss) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.35), in: Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(vm.item.SeriesName ?? vm.item.Name ?? "")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(subtitleLine)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onToggleDanmaku) {
                Image(systemName: settings.danmakuEnabled ? "text.bubble.fill" : "text.bubble")
                    .font(.system(size: 16))
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.35), in: Circle())
            }

            Button { onPanel(.sleep) } label: {
                Image(systemName: vm.sleepActive ? "timer" : "moon.zzz")
                    .font(.system(size: 16))
                    .foregroundStyle(vm.sleepActive ? .yellow : .white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.35), in: Circle())
            }

            Button { onPanel(.settings) } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16))
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.35), in: Circle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private var subtitleLine: String {
        var parts: [String] = []
        if vm.item.isEpisode { parts.append(vm.item.displayTitle) }
        if let q = vm.plan?.qualityLabel { parts.append(q) }
        if let m = vm.plan.map({ PlaybackDecision.description(for: $0.method) }) { parts.append(m) }
        return parts.joined(separator: " · ")
    }

    // MARK: - 底栏

    private var bottomBar: some View {
        VStack(spacing: 10) {
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

            ScrubberView(value: Binding(get: { vm.currentTime },
                                        set: { Task { await vm.seek(to: $0) } }),
                         duration: vm.duration,
                         buffered: vm.loadedDuration)

            HStack(spacing: 16) {
                Text(PlayerViewModel.formatTime(vm.currentTime))
                    .font(.caption.monospacedDigit())
                    .frame(width: 52, alignment: .leading)
                Spacer()
                Text("-" + PlayerViewModel.formatTime(max(0, vm.duration - vm.currentTime)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.75))
            }
            .font(.caption)

            HStack(alignment: .center, spacing: 22) {
                if vm.playlist.count > 1 {
                    Button { vm.playPrevious() } label: {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 20))
                    }
                    .disabled(vm.previousItem() == nil)
                }

                Button { vm.togglePlay() } label: {
                    Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30))
                }
                .frame(width: 52)

                if vm.playlist.count > 1 {
                    Button { vm.playNext() } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 20))
                    }
                    .disabled(vm.nextItem() == nil)
                }

                Spacer()

                Menu {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0], id: \.self) { r in
                        Button {
                            vm.setRate(Float(r))
                        } label: {
                            HStack {
                                Text(String(format: "%.2gx", r))
                                if abs(vm.playbackRate - Float(r)) < 0.01 { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    Text(vm.playbackRate == 1 ? "倍速" : String(format: "%.2gx", vm.playbackRate))
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 44)
                }

                if vm.playlist.count > 1 {
                    Button { onPanel(.episodes) } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 18))
                    }
                }

                Button { onPanel(.danmaku) } label: {
                    Image(systemName: "ellipsis.message")
                        .font(.system(size: 18))
                }

                Button(action: onSendDanmaku) {
                    Image(systemName: "bubble.right")
                        .font(.system(size: 18))
                }

                Button { vm.toggleGravity() } label: {
                    Image(systemName: vm.videoGravity == .resizeAspect ? "aspectratio" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 18))
                }
            }
            .padding(.bottom, 18)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
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
