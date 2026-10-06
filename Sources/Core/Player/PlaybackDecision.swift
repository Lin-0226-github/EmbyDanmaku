//
//  PlaybackDecision.swift
//  EmbyDanmaku
//
//  根据媒体源信息决定：直连播放、直串，还是请求服务器转码；
//  同时整理出可切换的音轨与字幕轨。
//

import Foundation
import AVFoundation

/// 一条可选择的字幕轨（客户端自渲染）
struct SubtitleTrack: Identifiable, Hashable {
    var id: Int { index }
    let index: Int
    let title: String
    let language: String?
    let url: URL?
    let isExternal: Bool
    let isDefault: Bool
    /// 图形字幕无法自渲染，只能通过服务器转码烧录
    let requiresBurnIn: Bool

    var displayTitle: String {
        var parts: [String] = []
        if let l = language, !l.isEmpty { parts.append(l) }
        if !title.isEmpty, title != language { parts.append(title) }
        if isExternal { parts.append("外挂") }
        return parts.isEmpty ? "字幕 \(index)" : parts.joined(separator: " · ")
    }
}

/// 播放方案
struct PlaybackPlan {
    let url: URL
    let method: PlayMethod
    let mediaSourceId: String
    let playSessionId: String?
    let durationTicks: Int64
    /// 客户端自渲染的字幕轨
    let subtitleTracks: [SubtitleTrack]
    /// 音轨（转码时通常只剩一条，切换依赖服务器）
    let audioTracks: [MediaStream]
    /// 需要附加到 AVAsset 请求上的 HTTP 头（反代场景）
    let httpHeaders: [String: String]
    /// 视频分辨率描述，用于 UI 展示
    let qualityLabel: String
    /// 原始文件名（用于弹幕匹配）
    let fileName: String?
}

enum PlaybackDecision {

    /// 需要服务器烧录的图形字幕编码
    private static let burnInSubtitleCodecs: Set<String> = ["pgssub", "pgs", "dvbsub", "dvdsub", "dvd_subtitle", "hdmv_pgs_subtitle", "xsub"]

    private static let textSubtitleCodecs: Set<String> = ["srt", "subrip", "ass", "ssa", "vtt", "webvtt", "smi", "mov_text", "subrip", "eia608", "eia708"]

    /// 生成播放方案
    static func plan(client: EmbyClient,
                     itemId: String,
                     info: PlaybackInfoResponse,
                     preferDirect: Bool,
                     preferredAudioIndex: Int? = nil,
                     preferredSubtitleIndex: Int? = nil) -> PlaybackPlan? {
        guard let sources = info.MediaSources, !sources.isEmpty else { return nil }

        // 优先挑一个可直连的源，否则用第一个支持转码的源
        let sorted = sources.sorted { a, b in
            score(a) > score(b)
        }
        guard let source = sorted.first else { return nil }

        let container = (source.Container ?? "").lowercased()
        let videoCodec = (source.videoStream?.Codec ?? "").lowercased()
        let canDirect = preferDirect
            && (source.SupportsDirectPlay ?? source.SupportsDirectStream ?? false)
            && DeviceCapability.containers.contains(container)
            && DeviceCapability.videoCodecs.contains(videoCodec)
            && !hasBurnInOnlySubtitle(source)
            && audioUsable(source)

        let subtitleTracks = buildSubtitles(client: client, itemId: itemId, source: source)
        let audioTracks = source.audioStreams

        if canDirect {
            guard let url = client.directStreamURL(itemId: itemId, mediaSourceId: source.Id, container: container) else {
                return nil
            }
            return PlaybackPlan(url: url,
                                method: .directPlay,
                                mediaSourceId: source.Id,
                                playSessionId: info.PlaySessionId,
                                durationTicks: source.RunTimeTicks ?? 0,
                                subtitleTracks: subtitleTracks,
                                audioTracks: audioTracks,
                                httpHeaders: source.RequiredHttpHeaders ?? [:],
                                qualityLabel: quality(of: source),
                                fileName: fileName(of: source))
        }

        // 转码：优先使用服务器给出的 HLS 地址
        if let tPath = source.TranscodingUrl, !tPath.isEmpty, let url = client.transcodeURL(transcodingPath: tPath) {
            return PlaybackPlan(url: url,
                                method: .transcode,
                                mediaSourceId: source.Id,
                                playSessionId: info.PlaySessionId,
                                durationTicks: source.RunTimeTicks ?? 0,
                                subtitleTracks: subtitleTracks,
                                audioTracks: audioTracks,
                                httpHeaders: [:],
                                qualityLabel: quality(of: source) + " · 转码",
                                fileName: fileName(of: source))
        }

        // 兜底：仍然尝试直串（服务器可能自己转封装）
        if let url = client.directStreamURL(itemId: itemId, mediaSourceId: source.Id, container: container) {
            return PlaybackPlan(url: url,
                                method: .directStream,
                                mediaSourceId: source.Id,
                                playSessionId: info.PlaySessionId,
                                durationTicks: source.RunTimeTicks ?? 0,
                                subtitleTracks: subtitleTracks,
                                audioTracks: audioTracks,
                                httpHeaders: source.RequiredHttpHeaders ?? [:],
                                qualityLabel: quality(of: source),
                                fileName: fileName(of: source))
        }
        return nil
    }

    /// 从媒体源路径提取文件名，作为弹幕匹配的线索
    private static func fileName(of s: MediaSource) -> String? {
        if let p = s.Path, !p.isEmpty {
            return (p as NSString).lastPathComponent
        }
        return s.Name
    }

    // MARK: - 判定辅助

    private static func score(_ s: MediaSource) -> Int {
        var v = 0
        if s.SupportsDirectPlay ?? false { v += 4 }
        if s.SupportsDirectStream ?? false { v += 2 }
        if DeviceCapability.containers.contains((s.Container ?? "").lowercased()) { v += 1 }
        return v
    }

    /// 音频是否至少有一条可解码
    private static func audioUsable(_ s: MediaSource) -> Bool {
        let audios = s.audioStreams
        if audios.isEmpty { return true }
        return audios.contains { DeviceCapability.audioCodecs.contains(($0.Codec ?? "").lowercased()) }
    }

    /// 是否只有图形字幕（必须烧录）
    private static func hasBurnInOnlySubtitle(_ s: MediaSource) -> Bool {
        let subs = s.subtitleStreams
        guard !subs.isEmpty else { return false }
        return subs.allSatisfy { burnInSubtitleCodecs.contains(($0.Codec ?? "").lowercased()) }
    }

    private static func buildSubtitles(client: EmbyClient, itemId: String, source: MediaSource) -> [SubtitleTrack] {
        source.subtitleStreams.compactMap { stream in
            let codec = (stream.Codec ?? "").lowercased()
            let burn = burnInSubtitleCodecs.contains(codec)
            var url: URL? = nil
            if !burn {
                if let delivery = stream.DeliveryUrl, !delivery.isEmpty {
                    var p = delivery
                    if !p.hasPrefix("/") { p = "/" + p }
                    if let token = client.accessToken, !p.contains("api_key") {
                        p += (p.contains("?") ? "&" : "?") + "api_key=" + token
                    }
                    url = URL(string: client.serverURL + p)
                } else {
                    url = subtitleURL(client: client, itemId: itemId,
                                      mediaSourceId: source.Id, index: stream.Index, codec: codec)
                }
            }
            return SubtitleTrack(index: stream.Index,
                                 title: stream.Title ?? stream.displayName,
                                 language: stream.displayLanguage,
                                 url: url,
                                 isExternal: stream.IsExternal ?? false,
                                 isDefault: stream.Index == source.DefaultSubtitleStreamIndex,
                                 requiresBurnIn: burn)
        }
    }

    private static func subtitleURL(client: EmbyClient, itemId: String, mediaSourceId: String, index: Int, codec: String) -> URL? {
        let format: String
        if codec == "ass" || codec == "ssa" { format = "ass" } else { format = "vtt" }
        var comps = URLComponents(string: client.serverURL + "/emby/Videos/\(itemId)/\(mediaSourceId)/Subtitles/\(index)/Stream.\(format)")
        if let token = client.accessToken {
            comps?.queryItems = [URLQueryItem(name: "api_key", value: token)]
        }
        return comps?.url
    }

    private static func quality(of s: MediaSource) -> String {
        guard let v = s.videoStream else { return "未知画质" }
        if let h = v.Height {
            switch h {
            case ..<480: return "SD"
            case 480..<720: return "480P"
            case 720..<1080: return "720P"
            case 1080..<1440: return "1080P"
            case 1440..<2160: return "2K"
            default: return "4K"
            }
        }
        return v.DisplayTitle ?? "直连"
    }

    /// 供 UI 展示的解码方式说明
    static func description(for method: PlayMethod) -> String {
        switch method {
        case .directPlay: return "直连（原画质）"
        case .directStream: return "直串"
        case .transcode: return "服务器转码"
        }
    }
}
