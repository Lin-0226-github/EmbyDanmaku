//
//  MineView.swift
//  EmbyDanmaku
//
//  「我的」页：账户卡片 + 数据概览 + 设置入口。
//  风格：纯黑底 + 大圆角卡片，与首页 / 清单保持一致。
//

import SwiftUI

struct MineView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var store = PlaylistStore.shared

    @State private var showLogoutConfirm = false
    @State private var showClearHistory = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 18) {
                    profileCard
                    statsRow
                    entriesSection
                    footNote
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .appBackground()
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("确定退出登录？", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                Button("退出登录", role: .destructive) { appState.logout() }
                Button("取消", role: .cancel) { }
            }
            .confirmationDialog("清空本机的播放历史？", isPresented: $showClearHistory, titleVisibility: .visible) {
                Button("清空", role: .destructive) { store.clearHistory() }
                Button("取消", role: .cancel) { }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: 账户卡片

    private var profileCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.elevated)
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(AppTheme.accent)
            }
            .frame(width: 62, height: 62)

            VStack(alignment: .leading, spacing: 4) {
                Text(appState.currentUserName ?? "未登录")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(appState.currentServer?.name ?? "未连接服务器")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
                if let url = appState.currentServer?.url {
                    Text(url)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)

            Button { appState.switchServer() } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(AppTheme.elevated))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
    }

    // MARK: 数据概览

    private var statsRow: some View {
        HStack(spacing: 12) {
            statCard(title: "稍后再看", value: "\(store.watchLater.items.count)", systemImage: "bookmark.fill")
            statCard(title: "播放历史", value: "\(store.history.count)", systemImage: "clock.arrow.circlepath")
            statCard(title: "自建清单", value: "\(store.customPlaylists.count)", systemImage: "list.bullet.rectangle")
        }
    }

    private func statCard(title: String, value: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
            Text(value)
                .font(.system(size: 20, weight: .bold).monospacedDigit())
                .foregroundStyle(AppTheme.textPrimary)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
    }

    // MARK: 设置入口

    private var entriesSection: some View {
        VStack(spacing: 10) {
            NavigationLink { DanmakuSourceSettings() } label: {
                entryRow(systemImage: "text.bubble",
                         title: "弹幕服务",
                         detail: settings.danmakuSourceConfigured ? "已配置" : "未配置",
                         detailColor: settings.danmakuSourceConfigured ? AppTheme.success : AppTheme.warning)
            }
            NavigationLink { PlaybackSettings() } label: {
                entryRow(systemImage: "play.rectangle", title: "播放设置", detail: "直连 / 码率 / 手势")
            }
            NavigationLink { SubtitleSettings() } label: {
                entryRow(systemImage: "captions.bubble", title: "字幕与画面", detail: "字号 \(Int(settings.subtitleSize))")
            }
            NavigationLink { SleepDefaultSettings() } label: {
                entryRow(systemImage: "moon.zzz",
                         title: "定时关闭",
                         detail: settings.defaultSleepMinutes == 0 ? "不启用" : "默认 \(settings.defaultSleepMinutes) 分钟")
            }
        }
    }

    private func entryRow(systemImage: String,
                          title: String,
                          detail: String? = nil,
                          detailColor: Color = AppTheme.textTertiary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(AppTheme.elevated))
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppTheme.textPrimary)
            Spacer(minLength: 6)
            if let d = detail {
                Text(d)
                    .font(.system(size: 12))
                    .foregroundStyle(detailColor)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
    }

    // MARK: 底部

    private var footNote: some View {
        VStack(spacing: 10) {
            Button(role: .destructive) { showClearHistory = true } label: {
                Text("清空播放历史")
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppTheme.danger.opacity(0.35), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button(role: .destructive) { showLogoutConfirm = true } label: {
                Text("退出登录")
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppTheme.hairline, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Text(appVersionText)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textTertiary)
                .padding(.top, 4)
        }
    }

    private var appVersionText: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Lplayers \(v) (\(b))"
    }
}

// MARK: - 拆分的三个设置子页（复用 AppSettings）

struct PlaybackSettings: View {
    @EnvironmentObject private var settings: AppSettings

    private let bitrateOptions: [(String, Int)] = [
        ("自动（60 Mbps）", 60_000_000),
        ("40 Mbps", 40_000_000),
        ("20 Mbps", 20_000_000),
        ("10 Mbps", 10_000_000),
        ("4 Mbps", 4_000_000),
        ("2 Mbps", 2_000_000)
    ]

    var body: some View {
        Form {
            Section {
                Picker("转码码率上限", selection: $settings.maxBitrate) {
                    ForEach(bitrateOptions, id: \.1) { t in Text(t.0).tag(t.1) }
                }
                Toggle("优先直连播放", isOn: $settings.preferDirectPlay)
                Toggle("自动从上次进度续播", isOn: $settings.autoResume)
                Toggle("手势控制（亮度/音量/快进）", isOn: $settings.gesturesEnabled)
                Toggle("后台继续播放", isOn: $settings.backgroundPlayback)
            } header: {
                Text("播放")
            } footer: {
                Text("直连播放画质最好、服务器压力最小；网络或格式不支持时会自动回退到服务器转码。")
            }
        }
        .appBackground()
        .navigationTitle("播放设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SubtitleSettings: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("字幕") {
                Stepper(value: $settings.subtitleSize, in: 14...36, step: 1) {
                    Text("默认字号 \(Int(settings.subtitleSize))")
                }
            }
        }
        .appBackground()
        .navigationTitle("字幕与画面")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SleepDefaultSettings: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("定时关闭") {
                Picker("默认时长", selection: $settings.defaultSleepMinutes) {
                    Text("不启用").tag(0)
                    ForEach(SleepTimer.presets, id: \.self) { m in
                        Text("\(m) 分钟").tag(m)
                    }
                }
            }
        }
        .appBackground()
        .navigationTitle("定时关闭")
        .navigationBarTitleDisplayMode(.inline)
    }
}
