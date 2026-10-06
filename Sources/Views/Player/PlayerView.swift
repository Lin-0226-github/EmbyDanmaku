//
//  PlayerView.swift
//  EmbyDanmaku
//
//  全屏播放器：视频层 + 弹幕层 + 字幕层 + 手势 + 控制层。
//  交互参考 VidHub / EPlayerX：左半屏调亮度、右半屏调音量、水平拖动快进、双击播放暂停。
//

import SwiftUI
import AVFoundation
import AVKit
import MediaPlayer
import UIKit

// MARK: - 视频层

final class PlayerLayerUIView: UIView {
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    override static var layerClass: AnyClass { AVPlayerLayer.self }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity

    func makeUIView(context: Context) -> PlayerLayerUIView {
        let v = PlayerLayerUIView(frame: .zero)
        v.playerLayer.player = player
        v.playerLayer.videoGravity = gravity
        v.backgroundColor = .black
        return v
    }

    func updateUIView(_ uiView: PlayerLayerUIView, context: Context) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = gravity
    }
}

// MARK: - 音量控制

final class SystemVolumeController: ObservableObject {
    /// 隐藏的 MPVolumeView，用于写系统音量
    let volumeView = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
    private var slider: UISlider?

    @Published var value: Float = 0.5

    init() {
        value = AVAudioSession.sharedInstance().outputVolume
        findSlider()
    }

    private func findSlider() {
        for sub in volumeView.subviews {
            if let s = sub as? UISlider { slider = s; return }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            for sub in self?.volumeView.subviews ?? [] {
                if let s = sub as? UISlider { self?.slider = s; return }
            }
        }
    }

    func set(_ v: Float) {
        let clamped = min(1, max(0, v))
        value = clamped
        slider?.value = clamped
    }

    func refresh() {
        value = AVAudioSession.sharedInstance().outputVolume
    }
}

struct VolumeHostingView: UIViewRepresentable {
    let controller: SystemVolumeController
    func makeUIView(context: Context) -> MPVolumeView { controller.volumeView }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

// MARK: - 手势状态

enum DragMode {
    case none
    case seek(startTime: Double, offset: Double)
    case brightness(start: CGFloat)
    case volume(start: Float)
}

// MARK: - 播放器主体

struct PlayerView: View {
    let client: EmbyClient
    let item: BaseItem
    let playlist: [BaseItem]
    let startSeconds: Double?

    enum PlayerPanel: String, Identifiable {
        case settings, episodes, danmaku, sleep
        var id: String { rawValue }
    }

    @StateObject private var vm: PlayerViewModel
    @StateObject private var volumeController = SystemVolumeController()
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings

    @State private var showControls: Bool = true
    @State private var dragMode: DragMode = .none
    @State private var hudText: String?
    @State private var hudValue: Double?
    @State private var previewTime: Double = 0
    @State private var screenBrightness: CGFloat = UIScreen.main.brightness
    @State private var previousRate: Float?
    @State private var activePanel: PlayerPanel?
    @State private var showDanmakuInput = false
    @State private var danmakuInputText = ""
    @State private var controlsTask: Task<Void, Never>?

    init(client: EmbyClient, item: BaseItem, playlist: [BaseItem], startSeconds: Double?) {
        self.client = client
        self.item = item
        self.playlist = playlist
        self.startSeconds = startSeconds
        _vm = StateObject(wrappedValue: PlayerViewModel(client: client,
                                                        item: item,
                                                        playlist: playlist,
                                                        startSeconds: startSeconds))
    }

    var body: some View {
        ZStack(alignment: .center) {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                ZStack(alignment: .center) {
                    PlayerLayerView(player: vm.player, gravity: vm.videoGravity)
                        .ignoresSafeArea()

                    // 弹幕层
                    DanmakuCanvasView(engine: vm.engine,
                                      isRunning: vm.isPlaying && settings.danmakuEnabled,
                                      timeProvider: { vm.danmakuCurrentTime() })
                        .ignoresSafeArea()
                        .allowsHitTesting(false)

                    // 字幕层
                    subtitleLayer(size: geo.size)

                    // 手势层：位于控制层之下，空白区域由它响应，控制按钮优先响应
                    gestureLayer(size: geo.size)

                    // 控制层
                    if showControls {
                        PlayerControls(vm: vm,
                                       onDismiss: { closePlayer() },
                                       onPanel: { activePanel = $0 },
                                       onToggleDanmaku: { toggleDanmaku() },
                                       onSendDanmaku: { showDanmakuInput = true })
                            .transition(.opacity)
                    }

                    // 手势提示
                    if hudText != nil {
                        gestureHUD
                    }

                    if vm.isBuffering {
                        ProgressView()
                            .controlSize(.large)
                            .accentColor(.white)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }

            VolumeHostingView(controller: volumeController)
                .frame(width: 1, height: 1)
                .opacity(0.01)
        }
        .statusBarHidden(true)
        .onAppear { scheduleControlsHide() }
        .onDisappear {
            controlsTask?.cancel()
            vm.onDisappear()
        }
        .onChange(of: vm.isPlaying) { playing in
            if playing { scheduleControlsHide() } else { controlsTask?.cancel() }
        }
        .sheet(item: $activePanel) { panel in
            panelView(panel)
        }
        .overlay(alignment: .bottom) {
            if showDanmakuInput { danmakuInputBar }
        }
        .alert("定时关闭", isPresented: Binding(get: { vm.sleepFiredMessage != nil },
                                                set: { if !$0 { vm.sleepFiredMessage = nil } })) {
            Button("继续播放") { vm.play() }
            Button("好", role: .cancel) { }
        } message: {
            Text(vm.sleepFiredMessage ?? "")
        }
        .alert("播放失败", isPresented: Binding(get: { vm.errorMessage != nil },
                                                set: { if !$0 { vm.errorMessage = nil } })) {
            Button("重试") { vm.errorMessage = nil; Task { await vm.load() } }
            Button("关闭", role: .cancel) { closePlayer() }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - 字幕

    private func subtitleLayer(size: CGSize) -> some View {
        VStack {
            Spacer()
            if let text = vm.currentSubtitleText, !text.isEmpty {
                Text(text)
                    .font(.system(size: vm.subtitleFontSize, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                    .padding(.bottom, showControls ? 100 : 44)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    // MARK: - 手势

    private func gestureLayer(size: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { handleDragChanged($0, size: size) }
                    .onEnded { _ in handleDragEnded() }
            )
            .onTapGesture(count: 1) {
                // 单击：显示 / 隐藏控制层
                withAnimation(.easeOut(duration: 0.18)) { showControls.toggle() }
                if showControls { scheduleControlsHide() } else { controlsTask?.cancel() }
            }
            .onTapGesture(count: 2) {
                // 双击：播放 / 暂停（声明在后，优先级更高，双击时不会触发单击）
                vm.togglePlay()
                scheduleControlsHide()
            }
            .onLongPressGesture(minimumDuration: 0.6) {
                if vm.playbackRate < 2 { previousRate = vm.playbackRate; vm.setRate(3.0) }
            } onPressingChanged: { pressing in
                if !pressing, let r = previousRate { vm.setRate(r); previousRate = nil }
            }
    }

    private func handleDragChanged(_ value: DragGesture.Value, size: CGSize) {
        guard settings.gesturesEnabled else { return }
        controlsTask?.cancel()
        let dx = value.translation.width
        let dy = value.translation.height

        switch dragMode {
        case .none:
            if abs(dx) > abs(dy) {
                dragMode = .seek(startTime: vm.currentTime, offset: 0)
            } else if value.startLocation.x < size.width / 2 {
                screenBrightness = UIScreen.main.brightness
                dragMode = .brightness(start: screenBrightness)
            } else {
                volumeController.refresh()
                dragMode = .volume(start: volumeController.value)
            }
        case .seek(let start, _):
            // 横向滑过整屏 ≈ 90 秒
            let delta = Double(dx) / Double(max(1, size.width)) * 90
            dragMode = .seek(startTime: start, offset: delta)
            previewTime = max(0, min(start + delta, max(vm.duration, 0)))
            hudText = "快进 / 快退"
            hudValue = delta
        case .brightness(let start):
            let delta = -CGFloat(dy) / max(1, size.height)
            let v = min(1, max(0, start + delta))
            screenBrightness = v
            UIScreen.main.brightness = v
            hudText = "亮度"
            hudValue = Double(v)
        case .volume(let start):
            let delta = -Float(dy) / Float(max(1, size.height))
            volumeController.set(min(1, max(0, start + delta)))
            hudText = "音量"
            hudValue = Double(volumeController.value)
        }
    }

    private func handleDragEnded() {
        if case .seek(let start, let offset) = dragMode {
            Task { await vm.seek(to: max(0, start + offset)) }
        }
        dragMode = .none
        hudText = nil
        hudValue = nil
        scheduleControlsHide()
    }

    private var gestureHUD: some View {
        VStack(spacing: 8) {
            Image(systemName: iconForHUD)
                .font(.system(size: 26))
            Text(hudText ?? "")
                .font(.subheadline)
            if case .seek = dragMode {
                Text("\(PlayerViewModel.formatTime(previewTime)) / \(PlayerViewModel.formatTime(vm.duration))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
            } else if let v = hudValue {
                ProgressView(value: v, total: 1.0)
                    .frame(width: 120)
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var iconForHUD: String {
        switch dragMode {
        case .seek(_, let offset): return offset >= 0 ? "goforward" : "gobackward"
        case .brightness: return "sun.max.fill"
        case .volume: return "speaker.wave.2.fill"
        case .none: return "circle"
        }
    }

    // MARK: - 控制层自动隐藏

    private func scheduleControlsHide() {
        controlsTask?.cancel()
        controlsTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { showControls = false }
        }
    }

    // MARK: - 动作

    private func toggleDanmaku() {
        vm.danmakuManager.toggleEnabled(!settings.danmakuEnabled)
        vm.refreshDanmakuSettings()
    }

    private func closePlayer() {
        vm.onDisappear()
        dismiss()
    }

    // MARK: - 弹幕输入

    private var danmakuInputBar: some View {
        HStack(spacing: 10) {
            TextField("发条弹幕…", text: $danmakuInputText)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.send)
                .onSubmit { sendDanmaku() }
            Button("发送") { sendDanmaku() }
                .buttonStyle(.borderedProminent)
                .disabled(danmakuInputText.trimmingCharacters(in: .whitespaces).isEmpty)
            Button {
                showDanmakuInput = false
                danmakuInputText = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private func sendDanmaku() {
        vm.danmakuManager.send(text: danmakuInputText, at: vm.currentTime)
        danmakuInputText = ""
        showDanmakuInput = false
    }

    // MARK: - 面板

    @ViewBuilder
    private func panelView(_ panel: PlayerPanel) -> some View {
        switch panel {
        case .settings: PlayerSettingsPanel(vm: vm)
        case .episodes: EpisodePanel(vm: vm)
        case .danmaku: DanmakuPanel(vm: vm)
        case .sleep: SleepTimerPanel(timer: vm.sleepTimer)
        }
    }
}
