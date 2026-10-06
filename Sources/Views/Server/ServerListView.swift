//
//  ServerListView.swift
//  EmbyDanmaku
//
//  服务器管理：添加、选择、删除 Emby 服务器。
//

import SwiftUI

struct ServerListView: View {
    @EnvironmentObject private var appState: AppState
    @State private var newURL = ""
    @State private var showAddSheet = false

    var body: some View {
        NavigationView {
            Group {
                if appState.servers.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            ForEach(appState.servers) { server in
                                NavigationLink {
                                    LoginView(server: server)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "server.rack")
                                            .font(.title3)
                                            .foregroundStyle(Color.accentColor)
                                            .frame(width: 34)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(server.name)
                                                .font(.body.weight(.medium))
                                            Text(server.url)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                            .onDelete { idx in
                                for i in idx { appState.removeServer(appState.servers[i]) }
                            }
                        } header: {
                            Text("已保存的服务器")
                        } footer: {
                            Text("地址格式示例：http://192.168.1.10:8096 或 https://emby.example.com")
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Emby 服务器")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddServerSheet { url in
                    Task { await appState.addServer(url: url) }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if appState.isConnecting {
                    HStack {
                        ProgressView()
                        Text("正在连接…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(.bar, in: Capsule())
                    .padding(.bottom, 8)
                }
            }
            .alert("出错了", isPresented: errorBinding) {
                Button("好", role: .cancel) { appState.errorMessage = nil }
            } message: {
                Text(appState.errorMessage ?? "")
            }
        }
        .navigationViewStyle(.stack)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "server.rack")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("还没有添加服务器")
                .font(.headline)
            Text("输入你的 Emby 服务器地址即可开始")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                showAddSheet = true
            } label: {
                Label("添加服务器", systemImage: "plus")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { appState.errorMessage != nil },
                set: { if !$0 { appState.errorMessage = nil } })
    }
}

// MARK: - 添加服务器

struct AddServerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    var onAdd: (String) -> Void

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("http://192.168.1.10:8096", text: $text)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                } header: {
                    Text("服务器地址")
                } footer: {
                    Text("可以是局域网地址，也可以是已配置好 HTTPS 的公网域名。")
                }
                Section {
                    Button("快速填入局域网示例") { text = "http://192.168.1.10:8096" }
                    Button("快速填入本地示例") { text = "http://localhost:8096" }
                }
            }
            .navigationTitle("添加服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        onAdd(text)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
