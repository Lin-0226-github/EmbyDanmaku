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
        case settings, episodes, danmaku, sleep, info, source
        var id: String { rawValue }
    }

    @StateObject private var vm: PlayerViewModel
    @StateObject private var volumeController = SystemVolumeController()
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var playlistStore = PlaylistStore.shared

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
    @State private var toastText: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var isLandscape: Bool = UIDevice.current.orientation.isLandscape
    /// 真实安全区：铺满整屏后自己补，控制层才不会被刘海 / 横屏圆角切掉
    @State private var safeInsets: UIEdgeInsets = .zero

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

            // 关键：GeometryReader 直接吃下整块屏幕（含安全区），
            // 否则横屏时「安全区内尺寸」的控制层会被外层 ZStack 居中，整体上移，
            // 顶栏按钮会被屏幕上缘切掉一截。
            GeometryReader { geo in
                ZStack(alignment: .center) {
                    PlayerLayerView(player: vm.player, gravity: vm.videoGravity)

                    // 弹幕层
                    DanmakuCanvasView(engine: vm.engine,
                                      isRunning: vm.isPlaying && settings.danmakuEnabled,
                                      timeProvider: { vm.danmakuCurrentTime() })
                        .allowsHitTesting(false)

                    // 字幕层
                    subtitleLayer(size: geo.size)

                    // 控制层：**常驻视图树**，只用透明度显隐。
                    // 之前用 `if showControls` 条件插入 + transition，在 iOS 15 上反复隐藏/出现几次后，
                    // 会出现「画得出但点不着」的命中失效（触摸直接穿透到下面），这是按钮按不了的根源。
                    PlayerControls(vm: vm,
                                   onDismiss: { closePlayer() },
                                   onPanel: { openPanel($0) },
                                   onToggleDanmaku: { toggleDanmaku() },
                                   onSendDanmaku: { showDanmakuInput = true },
                                   onToggleOrientation: { toggleOrientation() },
                                   isLandscape: isLandscape,
                                   insets: safeInsets,
                                   onToast: { showToast($0) })
                        .opacity(showControls ? 1 : 0)
                        .allowsHitTesting(showControls)

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
                // 手势全部挂在容器本身（父层手势优先级低于子按钮，点按钮不会误触发），
                // 不再用「垫在下层的透明手势层」——那种结构在 iOS 15 上会干扰上方按钮的命中。
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { handleDragChanged($0, size: geo.size) }
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
            .ignoresSafeArea()

            // 隐藏的 MPVolumeView：MPVolumeView 不会裁剪子视图（音量滑杆约 260pt 宽），
            // 叠在屏幕中央会拦截中间按钮的触摸。这里彻底挪出屏幕外并禁用命中。
            VolumeHostingView(controller: volumeController)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .offset(x: -3000, y: -3000)
                .allowsHitTesting(false)
        }
        .statusBarHidden(true)
        .onAppear {
            scheduleControlsHide()
            recordHistory()
            refreshInsets()
            // 横屏时底部上滑需两次才回主屏（防误触）
            ScreenEdgeGestures.deferBottomGestures(isLandscape)
        }
        .onChange(of: isLandscape) { land in
            ScreenEdgeGestures.deferBottomGestures(land)
        }
        .onDisappear {
            controlsTask?.cancel()
            // 退出播放器一律回到竖屏，解除方向锁定；恢复系统默认手势
            ScreenEdgeGestures.deferBottomGestures(false)
            OrientationController.portrait()
            vm.onDisappear()
        }
        .onChange(of: vm.isPlaying) { playing in
            if playing { scheduleControlsHide() } else { controlsTask?.cancel() }
        }
        // 旋转设备后同步按钮图标与安全区
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            let landscape = UIDevice.current.orientation.isLandscape
            if landscape != isLandscape {
                isLandscape = landscape
                showToast(landscape ? "已切换到横屏" : "已切换到竖屏")
            }
            refreshInsets()
            OrientationController.scheduleSafeAreaRefresh()
        }
        // 旋转后延迟重读安全区（不捕获 self，避免 struct 在逃逸闭包里的问题）
        .onReceive(NotificationCenter.default.publisher(for: .refreshSafeArea)) { _ in
            safeInsets = ScreenSafeArea.insets
        }
        .overlay { panelOverlay() }
        .overlay(alignment: .bottom) {
            // 弹幕输入条：同样常驻视图树，避免条件插入导致命中失效
            danmakuInputBar
                .offset(y: showDanmakuInput ? 0 : 160)
                .opacity(showDanmakuInput ? 1 : 0)
                .allowsHitTesting(showDanmakuInput)
                .animation(.easeOut(duration: 0.2), value: showDanmakuInput)
        }
        .overlay(alignment: .center) {
            if let text = toastText {
                toastView(text)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.18), value: toastText)
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
    //
    // 说明：拖动 / 单击 / 双击 / 长按倍速全部挂在上面的容器上，这里只保留处理逻辑。

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
        OrientationController.portrait()
        vm.onDisappear()
        dismiss()
    }

    // MARK: - 横竖屏

    private func toggleOrientation() {
        if isLandscape {
            OrientationController.portrait()
            showToast("竖屏")
        } else {
            OrientationController.landscape()
            showToast("横屏")
        }
        isLandscape.toggle()
        scheduleControlsHide()
        refreshInsets()
        OrientationController.scheduleSafeAreaRefresh()
    }

    /// 重新读取窗口安全区
    private func refreshInsets() {
        safeInsets = ScreenSafeArea.insets
    }

    /// 记一条本机播放历史，供「清单 → 播放历史」使用
    private func recordHistory() {
        let entry = PlaylistEntry.make(from: item, serverId: PlaylistStore.currentServerId)
        playlistStore.recordHistory(entry)
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
    //
    // 说明：iOS 15 上在 fullScreenCover 里再弹系统 .sheet 经常「点了没反应」，
    // 所以这里全部改成**内嵌浮层**，由 activePanel 驱动，不再依赖系统 presentation。

    private func openPanel(_ panel: PlayerPanel) {
        controlsTask?.cancel()
        activePanel = panel
        showControls = true
    }

    private func closePanel() {
        activePanel = nil
        vm.refreshDanmakuSettings()
        scheduleControlsHide()
    }

    /// 面板浮层：**常驻视图树**（关闭时整体滑到屏幕外 + 禁用命中），
    /// 不做条件插入 / 移除，规避 iOS 15 的命中失效问题。
    @ViewBuilder
    private func panelOverlay() -> some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Color.black
                    .opacity(activePanel == nil ? 0 : 0.5)
                    .contentShape(Rectangle())
                    .onTapGesture { closePanel() }

                VStack(spacing: 0) {
                    Capsule()
                        .fill(Color.white.opacity(0.32))
                        .frame(width: 42, height: 4)
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                    panelView(activePanel ?? .settings)
                        .id(activePanel?.id ?? "closed")
                }
                // 横屏时屏幕高度只有 300 多，面板必须跟着变矮，否则会顶出屏幕
                .frame(width: geo.size.width,
                       height: min(geo.size.height * 0.82,
                                   max(320, geo.size.height * 0.62)))
                .background(AppTheme.background)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .offset(y: activePanel == nil ? geo.size.height + 60 : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .allowsHitTesting(activePanel != nil)
            .animation(.easeOut(duration: 0.24), value: activePanel)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder
    private func panelView(_ panel: PlayerPanel) -> some View {
        switch panel {
        case .settings: PlayerSettingsPanel(vm: vm, onClose: { closePanel() })
        case .episodes: EpisodePanel(vm: vm, onClose: { closePanel() })
        case .danmaku: DanmakuPanel(vm: vm, onClose: { closePanel() })
        case .sleep: SleepTimerPanel(timer: vm.sleepTimer, onClose: { closePanel() })
        case .info: ItemInfoPanel(client: client, item: vm.item, onClose: { closePanel() })
        case .source: SourcePanel(vm: vm, onClose: { closePanel() })
        }
    }

    // MARK: - 轻提示

    private func showToast(_ text: String) {
        toastTask?.cancel()
        toastText = text
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            toastText = nil
        }
    }

    private func toastView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.black.opacity(0.66), in: Capsule())
            .padding(.horizontal, 30)
    }
}
