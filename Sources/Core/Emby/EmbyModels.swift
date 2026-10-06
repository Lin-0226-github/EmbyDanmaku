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

/// Emby 的 Studios 返回的是 [{Name, Id}] 对象数组，而 Genres / Tags 是字符串数组。
/// 不同服务器版本偶有差异，这里做成「字符串数组」和「对象数组」都能解的宽容类型，
/// 避免详情页因为一个字段格式不对就整页打不开。
struct EmbyNameList: Codable, Hashable {
    let names: [String]

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let arr = try? c.decode([String].self) {
            names = arr
        } else if let arr = try? c.decode([EmbyNameOnly].self) {
            names = arr.compactMap { $0.Name }
        } else {
            names = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = try encoder.unkeyedContainer()
        for n in names { try c.encode(n) }
    }
}

struct EmbyNameOnly: Codable, Hashable {
    let Name: String?
}

/// Emby 的 BaseItemDto 的子集，覆盖影音库浏览所需字段
struct BaseItem: Codable, Identifiable, Hashable {
    var id: String { Id }
    let Id: String
    let Name: String?
    let OriginalTitle: String?
    let SortName: String?
    let Overview: String?
    let ItemType: String?          // Movie / Series / Season / Episode / Folder / CollectionFolder（JSON 键 "Type"）
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
    let Genres: EmbyNameList?
    let Studios: EmbyNameList?
    let Tags: EmbyNameList?
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
    let ProviderIds: [String: FlexibleScalar]?

    enum CodingKeys: String, CodingKey {
        case Id, Name, OriginalTitle, SortName, Overview
        case ItemType = "Type"
        case MediaType, SeriesName, SeasonName, SeriesId, SeasonId, ParentId
        case IndexNumber, ParentIndexNumber, ProductionYear, PremiereDate, EndDate
        case CommunityRating, CriticRating, OfficialRating, RunTimeTicks
        case Genres, Studios, Tags, People, ImageTags, BackdropImageTags
        case SeriesPrimaryImageTag, ParentPrimaryImageItemId
        case ParentBackdropItemId, ParentBackdropImageTags
        case PrimaryImageAspectRatio, UserData, ChildCount, RecursiveItemCount
        case MediaSources, MediaStreams, CollectionType, LocationType, DateCreated
        case Taglines, ExternalUrls, ProviderIds
    }

    // MARK: 派生属性

    var isFolder: Bool {
        guard let t = ItemType else { return false }
        return t == "Folder" || t == "CollectionFolder" || t == "Series" || t == "Season" || t == "BoxSet" || t == "UserView"
    }

    var isMovie: Bool { ItemType == "Movie" || ItemType == "Video" }
    var isSeries: Bool { ItemType == "Series" }
    var isSeason: Bool { ItemType == "Season" }
    var isEpisode: Bool { ItemType == "Episode" }
    var isPlayable: Bool { isMovie || isEpisode || ItemType == "Video" || ItemType == "TvChannel" || ItemType == "Program" || ItemType == "MusicVideo" }

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
    let ItemType: String?
    let PrimaryImageTag: String?

    enum CodingKeys: String, CodingKey {
        case Id, Name, Role, PrimaryImageTag
        case ItemType = "Type"
    }
}

struct ExternalUrl: Codable, Hashable {
    let Name: String?
    let Url: String?
}

struct ItemsResult: Decodable {
    let Items: [BaseItem]?
    let TotalRecordCount: Int?
    let StartIndex: Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 宽容解码：个别条目数据异常时跳过该条目，而不是整个列表都加载失败
        if let arr = try? c.decode([TolerantItem].self, forKey: .Items) {
            Items = arr.compactMap(\.item)
        } else {
            Items = nil
        }
        TotalRecordCount = try? c.decodeIfPresent(Int.self, forKey: .TotalRecordCount)
        StartIndex = try? c.decodeIfPresent(Int.self, forKey: .StartIndex)
    }

    private enum CodingKeys: String, CodingKey {
        case Items, TotalRecordCount, StartIndex
    }

    /// 单条解码失败就变 nil 的包装器
    private struct TolerantItem: Decodable {
        let item: BaseItem?
        init(from decoder: Decoder) throws {
            item = try? BaseItem(from: decoder)
        }
    }
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
        MediaStreams?.first { ($0.ItemType ?? "") == "Video" }
    }
    var audioStreams: [MediaStream] {
        (MediaStreams ?? []).filter { ($0.ItemType ?? "") == "Audio" }
    }
    var subtitleStreams: [MediaStream] {
        (MediaStreams ?? []).filter { ($0.ItemType ?? "") == "Subtitle" }
    }
    var durationSeconds: Double {
        guard let t = RunTimeTicks, t > 0 else { return 0 }
        return Double(t) / 10_000_000.0
    }
}

struct MediaStream: Codable, Hashable, Identifiable {
    var id: Int { Index }
    let Index: Int
    let ItemType: String?
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

    enum CodingKeys: String, CodingKey {
        case Index, Codec, Language, DisplayTitle, Title
        case Channels, SampleRate, BitRate, Width, Height
        case IsDefault, IsForced, IsExternal, IsTextSubtitleStream, SupportsExternalStream
        case DeliveryUrl, Path, CodecTag, Profile, Level
        case AverageFrameRate, RealFrameRate, VideoRange
        case ItemType = "Type"
    }

    /// 展示名：优先使用服务器给的 DisplayTitle，否则自己拼一个
    var displayName: String {
        if let d = DisplayTitle, !d.isEmpty { return d }
        var parts: [String] = []
        if let lang = displayLanguage, !lang.isEmpty { parts.append(lang) }
        if let t = Title, !t.isEmpty, t != langName { parts.append(t) }
        if let c = Codec { parts.append(c.uppercased()) }
        if ItemType == "Audio", let ch = Channels { parts.append(chName(ch)) }
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
    case decoding(String)
    case notAuthenticated
    case playbackUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "服务器地址无效"
        case .badStatus(let code, let msg):
            if let msg, !msg.isEmpty { return "请求失败 (\(code))：\(msg)" }
            return "请求失败 (\(code))"
        case .decoding(let detail): return detail
        case .notAuthenticated: return "尚未登录"
        case .playbackUnavailable: return "该媒体没有任何可用的播放源"
        }
    }

    /// 把解码错误翻译成能看懂的信息：哪个字段出了问题 + 服务器响应的开头长什么样。
    /// 这样即使再出解析问题，弹窗里就能直接看出原因，不用再猜。
    static func decodeFailure(_ error: Error, data: Data) -> String {
        var detail = ""
        if let de = error as? DecodingError {
            let path: ([(any CodingKey)]?) -> String = { keys in
                (keys ?? []).map { $0.stringValue }.joined(separator: ".")
            }
            switch de {
            case .typeMismatch(_, let ctx):
                let p = path(ctx.codingPath)
                detail = p.isEmpty ? "数据类型不对" : "字段 \(p) 类型不对"
            case .keyNotFound(let key, _):
                detail = "缺少字段 \(key.stringValue)"
            case .valueNotFound(_, let ctx):
                let p = path(ctx.codingPath)
                detail = "字段 \(p) 的值是 null"
            case .dataCorrupted(let ctx):
                let p = path(ctx.codingPath)
                detail = p.isEmpty ? "响应不是有效的 JSON" : "字段 \(p) 数据损坏"
            @unknown default:
                detail = error.localizedDescription
            }
        } else {
            detail = error.localizedDescription
        }
        let head = String(data: data.prefix(150), encoding: .utf8) ?? ""
        return "数据解析失败：\(detail)。响应开头：\(head)"
    }
}

extension Error {
    /// 任务被取消（切换页面、重复刷新等）不算真错误，不应该弹窗
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let ue = self as? URLError, ue.code == .cancelled { return true }
        return false
    }
}

/// 兼容值为字符串或数字的字段（Emby 的 ProviderIds 等偶尔会返回数字）
enum FlexibleScalar: Codable, Hashable {
    case text(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { self = .text(s) }
        else if let i = try? c.decode(Int64.self) { self = .text(String(i)) }
        else if let d = try? c.decode(Double.self) { self = .text(String(d)) }
        else if let b = try? c.decode(Bool.self) { self = .text(String(b)) }
        else { self = .text("") }
    }

    func encode(to encoder: Encoder) throws {
        var c = try encoder.singleValueContainer()
        if case .text(let s) = self { try c.encode(s) }
    }

    var stringValue: String {
        if case .text(let s) = self { return s }
        return ""
    }
}
