//
//  DanmakuAPI.swift
//  EmbyDanmaku
//
//  弹弹play 开放弹幕网络 API v2 客户端。
//  签名算法：base64(sha256(AppId + Timestamp + Path + AppSecret))
//  参考 https://doc.dandanplay.com/open/
//
//  说明：任何与弹弹play 接口规范兼容的第三方/自建服务器，
//  都可以把地址填进「设置 → 弹幕 API 地址」直接使用。
//

import Foundation
import CryptoKit

// MARK: - 返回模型

struct AnimeSearchResult: Codable, Identifiable, Hashable {
    var id: Int { animeId }
    let animeId: Int
    let animeTitle: String
    let type: String?
    let typeDescription: String?
    let imageUrl: String?
    let startDate: String?
    let rating: Double?
    let isFavorited: Bool?
    let searchMatchedText: String?
    let eps: Int?
}

struct AnimeSearchResponse: Codable {
    let success: Bool?
    let errorCode: Int?
    let errorMessage: String?
    let animes: [AnimeSearchResult]?
}

struct EpisodeSearchResult: Codable, Identifiable, Hashable {
    var id: Int64 { episodeId }
    let episodeId: Int64
    let animeTitle: String?
    let episodeTitle: String?
}

struct EpisodeSearchResponse: Codable {
    let success: Bool?
    let errorCode: Int?
    let errorMessage: String?
    let episodes: [EpisodeSearchResult]?
}

struct MatchResult: Codable, Identifiable, Hashable {
    var id: Int64 { episodeId }
    let episodeId: Int64
    let animeTitle: String?
    let episodeTitle: String?
}

struct MatchResponse: Codable {
    let success: Bool?
    let errorCode: Int?
    let errorMessage: String?
    let isMatched: Bool?
    let matches: [MatchResult]?
}

/// 弹弹play 弹幕返回：{ "comments": [ { "p": "1.2,1,25,16777215,1538999075,0,hash,id", "m": "文本" } ] }
struct CommentResponse: Codable {
    let success: Bool?
    let errorCode: Int?
    let errorMessage: String?
    let count: Int?
    let comments: [RawComment]?
}

struct RawComment: Codable {
    /// 逗号分隔：时间,模式,字号,颜色,时间戳,弹幕池,用户Hash,弹幕ID
    let p: String
    /// 弹幕内容
    let m: String
}

struct BangumiResponse: Codable {
    let success: Bool?
    let errorCode: Int?
    let errorMessage: String?
    let bangumi: BangumiDetail?
}

struct BangumiDetail: Codable {
    let animeTitle: String?
    let imageUrl: String?
    let episodes: [BangumiEpisode]?
}

struct BangumiEpisode: Codable, Identifiable, Hashable {
    var id: Int64 { episodeId }
    let episodeId: Int64
    let episodeTitle: String?
}

// MARK: - 客户端

enum DanmakuAPIError: LocalizedError {
    case notConfigured
    case invalidURL
    case httpError(Int, String?)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "尚未配置弹幕服务（设置 → 弹幕）"
        case .invalidURL: return "弹幕服务地址无效"
        case .httpError(let c, let m): return "弹幕服务返回 \(c)\(m.map { "：" + $0 } ?? "")"
        case .serverError(let m): return m
        }
    }
}

final class DanmakuAPI {

    var baseURL: String
    var appId: String
    var appSecret: String

    init(baseURL: String = "https://api.dandanplay.net", appId: String = "", appSecret: String = "") {
        self.baseURL = baseURL
        self.appId = appId
        self.appSecret = appSecret
    }

    /// 从全局设置构造
    convenience init(settings: AppSettings) {
        self.init(baseURL: settings.danmakuAPIBase,
                  appId: settings.dandanAppId,
                  appSecret: settings.dandanAppSecret)
    }

    // MARK: - 签名

    /// base64(sha256(AppId + Timestamp + Path + AppSecret))
    func signature(timestamp: Int64, path: String) -> String {
        let raw = "\(appId)\(timestamp)\(path)\(appSecret)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return Data(digest).base64EncodedString()
    }

    private func request(path: String, query: [URLQueryItem] = []) throws -> URLRequest {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var comps = URLComponents(string: trimmedBase + path) else { throw DanmakuAPIError.invalidURL }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw DanmakuAPIError.invalidURL }

        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if !appId.isEmpty {
            let ts = Int64(Date().timeIntervalSince1970)
            req.setValue(appId, forHTTPHeaderField: "X-AppId")
            req.setValue(String(ts), forHTTPHeaderField: "X-Timestamp")
            req.setValue(signature(timestamp: ts, path: path), forHTTPHeaderField: "X-Signature")
        }
        return req
    }

    private func send<T: Decodable>(_ req: URLRequest, as type: T.Type) async throws -> T {
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8)
            throw DanmakuAPIError.httpError(http.statusCode, body)
        }
        let decoded = try? JSONDecoder().decode(T.self, from: data)
        guard let decoded else {
            throw DanmakuAPIError.serverError("弹幕返回数据无法解析")
        }
        // 业务层错误（HTTP 200 但 success=false）
        let mirror = Mirror(reflecting: decoded)
        for child in mirror.children where child.label == "errorMessage" {
            if let msg = child.value as? String, !msg.isEmpty {
                for c2 in mirror.children where c2.label == "success" {
                    if let ok = c2.value as? Bool, !ok {
                        throw DanmakuAPIError.serverError(msg)
                    }
                }
            }
        }
        return decoded
    }

    // MARK: - 接口

    /// 按关键字搜索番剧
    func searchAnime(keyword: String) async throws -> [AnimeSearchResult] {
        let req = try request(path: "/api/v2/search/anime",
                               query: [URLQueryItem(name: "keyword", value: keyword),
                                       URLQueryItem(name: "v2", value: "true")])
        let r: AnimeSearchResponse = try await send(req, as: AnimeSearchResponse.self)
        return r.animes ?? []
    }

    /// 按关键字搜索节目（可直接得到 episodeId）
    func searchEpisodes(keyword: String) async throws -> [EpisodeSearchResult] {
        let req = try request(path: "/api/v2/search/episodes",
                               query: [URLQueryItem(name: "anime", value: keyword),
                                       URLQueryItem(name: "v2", value: "true")])
        let r: EpisodeSearchResponse = try await send(req, as: EpisodeSearchResponse.self)
        return r.episodes ?? []
    }

    /// 文件识别：用文件名 + 前 16MB 的 MD5 匹配
    func match(fileName: String, fileHash: String? = nil, fileSize: Int64? = nil, duration: Double? = nil) async throws -> [MatchResult] {
        struct Body: Encodable {
            let fileName: String
            let fileHash: String?
            let fileSize: Int64?
            let videoDuration: Double?
            let matchMode: String
        }
        var req = try request(path: "/api/v2/match")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(Body(fileName: fileName,
                                                     fileHash: fileHash,
                                                     fileSize: fileSize,
                                                     videoDuration: duration,
                                                     matchMode: "hashAndFileName"))
        let r: MatchResponse = try await send(req, as: MatchResponse.self)
        return r.matches ?? []
    }

    /// 获取某个弹幕库的全部弹幕
    func comments(episodeId: Int64, withRelated: Bool = true) async throws -> [DanmakuItem] {
        let path = "/api/v2/comment/\(episodeId)"
        let req = try request(path: path,
                              query: [URLQueryItem(name: "withRelated", value: withRelated ? "true" : "false")])
        let r: CommentResponse = try await send(req, as: CommentResponse.self)
        let raws = r.comments ?? []
        return DanmakuParser.parse(rawComments: raws)
    }

    /// 番剧详情（含分集列表，便于手动选集）
    func bangumi(animeId: Int) async throws -> BangumiDetail? {
        let req = try request(path: "/api/v2/bangumi/\(animeId)")
        let r: BangumiResponse = try await send(req, as: BangumiResponse.self)
        return r.bangumi
    }

    /// 发送弹幕（需要应用权限，未开放时返回错误但不影响播放）
    func postComment(episodeId: Int64, text: String, time: Double, color: Int = 0xFFFFFF, mode: DanmakuMode = .scroll) async throws {
        struct Body: Encodable {
            let time: Double
            let mode: Int
            let color: Int
            let comment: String
        }
        var req = try request(path: "/api/v2/comment/\(episodeId)/app")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(Body(time: time, mode: mode.rawValue, color: color, comment: text))
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8)
            throw DanmakuAPIError.httpError(http.statusCode, body)
        }
    }
}
