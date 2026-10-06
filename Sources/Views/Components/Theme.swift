//
//  Theme.swift
//  EmbyDanmaku
//
//  全局深色主题：配色、通用标题、卡片容器、胶囊按钮。
//  风格参考 EPlayerX / VidHub：纯黑底 + 高对比强调色 + 大圆角卡片。
//

import SwiftUI

// MARK: - 配色

enum AppTheme {

    /// 强调色（亮蓝）
    static let accent = Color(red: 0.24, green: 0.55, blue: 1.0)
    /// 次强调（播放按钮渐变用）
    static let accentWarm = Color(red: 0.99, green: 0.42, blue: 0.36)

    /// App 最底层背景（近纯黑）
    static let background = Color(red: 0.043, green: 0.043, blue: 0.055)
    /// 卡片 / 分组背景
    static let card = Color(red: 0.086, green: 0.086, blue: 0.106)
    /// 抬高一层（弹层、输入框）
    static let elevated = Color(red: 0.125, green: 0.125, blue: 0.149)
    /// 按下态
    static let pressed = Color(red: 0.165, green: 0.165, blue: 0.192)

    static let separator = Color.white.opacity(0.09)
    static let hairline = Color.white.opacity(0.06)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.38)

    static let success = Color(red: 0.30, green: 0.80, blue: 0.52)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.30)
    static let danger = Color(red: 1.0, green: 0.42, blue: 0.42)
}

// MARK: - 背景

struct AppBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppTheme.background.ignoresSafeArea())
    }
}

extension View {
    func appBackground() -> some View { modifier(AppBackground()) }
}

// MARK: - 分区标题

struct SectionHeader: View {
    let title: String
    var systemImage: String? = nil
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 7) {
            if let s = systemImage {
                Image(systemName: s)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
            if let sub = subtitle {
                Text(sub)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            Spacer(minLength: 8)
            if let a = actionTitle {
                Button {
                    action?()
                } label: {
                    HStack(spacing: 2) {
                        Text(a).font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - 卡片容器

struct DarkCard<Content: View>: View {
    let padding: CGFloat
    let content: Content

    init(padding: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.hairline, lineWidth: 1)
            )
    }
}

// MARK: - 胶囊按钮

struct CapsuleButton: View {
    let title: String
    var systemImage: String? = nil
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button { action() } label: {
            HStack(spacing: 5) {
                if let s = systemImage {
                    Image(systemName: s).font(.system(size: 12, weight: .semibold))
                }
                Text(title).font(.system(size: 14, weight: .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isActive ? AppTheme.accent : AppTheme.elevated)
            )
            .foregroundStyle(isActive ? .white : AppTheme.textSecondary)
        }
        .buttonStyle(.plain)
    }
}

/// EPlayerX 风格的主播放按钮（渐变实心）
struct PrimaryPlayButton: View {
    let title: String
    var systemImage: String = "play.fill"
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button { action() } label: {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView().progressViewStyle(.circular)
                } else {
                    Image(systemName: systemImage).font(.system(size: 15, weight: .semibold))
                }
                Text(title).font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                LinearGradient(colors: [AppTheme.accent, AppTheme.accent.opacity(0.72)],
                               startPoint: .leading, endPoint: .trailing)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

/// 次要图标按钮（收藏 / 已看 / 加入清单）
struct CircleIconButton: View {
    let systemImage: String
    var active: Bool = false
    var activeColor: Color = AppTheme.accentWarm
    var size: CGFloat = 46
    let action: () -> Void

    var body: some View {
        Button { action() } label: {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(active ? activeColor : AppTheme.textSecondary)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.elevated)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 空状态

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 46))
                .foregroundStyle(AppTheme.textTertiary)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
            if let s = subtitle {
                Text(s)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

// MARK: - 分段选择器（深色）

struct DarkSegmentedPicker<Selection: Hashable, Content: View>: View {
    let selection: Binding<Selection>
    let content: Content

    init(selection: Binding<Selection>, @ViewBuilder content: () -> Content) {
        self.selection = selection
        self.content = content()
    }

    var body: some View {
        // iOS 15 没有 .scrollContentBackground，这里手动铺一层底色
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.elevated)
            Picker("", selection: selection) { content }
                .pickerStyle(.segmented)
                .padding(3)
        }
        .frame(height: 38)
    }
}
