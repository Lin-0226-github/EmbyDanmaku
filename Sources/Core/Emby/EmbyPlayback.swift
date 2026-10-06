//
//  EmbyPlayback.swift
//  EmbyDanmaku
//
//  播放信息协商（直连 / 直串 / 转码）与播放进度上报。
//

import Foundation

// MARK: - 设备能力档案

/// 提交给 Emby 的 DeviceProfile，决定服务器给我们直连还是转码
struct DeviceProfile: Encodable {
    let MaxStreamingBitrate: Int
    let MaxStaticBitrate: Int
    let MusicStreamingTranscodingBitrate: Int
    let DirectPlayProfiles: [DirectPlayProfile]
    let TranscodingProfiles: [TranscodingProfile]
    let ContainerProfiles: [ContainerProfile]
    let CodecProfiles: [CodecProfile]
    let SubtitleProfiles: [SubtitleProfile]
    let ResponseProfiles: [ResponseProfile]

    /// 生成一份描述 iOS AVPlayer 能力的档案
    /// - Parameter maxBitrate: 转码码率上限（bps）。取 0 表示不限。
    static func iOS(maxBitrate: Int) -> DeviceProfile {
        DeviceProfile(
            MaxStreamingBitrate: maxBitrate,
            MaxStaticBitrate: 120_000_000,
            MusicStreamingTranscodingBitrate: 192_000,
            DirectPlayProfiles: [
                // 完整容器直连：mp4 / m4v / mov
                DirectPlayProfile(Container: "mp4,m4v,mov",
                                  Type: "Video",
                                  VideoCodec: DeviceCapability.videoCodecs.joined(separator: ","),
                                  AudioCodec: DeviceCapability.audioCodecs.joined(separator: ","))
            ],
            TranscodingProfiles: [
                TranscodingProfile(Container: "ts", Type: "Video", `Protocol`: "hls",
                                   VideoCodec: "h264", AudioCodec: "aac",
                                   AudioChannels: "2", SubProtocol: "hls",
                                   TranscodeSeekInfo: "Auto", Context: "Streaming",
                                   BreakOnNonKeyFrames: false, MaxAudioChannels: "2",
                                   MinSegments: "1", SegmentLength: "6"),
                // 兜底：渐进式下载流
                TranscodingProfile(Container: "mp4", Type: "Video", `Protocol`: "http",
                                   VideoCodec: "h264", AudioCodec: "aac",
                                   AudioChannels: "2", SubProtocol: nil,
                                   TranscodeSeekInfo: "Auto", Context: "Streaming",
                                   BreakOnNonKeyFrames: false, MaxAudioChannels: "2",
                                   MinSegments: nil, SegmentLength: nil)
            ],
            ContainerProfiles: [],
            CodecProfiles: [],
            SubtitleProfiles: [
                // 文本字幕走 External：由客户端自行下载并渲染，避免烧录
                SubtitleProfile(Format: "srt", Method: "External"),
                SubtitleProfile(Format: "subrip", Method: "External"),
                SubtitleProfile(Format: "ass", Method: "External"),
                SubtitleProfile(Format: "ssa", Method: "External"),
                SubtitleProfile(Format: "vtt", Method: "External"),
                SubtitleProfile(Format: "webvtt", Method: "External"),
                SubtitleProfile(Format: "smi", Method: "External"),
                SubtitleProfile(Format: "dvbsub", Method: "Encode"),
                SubtitleProfile(Format: "dvdsub", Method: "Encode"),
                SubtitleProfile(Format: "pgssub", Method: "Encode"),
                SubtitleProfile(Format: "pgs", Method: "Encode")
            ],
            ResponseProfiles: [
                ResponseProfile(Container: "m4v", Type: "Video", MimeType: "video/mp4")
            ]
        )
    }
}

struct DirectPlayProfile: Encodable {
    let Container: String
    let `Type`: String
    let VideoCodec: String
    let AudioCodec: String
}

struct TranscodingProfile: Encodable {
    let Container: String
    let `Type`: String
    let `Protocol`: String
    let VideoCodec: String
    let AudioCodec: String
    let AudioChannels: String
    let SubProtocol: String?
    let TranscodeSeekInfo: String
    let Context: String
    let BreakOnNonKeyFrames: Bool
    let MaxAudioChannels: String
    let MinSegments: String?
    let SegmentLength: String?
}

struct ContainerProfile: Encodable {
    let Type: String
    let Conditions: [ProfileCondition]
}

struct CodecProfile: Encodable {
    let Type: String
    let Codec: String?
    let Conditions: [ProfileCondition]
}

struct ProfileCondition: Encodable {
    let Condition: String
    let Property: String
    let Value: String
    let IsRequired: Bool
}

struct SubtitleProfile: Encodable {
    let Format: String
    let Method: String
}

struct ResponseProfile: Encodable {
    let Container: String?
    let Type: String
    let MimeType: String?
}

// MARK: - 播放信息请求

struct PlaybackInfoBody: Encodable {
    let UserId: String
    let DeviceProfile: DeviceProfile
    let AutoOpenLiveStream: Bool
    let IsPlayback: Bool
    let MaxStreamingBitrate: Int
    let MediaSourceId: String?
}

extension EmbyClient {

    /// 向服务器询问某个条目的播放信息
    func fetchPlaybackInfo(itemId: String, mediaSourceId: String? = nil, maxBitrate: Int = 60_000_000) async throws -> PlaybackInfoResponse {
        guard let uid = userId else { throw EmbyError.notAuthenticated }
        let body = PlaybackInfoBody(UserId: uid,
                                    DeviceProfile: .iOS(maxBitrate: maxBitrate),
                                    AutoOpenLiveStream: false,
                                    IsPlayback: true,
                                    MaxStreamingBitrate: maxBitrate,
                                    MediaSourceId: mediaSourceId)
        return try await post("/emby/Items/\(itemId)/PlaybackInfo", body: body, as: PlaybackInfoResponse.self)
    }
}

// MARK: - 播放进度上报

/// 播放方式，与 Emby 上报字段一致
enum PlayMethod: String {
    case directPlay = "DirectPlay"
    case directStream = "DirectStream"
    case transcode = "Transcode"
}

/// 播放进度上报器：开始 / 进度 / 停止
@MainActor
final class PlaybackReporter {

    private let client: EmbyClient
    private var playSessionId: String?
    private var itemId: String?
    private var mediaSourceId: String?
    private var runTimeTicks: Int64
    private var playMethod: PlayMethod
    private var lastReportedTicks: Int64 = 0

    /// 上报节流：Emby 建议不要高于 1 次 / 3 秒
    static let minInterval: TimeInterval = 5

    init(client: EmbyClient) {
        self.client = client
        self.runTimeTicks = 0
        self.playMethod = .directPlay
    }

    func start(itemId: String, mediaSourceId: String?, playSessionId: String?, runTimeTicks: Int64, playMethod: PlayMethod, startTicks: Int64) async {
        self.itemId = itemId
        self.mediaSourceId = mediaSourceId
        self.playSessionId = playSessionId
        self.runTimeTicks = runTimeTicks
        self.playMethod = playMethod
        self.lastReportedTicks = startTicks
        await report(positionTicks: startTicks, isPaused: false, eventName: nil)
    }

    func progress(positionTicks: Int64, isPaused: Bool) async {
        lastReportedTicks = positionTicks
        await report(positionTicks: positionTicks, isPaused: isPaused, eventName: "TimeUpdate")
    }

    func paused(positionTicks: Int64) async {
        await report(positionTicks: positionTicks, isPaused: true, eventName: "Pause")
    }

    func stopped(positionTicks: Int64) async {
        await report(positionTicks: positionTicks, isPaused: true, eventName: nil, stop: true)
    }

    private func report(positionTicks: Int64, isPaused: Bool, eventName: String?, stop: Bool = false) async {
        guard let itemId else { return }
        struct Body: Encodable {
            let ItemId: String
            let MediaSourceId: String?
            let PlaySessionId: String?
            let PositionTicks: Int64
            let RunTimeTicks: Int64
            let CanSeek: Bool
            let IsPaused: Bool
            let IsMuted: Bool
            let VolumeLevel: Int
            let PlayMethod: String
            let QueueableMediaTypes: [String]
            let EventName: String?
        }
        let body = Body(ItemId: itemId,
                        MediaSourceId: mediaSourceId,
                        PlaySessionId: playSessionId,
                        PositionTicks: positionTicks,
                        RunTimeTicks: runTimeTicks,
                        CanSeek: true,
                        IsPaused: isPaused,
                        IsMuted: false,
                        VolumeLevel: 100,
                        PlayMethod: playMethod.rawValue,
                        QueueableMediaTypes: ["Video"],
                        EventName: eventName)

        let path: String
        if stop {
            path = "/emby/Sessions/Playing/Stopped"
        } else if eventName == nil {
            path = "/emby/Sessions/Playing"
        } else {
            path = "/emby/Sessions/Playing/Progress"
        }

        do {
            var req = try client.makeRequest(path: path)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
            _ = try await client.perform(req)
        } catch {
            // 进度上报失败不应影响播放，静默忽略
        }
    }
}

// MARK: - 供 Reporter 使用的内部请求入口

extension EmbyClient {
    func makeRequest(path: String, query: [String: String] = [:]) throws -> URLRequest {
        try request(path: path, query: query)
    }

    func perform(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await send(req)
    }
}
