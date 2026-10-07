//
//  EmbyDanmakuApp.swift
//  EmbyDanmaku
//
//  应用入口。全局强制深色外观。
//

import SwiftUI

@main
struct EmbyDanmakuApp: App {

    @StateObject private var appState = AppState()
    @StateObject private var settings = AppSettings.shared
    // 由它动态决定窗口允许的方向（播放器切换横竖屏用）
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(settings)
                .accentColor(AppTheme.accent)
                .preferredColorScheme(.dark)
        }
    }

    // MARK: - 外观

    private func configureAppearance() {
        // 导航栏
        let nav = UINavigationBar.appearance()
        nav.tintColor = UIColor(AppTheme.accent)
        nav.titleTextAttributes = [.foregroundColor: UIColor.white]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        nav.barTintColor = UIColor(AppTheme.background)
        nav.backgroundColor = UIColor(AppTheme.background)

        // 标签栏
        let tab = UITabBar.appearance()
        tab.tintColor = UIColor(AppTheme.accent)
        tab.barTintColor = UIColor(AppTheme.background)
        tab.backgroundColor = UIColor(AppTheme.background)
        tab.unselectedItemTintColor = UIColor.white.withAlphaComponent(0.45)

        // 列表 / 表单：让 SwiftUI 的背景透出来
        UITableView.appearance().backgroundColor = .clear
        UITableViewCell.appearance().backgroundColor = .clear
        UITableView.appearance().separatorColor = UIColor.white.withAlphaComponent(0.10)

        // 分段控件
        let seg = UISegmentedControl.appearance()
        seg.backgroundColor = UIColor(AppTheme.elevated)
        seg.selectedSegmentTintColor = UIColor(AppTheme.accent)
        seg.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        seg.setTitleTextAttributes([.foregroundColor: UIColor.white.withAlphaComponent(0.72)], for: .normal)

        // 搜索框
        UISearchBar.appearance().tintColor = UIColor(AppTheme.accent)
        UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self])
            .tintColor = UIColor(AppTheme.accent)
    }
}

enum AppTint {
    static let accent = AppTheme.accent
}
