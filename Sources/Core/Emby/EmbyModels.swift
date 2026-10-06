//
//  EmbyModels.swift
//  EmbyDanmaku
//
//  Emby REST API 数据模型。字段名与 Emby 返回的 JSON 保持一致（大写开头），
//  因此不需要额外的 CodingKeys。
//

import Foundation

// MARK: - 服务器连接

/// 一个已保存的 Emby 服务器（不含凭据，凭据存于 Keychain）
struct EmbyServer: Codable, Identifiable, Hashable {
    var id: String { url.lowercased() }
    /// 服务器根地址，例如 http://192.168.1.10:8096（不要带 /emby 后缀）
    var url: String
    var name: String
    /// 上次登录成功的用户名，用于快速重登
    var lastUsername: String?
    var lastUserId: String?

    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if s.isEmpty { return "" }
        if !s.hasPrefix("http://") && !s.hasPrefix("https://") {
            s = "http://" + s
        }
        return s
    }
}

/// 登录返回
struct AuthResult: Codable {
    let AccessToken: String?
    let ServerId: String?
    let SessionInfo: SessionInfo?
    let User: UserDto?
}

struct SessionInfo: Codable {
    let Id: String?
    let UserId: String?
    let ServerId: String?
}

struct UserDto: Codable {
    let Id: String?
    let Name: String?
    let PrimaryImageTag: String?
    let HasPassword: Bool?
    let Configuration: UserConfiguration?
}

struct UserConfiguration: Codable {
    let AudioLanguagePreference: String?
    let SubtitleLanguagePreference: String?
    let DisplayMissingEpisodes: Bool?
    let SubtitleMode: String?
}

/// 公开服务器信息（用于探测连通性、取服务器名）
struct PublicSystemInfo: Codable {
    let ServerName: String?
    let Version: String?
    let Id: String?
    let OperatingSystem: String?
}

// MARK: - 媒体条目

/// Emby 的 BaseItemDto 的子集，覆盖影音库浏览所需字段
struct BaseItem: Codable, Identifiable, Hashable {
    var id: String { Id }
    let Id: String
    let Name: String?
    let OriginalTitle: String?
    let SortName: String?
    let Overview: String?
    let Type: String?              // Movie / Series / Season / Episode / Folder / CollectionFolder
    let MediaType: String?         // Video / Audio / Photo
    let SeriesName: String?
    let SeasonName: String?
    let SeriesId: String?
    let SeasonId: String?
    let ParentId: String?
    let IndexNumber: Int?          // 集号
    let ParentIndexNumber: Int?    // 季号
    let ProductionYear: Int?
    let PremiereDate: String?
    let EndDate: String?
    let CommunityRating: Double?
    let CriticRating: Double?
    let OfficialRating: String?
    let RunTimeTicks: Int64?
    let Genres: [String]?
    let Studios: [String]?
    let Tags: [String]?
    let People: [EmbyPerson]?
    let ImageTags: [String: String]?
    let BackdropImageTags: [String]?
    let SeriesPrimaryImageTag: String?
    let ParentPrimaryImageItemId: String?
    let ParentBackdropItemId: String?
    let ParentBackdropImageTags: [String]?
    let PrimaryImageAspectRatio: Double?
    let UserData: UserData?
    let ChildCount: Int?
    let RecursiveItemCount: Int?
    let MediaSources: [MediaSource]?
    let MediaStreams: [MediaStream]?
    let CollectionType: String?
    let LocationType: String?
    let DateCreated: String?
    let Taglines: [String]?
    let ExternalUrls: [ExternalUrl]?
    let ProviderIds: [String: String]?

    // MARK: 派生属性

    var isFolder: Bool {
        guard let t = Type else { return false }
        return t == "Folder" || t == "CollectionFolder" || t == "Series" || t == "Season" || t == "BoxSet" || t == "UserView"
    }

    var isMovie: Bool { Type == "Movie" || Type == "Video" }
    var isSeries: Bool { Type == "Series" }
    var isSeason: Bool { Type == "Season" }
    var isEpisode: Bool { Type == "Episode" }
    var isPlayable: Bool { isMovie || isEpisode || Type == "Video" || Type == "TvChannel" || Type == "Program" || Type == "MusicVideo" }

    /// 展示标题：剧集显示 "S1E5 标题"
    var displayTitle: String {
        if isEpisode, let s = ParentIndexNumber, let e = IndexNumber {
            return String(format: "S%02dE%02d %@", s, e, Name ?? "")
        }
        return Name ?? "未知"
    }

    /// 二级标题：剧集显示剧名，电影显示年份
    var subtitleText: String? {
        if isEpisode {
            if let sn = SeasonName, !sn.isEmpty { return sn }
            return SeriesName
        }
        if let y = ProductionYear { return String(y) }
        return nil
    }

    /// 时长（秒）
    var durationSeconds: Double {
        guard let t = RunTimeTicks, t > 0 else { return 0 }
        return Double(t) / 10_000_000.0
    }

    var progress: Double {
        guard let ud = UserData,
              let pos = ud.PlaybackPositionTicks, pos > 0,
              let total = RunTimeTicks, total > 0 else { return 0 }
        return min(1, Double(pos) / Double(total))
    }

    var resumeSeconds: Double {
        guard let pos = UserData?.PlaybackPositionTicks else { return 0 }
        return Double(pos) / 10_000_000.0
    }

    var watched: Bool { UserData?.Played ?? false }

    var primaryImageTag: String? { ImageTags?["Primary"] }
    var backdropImageTag: String? { BackdropImageTags?.first }
}

struct UserData: Codable, Hashable {
    let PlaybackPositionTicks: Int64?
    let PlayCount: Int?
    let IsFavorite: Bool?
    let Played: Bool?
    let LastPlayedDate: String?
    let UnplayedItemCount: Int?
    let PlayedPercentage: Double?
}

struct EmbyPerson: Codable, Hashable, Identifiable {
    var id: String { Id ?? Name ?? UUID().uuidString }
    let Id: String?
    let Name: String?
    let Role: String?
    let Type: String?
    let PrimaryImageTag: String?
}

struct ExternalUrl: Codable, Hashable {
    let Name: String?
    let Url: String?
}

struct ItemsResult: Codable {
    let Items: [BaseItem]?
    let TotalRecordCount: Int?
    let StartIndex: Int?
}

// MARK: - 播放信息

struct PlaybackInfoResponse: Codable {
    let MediaSources: [MediaSource]?
    let PlaySessionId: String?
    let ErrorCode: String?
}

struct MediaSource: Codable, Hashable, Identifiable {
    var id: String { Id }
    let Id: String
    let Name: String?
    let Path: String?
    let Container: String?
    let Size: Int64?
    let Bitrate: Int?
    let RunTimeTicks: Int64?
    let `Protocol`: String?
    let MediaStreams: [MediaStream]?
    let SupportsDirectPlay: Bool?
    let SupportsDirectStream: Bool?
    let SupportsTranscoding: Bool?
    let DirectStreamUrl: String?
    let TranscodingUrl: String?
    let TranscodingSubProtocol: String?
    let TranscodingContainer: String?
    let DefaultAudioStreamIndex: Int?
    let DefaultSubtitleStreamIndex: Int?
    let RequiredHttpHeaders: [String: String]?

    var videoStream: MediaStream? {
        MediaStreams?.first { ($0.Type ?? "") == "Video" }
    }
    var audioStreams: [MediaStream] {
        (MediaStreams ?? []).filter { ($0.Type ?? "") == "Audio" }
    }
    var subtitleStreams: [MediaStream] {
        (MediaStreams ?? []).filter { ($0.Type ?? "") == "Subtitle" }
    }
    var durationSeconds: Double {
        guard let t = RunTimeTicks, t > 0 else { return 0 }
        return Double(t) / 10_000_000.0
    }
}

struct MediaStream: Codable, Hashable, Identifiable {
    var id: Int { Index }
    let Index: Int
    let Type: String?
    let Codec: String?
    let Language: String?
    let DisplayTitle: String?
    let Title: String?
    let Channels: Int?
    let SampleRate: Int?
    let BitRate: Int?
    let Width: Int?
    let Height: Int?
    let IsDefault: Bool?
    let IsForced: Bool?
    let IsExternal: Bool?
    let IsTextSubtitleStream: Bool?
    let SupportsExternalStream: Bool?
    let DeliveryUrl: String?
    let Path: String?
    let CodecTag: String?
    let Profile: String?
    let Level: Double?
    let AverageFrameRate: Double?
    let RealFrameRate: Double?
    let VideoRange: String?

    /// 展示名：优先使用服务器给的 DisplayTitle，否则自己拼一个
    var displayName: String {
        if let d = DisplayTitle, !d.isEmpty { return d }
        var parts: [String] = []
        if let lang = displayLanguage, !lang.isEmpty { parts.append(lang) }
        if let t = Title, !t.isEmpty, t != langName { parts.append(t) }
        if let c = Codec { parts.append(c.uppercased()) }
        if Type == "Audio", let ch = Channels { parts.append(chName(ch)) }
        return parts.isEmpty ? "轨道 \(Index)" : parts.joined(separator: " · ")
    }

    private var langName: String? { Language }

    var displayLanguage: String? {
        guard let l = Language, !l.isEmpty else { return nil }
        let map: [String: String] = [
            "chi": "中文", "zho": "中文", "cmn": "中文", "zh": "中文",
            "eng": "英语", "jpn": "日语", "kor": "韩语",
            "fre": "法语", "fra": "法语", "ger": "德语", "deu": "德语",
            "spa": "西班牙语", "rus": "俄语", "ita": "意大利语",
            "und": "未知", "": "未知"
        ]
        return map[l.lowercased()] ?? l
    }

    private func chName(_ n: Int) -> String {
        switch n {
        case 1: return "单声道"
        case 2: return "立体声"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return "\(n)ch"
        }
    }
}

// MARK: - 通用错误

enum EmbyError: LocalizedError {
    case invalidURL
    case badStatus(Int, String?)
    case decoding(Error)
    case notAuthenticated
    case playbackUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "服务器地址无效"
        case .badStatus(let code, let msg):
            if let msg, !msg.isEmpty { return "请求失败 (\(code))：\(msg)" }
            return "请求失败 (\(code))"
        case .decoding(let e): return "数据解析失败：\(e.localizedDescription)"
        case .notAuthenticated: return "尚未登录"
        case .playbackUnavailable: return "该媒体没有任何可用的播放源"
        }
    }
}
