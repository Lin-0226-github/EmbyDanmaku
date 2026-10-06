//
//  EmbyDanmakuApp.swift
//  EmbyDanmaku
//
//  应用入口。
//

import SwiftUI

@main
struct EmbyDanmakuApp: App {

    @StateObject private var appState = AppState()
    @StateObject private var settings = AppSettings.shared

    init() {
        // 应用启动时统一外观
        let nav = UINavigationBar.appearance()
        nav.tintColor = .label
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(settings)
                .accentColor(AppTint.accent)
                .preferredColorScheme(nil)
        }
    }
}

enum AppTint {
    static let accent = Color(red: 0.20, green: 0.62, blue: 0.95)
}
