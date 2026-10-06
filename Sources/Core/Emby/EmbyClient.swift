//
//  EmbyClient.swift
//  EmbyDanmaku
//
//  Emby REST API 客户端。负责认证、媒体库浏览、搜索、播放地址构造与播放进度上报。
//  所有接口使用 async/await。
//

import Foundation
import UIKit

// MARK: - 设备能力描述（用于告知服务器能否直连/直串）

/// AVPlayer 在本机可原生解码的能力集合
enum DeviceCapability {
    /// 可直接播放的容器
    static let containers = ["mp4", "m4v", "mov"]
    /// 可直接播放的视频编码
    static let videoCodecs = ["h264", "hevc", "mpeg4", "av1"]
    /// 可直接播放的音频编码（DTS / TrueHD 等不支持）
    static let audioCodecs = ["aac", "mp3", "ac3", "eac3", "alac", "flac", "opus", "mp2"]
    /// 可自行渲染的文本字幕（其余交给服务器转码烧录）
    static let textSubtitleCodecs = ["srt", "subrip", "ass", "ssa", "vtt", "webvtt", "smi", "pgssub"]
}

final class EmbyClient {

    // MARK: - 属性

    private(set) var serverURL: String
    private(set) var accessToken: String?
    private(set) var userId: String?
    private(set) var serverId: String?
    private(set) var userName: String?

    let deviceId: String
    let clientName = "EmbyDanmaku"
    let clientVersion = "1.0.0"
    let deviceName: String

    private let session: URLSession
    private let decoder: JSONDecoder

    init(serverURL: String) {
        self.serverURL = EmbyServer.normalize(serverURL)
        self.deviceName = UIDevice.current.model
        self.deviceId = EmbyClient.persistentDeviceId()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.httpMaximumConnectionsPerHost = 6
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config, delegate: nil, delegateQueue: nil)

        let d = JSONDecoder()
        d.keyDecodingStrategy = .useDefaultKeys
        self.decoder = d
    }

    private static func persistentDeviceId() -> String {
        let key = "EmbyDanmaku.deviceId"
        if let saved = UserDefaults.standard.string(forKey: key) { return saved }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    // MARK: - 凭据注入

    func setCredentials(token: String, userId: String, serverId: String?, userName: String?) {
        self.accessToken = token
        self.userId = userId
        self.serverId = serverId
        self.userName = userName
    }

    func clearCredentials() {
        accessToken = nil
        userId = nil
        serverId = nil
        userName = nil
    }

    var isAuthenticated: Bool { accessToken != nil && userId != nil }

    // MARK: - 请求头

    /// Emby 要求登录请求与已登录请求使用不同的 Authorization 格式
    private func authorizationHeader() -> String {
        if let token = accessToken, let uid = userId {
            return "Emby UserId=\"\(uid)\", Client=\"\(clientName)\", Device=\"\(deviceName)\", DeviceId=\"\(deviceId)\", Version=\"\(clientVersion)\", Token=\"\(token)\""
        }
        return "Emby Client=\"\(clientName)\", Device=\"\(deviceName)\", DeviceId=\"\(deviceId)\", Version=\"\(clientVersion)\""
    }

    /// 构造带鉴权头的 GET 请求（EmbyPlayback 的 Reporter 也需要用）
    func request(path: String, query: [String: String] = [:]) throws -> URLRequest {
        guard var comps = URLComponents(string: serverURL + path) else { throw EmbyError.invalidURL }
        var items: [URLQueryItem] = comps.queryItems ?? []
        for (k, v) in query where !v.isEmpty {
            items.append(URLQueryItem(name: k, value: v))
        }
        if !items.isEmpty { comps.queryItems = items }
        guard let url = comps.url else { throw EmbyError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(authorizationHeader(), forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = accessToken {
            req.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        }
        return req
    }

    func send(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw EmbyError.badStatus(-1, "无响应") }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw EmbyError.badStatus(http.statusCode, body)
        }
        return (data, http)
    }

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:], as type: T.Type = T.self) async throws -> T {
        let req = try request(path: path, query: query)
        let (data, _) = try await send(req)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw EmbyError.decoding(EmbyError.decodeFailure(error, data: data))
        }
    }

    func post<T: Decodable, B: Encodable>(_ path: String, body: B, query: [String: String] = [:], as type: T.Type = T.self) async throws -> T {
        var req = try request(path: path, query: query)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, _) = try await send(req)
        do { return try decoder.decode(T.self, from: data) } catch { throw EmbyError.decoding(EmbyError.decodeFailure(error, data: data)) }
    }

    private func postNoResult<B: Encodable>(_ path: String, body: B) async throws {
        var req = try request(path: path)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        _ = try await send(req)
    }

    private func delete(_ path: String) async throws {
        var req = try request(path: path)
        req.httpMethod = "DELETE"
        _ = try await send(req)
    }

    // MARK: - 服务器探测与认证

    func fetchPublicInfo() async throws -> PublicSystemInfo {
        try await get("/emby/System/Info/Public", as: PublicSystemInfo.self)
    }

    /// 用户名 + 密码登录（Pw 可为明文，Emby 不强制哈希）
    @discardableResult
    func login(username: String, password: String) async throws -> AuthResult {
        struct Body: Encodable { let Username: String; let Pw: String }
        let result: AuthResult = try await post("/emby/Users/AuthenticateByName", body: Body(Username: username, Pw: password))
        guard let token = result.AccessToken, let uid = result.User?.Id ?? result.SessionInfo?.UserId else {
            throw EmbyError.badStatus(401, "服务器未返回访问令牌")
        }
        self.accessToken = token
        self.userId = uid
        self.serverId = result.ServerId ?? result.SessionInfo?.ServerId
        self.userName = result.User?.Name ?? username
        return result
    }

    /// 已保存的用户列表（用于快速切换账号，头像墙登录）
    func fetchPublicUsers() async throws -> [UserDto] {
        try await get("/emby/Users/Public", as: [UserDto].self)
    }

    // MARK: - 媒体库浏览

    func fetchViews() async throws -> [BaseItem] {
        guard let uid = userId else { throw EmbyError.notAuthenticated }
        let r: ItemsResult = try await get("/emby/Users/\(uid)/Views")
        return r.Items ?? []
    }

    /// 通用条目查询
    func fetchItems(parentId: String? = nil,
                    includeItemTypes: [String]? = nil,
                    recursive: Bool = true,
                    sortBy: [String] = ["SortName"],
                    sortOrder: String = "Ascending",
                    startIndex: Int = 0,
                    limit: Int = 200,
                    filters: [String]? = nil,
                    searchTerm: String? = nil,
                    fields: String = "PrimaryImageAspectRatio,UserData,Overview,MediaSources,ChildCount") async throws -> ItemsResult {
        guard let uid = userId else { throw EmbyError.notAuthenticated }
        var q: [String: String] = [
            "UserId": uid,
            "Recursive": String(recursive),
            "StartIndex": String(startIndex),
            "Limit": String(limit),
            "SortBy": sortBy.joined(separator: ","),
            "SortOrder": sortOrder,
            "Fields": fields,
            "ImageTypeLimit": "1",
            "EnableImageTypes": "Primary,Backdrop,Thumb"
        ]
        if let parentId { q["ParentId"] = parentId }
        if let types = includeItemTypes, !types.isEmpty { q["IncludeItemTypes"] = types.joined(separator: ",") }
        if let f = filters, !f.isEmpty { q["Filters"] = f.joined(separator: ",") }
        if let s = searchTerm, !s.isEmpty { q["SearchTerm"] = s }
        return try await get("/emby/Users/\(uid)/Items", query: q, as: ItemsResult.self)
    }

    func fetchItem(_ id: String) async throws -> BaseItem {
        guard let uid = userId else { throw EmbyError.notAuthenticated }
        return try await get("/emby/Users/\(uid)/Items/\(id)",
                             query: ["Fields": "PrimaryImageAspectRatio,UserData,Overview,MediaSources,MediaStreams,People,Genres,ChildCount"],
                             as: BaseItem.self)
    }

    func fetchSeasons(seriesId: String) async throws -> [BaseItem] {
        guard let uid = userId else { throw EmbyError.notAuthenticated }
        let r: ItemsResult = try await get("/emby/Shows/\(seriesId)/Seasons",
                                           query: ["UserId": uid, "Fields": "PrimaryImageAspectRatio,UserData,ChildCount", "EnableImageTypes": "Primary"])
        return r.Items ?? []
    }

    func fetchEpisodes(seriesId: String, seasonId: String? = nil) async throws -> [BaseItem] {
        guard let uid = userId else { throw EmbyError.notAuthenticated }
        var q: [String: String] = ["UserId": uid,
                                   "Fields": "PrimaryImageAspectRatio,UserData,Overview,MediaSources",
                                   "EnableImageTypes": "Primary"]
        if let seasonId { q["SeasonId"] = seasonId }
        let r: ItemsResult = try await get("/emby/Shows/\(seriesId)/Episodes", query: q, as: ItemsResult.self)
        return (r.Items ?? []).sorted { (a, b) in
            let as_ = a.ParentIndexNumber ?? 0, bs = b.ParentIndexNumber ?? 0
            if as_ != bs { return as_ < bs }
            return (a.IndexNumber ?? 0) < (b.IndexNumber ?? 0)
        }
    }

    /// 「继续观看」
    func fetchResume(limit: Int = 24) async throws -> [BaseItem] {
        guard let uid = userId else { throw EmbyError.notAuthenticated }
        let r: ItemsResult = try await get("/emby/Users/\(uid)/Items/Resume",
                                           query: ["Limit": String(limit),
                                                   "Fields": "PrimaryImageAspectRatio,UserData,Overview",
                                                   "MediaTypes": "Video",
                                                   "EnableImageTypes": "Primary,Backdrop"])
        return r.Items ?? []
    }

    /// 最近加入
    func fetchLatest(parentId: String? = nil, limit: Int = 24) async throws -> [BaseItem] {
        guard let uid = userId else { throw EmbyError.notAuthenticated }
        var q: [String: String] = ["UserId": uid, "Limit": String(limit),
                                   "Fields": "PrimaryImageAspectRatio,UserData,Overview",
                                   "EnableImageTypes": "Primary,Backdrop"]
        if let parentId { q["ParentId"] = parentId }
        let r: ItemsResult = try await get("/emby/Users/\(uid)/Items/Latest", query: q, as: ItemsResult.self)
        return r.Items ?? []
    }

    func search(term: String, types: [String] = ["Movie", "Series", "Episode"], limit: Int = 60) async throws -> [BaseItem] {
        guard let uid = userId else { throw EmbyError.notAuthenticated }
        let r: ItemsResult = try await get("/emby/Users/\(uid)/Items",
                                           query: ["SearchTerm": term,
                                                   "IncludeItemTypes": types.joined(separator: ","),
                                                   "Recursive": "true",
                                                   "Limit": String(limit),
                                                   "Fields": "PrimaryImageAspectRatio,UserData,Overview",
                                                   "EnableImageTypes": "Primary"])
        return r.Items ?? []
    }

    // MARK: - 图片

    /// Emby 图片地址。图片接口无需鉴权头，用 api_key 查询参数即可，方便交给 AsyncImage / Kingfisher 这类图片库。
    func imageURL(itemId: String, imageType: String = "Primary", tag: String? = nil, maxWidth: Int = 500, quality: Int = 90) -> URL? {
        guard let token = accessToken else { return nil }
        var comps = URLComponents(string: serverURL + "/emby/Items/\(itemId)/Images/\(imageType)")
        var items = [URLQueryItem(name: "api_key", value: token)]
        if let tag, !tag.isEmpty { items.append(URLQueryItem(name: "tag", value: tag)) }
        items.append(URLQueryItem(name: "maxWidth", value: String(maxWidth)))
        items.append(URLQueryItem(name: "quality", value: String(quality)))
        comps?.queryItems = items
        return comps?.url
    }

    func backdropURL(itemId: String, tag: String? = nil, maxWidth: Int = 1920) -> URL? {
        imageURL(itemId: itemId, imageType: "Backdrop", tag: tag, maxWidth: maxWidth, quality: 85)
    }

    // MARK: - 播放地址

    /// 构造直连（DirectStream）地址
    func directStreamURL(itemId: String, mediaSourceId: String, container: String?) -> URL? {
        guard let token = accessToken else { return nil }
        let cont = (container ?? "mp4").lowercased()
        let safe = DeviceCapability.containers.contains(cont) ? cont : "mp4"
        var comps = URLComponents(string: serverURL + "/emby/Videos/\(itemId)/stream.\(safe)")
        comps?.queryItems = [
            URLQueryItem(name: "api_key", value: token),
            URLQueryItem(name: "Static", value: "true"),
            URLQueryItem(name: "MediaSourceId", value: mediaSourceId),
            URLQueryItem(name: "DeviceId", value: deviceId)
        ]
        return comps?.url
    }

    /// 构造转码（HLS）地址。transcodingPath 来自 PlaybackInfo 返回的 TranscodingUrl，已含查询串。
    func transcodeURL(transcodingPath: String) -> URL? {
        var path = transcodingPath
        if !path.hasPrefix("/") { path = "/" + path }
        // TranscodingUrl 通常已带 api_key，若缺失则补上
        if let token = accessToken, !path.contains("api_key") {
            path += (path.contains("?") ? "&" : "?") + "api_key=" + token
        }
        return URL(string: serverURL + path)
    }

    // MARK: - 媒体操作

    func markPlayed(_ itemId: String) async throws {
        guard let uid = userId else { throw EmbyError.notAuthenticated }
        try await postNoResult("/emby/Users/\(uid)/PlayedItems/\(itemId)", body: EmptyBody())
    }

    func markUnplayed(_ itemId: String) async throws {
        guard let uid = userId else { throw EmbyError.notAuthenticated }
        try await delete("/emby/Users/\(uid)/PlayedItems/\(itemId)")
    }

    func setFavorite(_ itemId: String, favorite: Bool) async throws {
        guard let uid = userId else { throw EmbyError.notAuthenticated }
        if favorite {
            try await postNoResult("/emby/Users/\(uid)/FavoriteItems/\(itemId)", body: EmptyBody())
        } else {
            try await delete("/emby/Users/\(uid)/FavoriteItems/\(itemId)")
        }
    }

    /// 手动更新本地播放进度（用于退出播放时兜底写入）
    func updateUserData(_ itemId: String, positionTicks: Int64) async throws {
        guard let uid = userId else { throw EmbyError.notAuthenticated }
        struct Body: Encodable { let PlaybackPositionTicks: Int64 }
        try await postNoResult("/emby/Users/\(uid)/Items/\(itemId)/UserData", body: Body(PlaybackPositionTicks: positionTicks))
    }
}

struct EmptyBody: Encodable {}
