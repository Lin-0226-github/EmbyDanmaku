//
//  LoginView.swift
//  EmbyDanmaku
//
//  账号登录：用户名 + 密码，支持已保存用户快速登录。
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    let server: EmbyServer

    @State private var username = ""
    @State private var password = ""
    @State private var rememberPassword = true
    @State private var publicUsers: [UserDto] = []
    @State private var isLoadingUsers = false
    @FocusState private var focusedField: Field?

    private enum Field { case username, password }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.name)
                            .font(.body.weight(.medium))
                        Text(server.url)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } header: {
                Text("服务器")
            }

            if !publicUsers.isEmpty {
                Section("选择用户") {
                    ForEach(publicUsers, id: \.Id) { user in
                        Button {
                            username = user.Name ?? ""
                            focusedField = .password
                        } label: {
                            HStack(spacing: 10) {
                                if let tag = user.PrimaryImageTag,
                                   let url = URL(string: "\(server.url)/emby/Users/\(user.Id ?? "")/Images/Primary?tag=\(tag)&maxWidth=120") {
                                    RemoteImageView(url: url, placeholderSystemImage: "person.circle")
                                        .frame(width: 36, height: 36)
                                        .clipShape(Circle())
                                } else {
                                    Image(systemName: "person.circle.fill")
                                        .font(.system(size: 32))
                                        .foregroundStyle(.secondary)
                                }
                                Text(user.Name ?? "未命名用户")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if username == user.Name {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }

            Section {
                TextField("用户名", text: $username)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .focused($focusedField, equals: .username)
                    .submitLabel(.next)
                SecureField("密码", text: $password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { submit() }
                Toggle("记住密码", isOn: $rememberPassword)
            } header: {
                Text("凭据")
            } footer: {
                Text("密码保存在系统钥匙串中，不会上传。")
            }

            Section {
                Button {
                    submit()
                } label: {
                    HStack {
                        Spacer()
                        if appState.isConnecting {
                            ProgressView()
                        } else {
                            Text("登录")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(username.isEmpty || appState.isConnecting)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("登录")
        .task {
            username = server.lastUsername ?? ""
            if let saved = appState.savedPassword(server: server, username: username), !saved.isEmpty {
                password = saved
            }
            await loadUsers()
        }
        .alert("出错了", isPresented: Binding(get: { appState.errorMessage != nil },
                                              set: { if !$0 { appState.errorMessage = nil } })) {
            Button("好", role: .cancel) { appState.errorMessage = nil }
        } message: {
            Text(appState.errorMessage ?? "")
        }
    }

    private func submit() {
        focusedField = nil
        Task { await appState.login(server: server, username: username, password: password, rememberPassword: rememberPassword) }
    }

    private func loadUsers() async {
        isLoadingUsers = true
        defer { isLoadingUsers = false }
        let c = EmbyClient(serverURL: server.url)
        publicUsers = (try? await c.fetchPublicUsers()) ?? []
    }
}
