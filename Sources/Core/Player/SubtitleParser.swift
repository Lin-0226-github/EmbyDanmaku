//
//  SubtitleParser.swift
//  EmbyDanmaku
//
//  外挂字幕解析（SRT / WebVTT / ASS）与按时间取当前字幕。
//  ASS 的高级特效不做还原，仅提取可读文本。
//

import Foundation

struct SubtitleCue: Hashable {
    let start: Double
    let end: Double
    let text: String
}

/// 字幕文本类型
enum SubtitleFormat {
    case srt
    case vtt
    case ass
    case unknown

    static func detect(from url: URL) -> SubtitleFormat {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "vtt": return .vtt
        case "ass", "ssa": return .ass
        case "srt": return .srt
        default: return .unknown
        }
    }
}

enum SubtitleParser {

    static func parse(data: Data, format: SubtitleFormat) -> [SubtitleCue] {
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16)
                ?? String(data: data, encoding: .isoLatin1) else { return [] }

        switch format {
        case .ass: return parseASS(text)
        case .vtt: return parseVTT(text)
        default:
            // 自动判断：含 Dialogue 行的是 ASS，含 WEBVTT 的是 VTT，其余按 SRT
            if text.contains("[Events]") || text.contains("Dialogue:") { return parseASS(text) }
            if text.uppercased().contains("WEBVTT") { return parseVTT(text) }
            return parseSRT(text)
        }
    }

    static func parse(url: URL, format: SubtitleFormat? = nil) async -> [SubtitleCue] {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return parse(data: data, format: format ?? SubtitleFormat.detect(from: url))
        } catch {
            return []
        }
    }

    // MARK: - SRT

    static func parseSRT(_ raw: String) -> [SubtitleCue] {
        let lines = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var cues: [SubtitleCue] = []
        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.contains("-->") {
                let parts = line.components(separatedBy: "-->")
                if parts.count >= 2,
                   let start = parseTimestamp(parts[0]),
                   let end = parseTimestamp(parts[1]) {
                    i += 1
                    var textLines: [String] = []
                    while i < lines.count {
                        let t = lines[i].trimmingCharacters(in: .whitespaces)
                        if t.isEmpty { break }
                        if t.contains("-->") { break }
                        textLines.append(stripTags(t))
                        i += 1
                    }
                    let text = textLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { cues.append(SubtitleCue(start: start, end: end, text: text)) }
                    continue
                }
            }
            i += 1
        }
        return cues
    }

    // MARK: - WebVTT

    static func parseVTT(_ raw: String) -> [SubtitleCue] {
        // WebVTT 与 SRT 时间轴格式基本一致，差别仅在头部与 cue 设置行
        let cleaned = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var lines = cleaned.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        // 去掉 WEBVTT 头与样式块
        if let idx = lines.firstIndex(where: { $0.uppercased().hasPrefix("WEBVTT") }) {
            lines.removeSubrange(0...idx)
        }
        return parseSRT(lines.joined(separator: "\n"))
    }

    // MARK: - ASS

    static func parseASS(_ raw: String) -> [SubtitleCue] {
        let lines = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var cues: [SubtitleCue] = []
        var fieldCount = 10

        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("Format:") {
                let header = t.replacingOccurrences(of: "Format:", with: "")
                fieldCount = header.split(separator: ",").count
                continue
            }
            guard t.hasPrefix("Dialogue:") else { continue }
            let body = t.replacingOccurrences(of: "Dialogue:", with: "")
            // Text 字段可能含有逗号，因此限制分割次数
            let parts = body.split(separator: ",", maxSplits: max(0, fieldCount - 1), omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 3 else { continue }
            guard let start = parseASSTime(parts[1]), let end = parseASSTime(parts[2]) else { continue }
            let textPart = parts.last ?? ""
            let text = stripASSOverrides(textPart)
            if text.isEmpty { continue }
            cues.append(SubtitleCue(start: start, end: end, text: text))
        }
        return cues.sorted { $0.start < $1.start }
    }

    // MARK: - 工具

    /// 支持 "00:00:01,000" / "00:00:01.000" / "0:00:01.00" / "00:01.5"
    static func parseTimestamp(_ s: String) -> Double? {
        var str = s.trimmingCharacters(in: .whitespaces)
        // 去掉 VTT 的 cue 设置（跟在时间轴后的空格内容）
        if let range = str.range(of: " ") { str = String(str[str.startIndex..<range.lowerBound]) }
        str = str.replacingOccurrences(of: ",", with: ".")
        let comps = str.split(separator: ":").map(String.init)
        guard !comps.isEmpty else { return nil }
        var seconds: Double = 0
        for (idx, c) in comps.enumerated() {
            guard let v = Double(c) else { return nil }
            let multiplier = Double(comps.count - 1 - idx)
            seconds += v * pow(60, multiplier)
        }
        return seconds
    }

    /// ASS 时间：H:MM:SS.cc
    static func parseASSTime(_ s: String) -> Double? {
        let str = s.trimmingCharacters(in: .whitespaces)
        let comps = str.split(separator: ":").map(String.init)
        guard comps.count == 3,
              let h = Double(comps[0]), let m = Double(comps[1]), let sec = Double(comps[2].replacingOccurrences(of: ",", with: ".")) else {
            return nil
        }
        return h * 3600 + m * 60 + sec
    }

    /// 去掉 HTML / SRT 标签
    static func stripTags(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: "\\{\\\\[^}]*\\}", with: "", options: .regularExpression)
        return out
    }

    /// 去掉 ASS 的 {\...} 特效标签与 \N 换行控制
    static func stripASSOverrides(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "\\{\\\\[^}]*\\}", with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: "\\N", with: "\n")
        out = out.replacingOccurrences(of: "\\n", with: "\n")
        out = out.replacingOccurrences(of: "\\h", with: " ")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 二分查找当前时间对应的字幕
    static func cue(at time: Double, in cues: [SubtitleCue]) -> SubtitleCue? {
        guard !cues.isEmpty else { return nil }
        var lo = 0, hi = cues.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let c = cues[mid]
            if time < c.start { hi = mid - 1 }
            else if time > c.end { lo = mid + 1 }
            else { return c }
        }
        return nil
    }
}
