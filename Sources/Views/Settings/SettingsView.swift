//
//  SettingsView.swift
//  EmbyDanmaku
//
//  应用设置：弹幕服务、播放偏好、服务器与账户。
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: AppSettings

    @State private var showLogoutConfirm = false

    private let bitrateOptions: [(String, Int)] = [
        ("自动（60 Mbps）", 60_000_000),
        ("40 Mbps", 40_000_000),
        ("20 Mbps", 20_000_000),
        ("10 Mbps", 10_000_000),
        ("4 Mbps", 4_000_000),
        ("2 Mbps", 2_000_000)
    ]

    var body: some View {
        NavigationView {
            Form {
                Section {
                    NavigationLink {
                        DanmakuSourceSettings()
                    } label: {
                        Label {
                            HStack {
                                Text("弹幕服务")
                                Spacer()
                                Text(settings.danmakuSourceConfigured ? "已配置" : "未配置")
                                    .font(.caption)
                                    .foregroundStyle(settings.danmakuSourceConfigured ? .green : .orange)
                            }
                        } icon: {
                            Image(systemName: "text.bubble")
                        }
                    }
                } header: {
                    Text("弹幕")
                } footer: {
                    Text("弹幕数据来自弹弹play 开放弹幕网络，需要自行申请 AppId / AppSecret；也可填写兼容的自建服务地址。")
                }

                Section("播放") {
                    Picker("转码码率上限", selection: $settings.maxBitrate) {
                        ForEach(bitrateOptions, id: \.1) { t in
                            Text(t.0).tag(t.1)
                        }
                    }
                    Toggle("优先直连播放", isOn: $settings.preferDirectPlay)
                    Toggle("自动从上次进度续播", isOn: $settings.autoResume)
                    Toggle("手势控制（亮度/音量/快进）", isOn: $settings.gesturesEnabled)
                    Toggle("后台继续播放", isOn: $settings.backgroundPlayback)
                }

                Section("字幕") {
                    Stepper(value: $settings.subtitleSize, in: 14...36, step: 1) {
                        Text("默认字号 \(Int(settings.subtitleSize))")
                    }
                }

                Section("定时关闭") {
                    Picker("默认时长", selection: $settings.defaultSleepMinutes) {
                        Text("不启用").tag(0)
                        ForEach(SleepTimer.presets, id: \.self) { m in
                            Text("\(m) 分钟").tag(m)
                        }
                    }
                }

                Section("账户") {
                    if let s = appState.currentServer {
                        LabeledRow("服务器") { Text(s.name).foregroundStyle(.secondary) }
                        LabeledRow("地址") { Text(s.url).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        if let u = appState.currentUserName {
                            LabeledRow("用户") { Text(u).foregroundStyle(.secondary) }
                        }
                    }
                    Button("切换到其他服务器") { appState.switchServer() }
                    Button("退出登录", role: .destructive) { showLogoutConfirm = true }
                }

                Section("关于") {
                    LabeledRow("版本") { Text("1.0.0").foregroundStyle(.secondary) }
                    Link("弹弹play 开放弹幕网络", destination: URL(string: "https://www.dandanplay.com/open.html")!)
                }
            }
            .navigationTitle("设置")
            .confirmationDialog("确定退出登录？", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                Button("退出登录", role: .destructive) { appState.logout() }
                Button("取消", role: .cancel) { }
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - 弹幕服务设置

struct DanmakuSourceSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var showSecret = false

    var body: some View {
        Form {
            Section {
                TextField("https://api.dandanplay.net", text: $settings.danmakuAPIBase)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            } header: {
                Text("弹幕 API 地址")
            } footer: {
                Text("任何兼容弹弹play v2 接口规范的服务器都可以填在这里。留空表示仅使用本地弹幕文件。")
            }

            Section {
                TextField("AppId", text: $settings.dandanAppId)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                HStack {
                    if showSecret {
                        TextField("AppSecret", text: $settings.dandanAppSecret)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    } else {
                        SecureField("AppSecret", text: $settings.dandanAppSecret)
                    }
                    Button {
                        showSecret.toggle()
                    } label: {
                        Image(systemName: showSecret ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("凭证")
            } footer: {
                Text("在弹弹play 开发者中心注册并创建应用后获得。凭证仅保存在本机。")
            }

            Section {
                Toggle("播放时自动匹配弹幕", isOn: $settings.danmakuAutoMatch)
            }

            Section {
                Button("恢复默认地址") {
                    settings.danmakuAPIBase = "https://api.dandanplay.net"
                }
            }
        }
        .navigationTitle("弹幕服务")
        .navigationBarTitleDisplayMode(.inline)
    }
}
