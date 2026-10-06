//
//  LibraryServersView.swift
//  EmbyDanmaku
//
//  「媒体库」Tab：服务器管理。列出已添加的 Emby 服务器，
//  点进任意服务器即可浏览它的媒体库；支持添加、删除、切换当前服务器。
//

import SwiftUI

struct LibraryServersView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showAddSheet = false

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if appState.servers.isEmpty {
                            emptyCard
                        } else {
                            ForEach(appState.servers) { s in
                                serverCard(s)
                            }
                        }

                        addCard

                        Text("点进服务器即可浏览它的媒体库；卡片会标注当前正在使用的服务器。")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.textTertiary)
                            .padding(.horizontal, 16)
                            .padding(.top, 2)
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("媒体库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddServerSheet { url in
                    Task { await appState.addServer(url: url) }
                }
                .preferredColorScheme(.dark)
            }
            .alert("出错了", isPresented: Binding(get: { appState.errorMessage != nil },
                                                  set: { if !$0 { appState.errorMessage = nil } })) {
                Button("好", role: .cancel) { appState.errorMessage = nil }
            } message: {
                Text(appState.errorMessage ?? "")
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: 服务器卡片

    private func serverCard(_ s: EmbyServer) -> some View {
        let isCurrent = s.id == appState.currentServer?.id
        let hasCred = appState.hasCredentials(s)

        return NavigationLink {
            if hasCred {
                LibraryTabView(server: s)
            } else {
                LoginView(server: s)
            }
        } label: {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isCurrent ? AppTheme.accent.opacity(0.22) : AppTheme.elevated)
                    Image(systemName: "server.rack")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(isCurrent ? AppTheme.accent : AppTheme.textSecondary)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(s.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)
                        if isCurrent {
                            Text("使用中")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(AppTheme.success))
                        } else if !hasCred {
                            Text("未登录")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(AppTheme.warning)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(AppTheme.elevated))
                        }
                    }
                    Text(s.url)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                    Text(hasCred ? "已登录 · 点击浏览媒体库" : "点击登录该服务器")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isCurrent ? AppTheme.accent.opacity(0.45) : AppTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !isCurrent, hasCred {
                Button {
                    Task { await appState.switchTo(s) }
                } label: {
                    Label("设为当前服务器", systemImage: "checkmark.circle")
                }
            }
            Button(role: .destructive) {
                appState.removeServer(s)
            } label: {
                Label("删除服务器", systemImage: "trash")
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: 添加卡片

    private var addCard: some View {
        Button { showAddSheet = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                Text("添加服务器")
                    .font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(AppTheme.accent)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AppTheme.accent.opacity(0.5),
                                  style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "server.rack")
                .font(.system(size: 40))
                .foregroundStyle(AppTheme.textTertiary)
            Text("还没有添加服务器")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
            Text("点下方「添加服务器」，输入 Emby 地址开始")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
}
