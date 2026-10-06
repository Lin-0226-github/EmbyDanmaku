//
//  AppState.swift
//  EmbyDanmaku
//
//  全局应用状态：服务器列表、登录会话、凭据持久化。
//

import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {

    @Published private(set) var servers: [EmbyServer] = []
    @Published private(set) var client: EmbyClient?
    @Published private(set) var currentServer: EmbyServer?
    @Published private(set) var isLoggedIn: Bool = false
    @Published private(set) var isConnecting: Bool = false
    @Published var errorMessage: String?
    @Published var currentUserName: String?

    private let serversKey = "EmbyDanmaku.servers"

    init() {
        loadServers()
    }

    // MARK: - 服务器列表

    private func loadServers() {
        guard let data = UserDefaults.standard.data(forKey: serversKey),
              let list = try? JSONDecoder().decode([EmbyServer].self, from: data) else { return }
        servers = list
    }

    private func persistServers() {
        if let data = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(data, forKey: serversKey)
        }
    }

    func addServer(url raw: String, name: String? = nil) async {
        let normalized = EmbyServer.normalize(raw)
        guard !normalized.isEmpty else {
            errorMessage = "请输入服务器地址"
            return
        }
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }

        do {
            let probe = EmbyClient(serverURL: normalized)
            let info = try await probe.fetchPublicInfo()
            let server = EmbyServer(url: normalized,
                                    name: name ?? info.ServerName ?? normalized,
                                    lastUsername: nil,
                                    lastUserId: nil)
            if let idx = servers.firstIndex(where: { $0.url.lowercased() == normalized.lowercased() }) {
                var existing = servers[idx]
                existing.name = server.name
                servers[idx] = existing
            } else {
                servers.append(server)
            }
            persistServers()
        } catch {
            if error.isCancellation { return }
            errorMessage = "无法连接服务器：\(error.localizedDescription)"
        }
    }

    func removeServer(_ server: EmbyServer) {
        if let token = client?.accessToken, let uid = client?.userId {
            try? Keychain.delete(account: Keychain.tokenKey(serverURL: server.url, userId: uid))
        }
        servers.removeAll { $0.id == server.id }
        persistServers()
        if currentServer?.id == server.id {
            logout()
        }
    }

    // MARK: - 登录

    /// 启动时尝试用已保存的令牌自动恢复会话
    func restoreSession() async {
        for server in servers {
            guard let uid = server.lastUserId, !uid.isEmpty,
                  let token = try? Keychain.read(account: Keychain.tokenKey(serverURL: server.url, userId: uid)) else { continue }
            let c = EmbyClient(serverURL: server.url)
            c.setCredentials(token: token, userId: uid, serverId: nil, userName: server.lastUsername)
            // 用一次轻量请求验证令牌是否仍然有效
            do {
                _ = try await c.fetchViews()
                self.client = c
                self.currentServer = server
                self.isLoggedIn = true
                self.currentUserName = server.lastUsername
                return
            } catch {
                try? Keychain.delete(account: Keychain.tokenKey(serverURL: server.url, userId: uid))
            }
        }
    }

    func login(server: EmbyServer, username: String, password: String, rememberPassword: Bool) async {
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }

        let c = EmbyClient(serverURL: server.url)
        do {
            let result = try await c.login(username: username, password: password)
            guard let uid = c.userId, let token = c.accessToken else {
                errorMessage = "登录失败：服务器未返回用户标识"
                return
            }
            try? Keychain.save(token, account: Keychain.tokenKey(serverURL: server.url, userId: uid))
            if rememberPassword {
                try? Keychain.save(password, account: Keychain.passwordKey(serverURL: server.url, username: username))
            }

            var updated = server
            updated.lastUsername = username
            updated.lastUserId = uid
            if let idx = servers.firstIndex(where: { $0.id == server.id }) {
                servers[idx] = updated
            } else {
                servers.append(updated)
            }
            persistServers()

            self.client = c
            self.currentServer = updated
            self.currentUserName = result.User?.Name ?? username
            self.isLoggedIn = true
        } catch {
            if error.isCancellation { return }
            errorMessage = "登录失败：\(error.localizedDescription)"
        }
    }

    /// 该服务器是否有保存过密码（快速登录用）
    func savedPassword(server: EmbyServer, username: String) -> String? {
        try? Keychain.read(account: Keychain.passwordKey(serverURL: server.url, username: username))
    }

    func logout() {
        if let c = client, let uid = c.userId, let url = currentServer?.url {
            try? Keychain.delete(account: Keychain.tokenKey(serverURL: url, userId: uid))
        }
        client?.clearCredentials()
        client = nil
        currentServer = nil
        currentUserName = nil
        isLoggedIn = false
    }

    /// 切换服务器（退出当前会话，回到服务器列表）
    func switchServer() {
        client?.clearCredentials()
        client = nil
        currentServer = nil
        isLoggedIn = false
    }
}
