//
//  RootView.swift
//  EmbyDanmaku
//
//  应用根视图：根据登录状态切换服务器列表与主界面（底部五栏）。
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.isLoggedIn, appState.client != nil {
                MainTabView()
            } else {
                ServerListView()
                    .appBackground()
            }
        }
        .task {
            await appState.restoreSession()
        }
        .animation(.easeOut(duration: 0.2), value: appState.isLoggedIn)
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }
            PlaylistHubView()
                .tabItem { Label("清单", systemImage: "list.bullet") }
            LibraryTabView()
                .tabItem { Label("媒体库", systemImage: "square.grid.2x2.fill") }
            MineView()
                .tabItem { Label("我的", systemImage: "person.fill") }
            SearchView()
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }
        }
        .accentColor(AppTheme.accent)
    }
}
