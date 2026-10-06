//
//  DanmakuParser.swift
//  EmbyDanmaku
//
//  弹幕解析：弹弹play JSON、B 站 XML、弹弹play 桌面端 XML、通用 JSON。
//

import Foundation
import UIKit

enum DanmakuParser {

    /// 弹弹play 的 p 字段：时间,模式,字号,颜色,时间戳,弹幕池,用户Hash,弹幕ID
    static func parse(rawComments: [RawComment], startId: Int64 = 1) -> [DanmakuItem] {
        var items: [DanmakuItem] = []
        items.reserveCapacity(rawComments.count)
        var seq = startId
        for raw in rawComments {
            let parts = raw.p.split(separator: ",").map(String.init)
            guard parts.count >= 4 else { continue }
            guard let time = Double(parts[0]) else { continue }
            let modeInt = Int(parts[1]) ?? 1
            let fontSize = Int(parts[2]) ?? 25
            let colorVal = Int(parts[3]) ?? 0xFFFFFF
            let ts = parts.count > 4 ? (Int(parts[4]) ?? 0) : 0
            let pool = parts.count > 5 ? (Int(parts[5]) ?? 0) : 0
            let text = raw.m.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }

            items.append(DanmakuItem(id: seq,
                                     time: max(0, time),
                                     mode: DanmakuMode(rawValue: modeInt) ?? .scroll,
                                     fontSize: fontSize,
                                     color: DanmakuItem.color(fromDecimal: colorVal),
                                     text: text,
                                     timestamp: ts,
                                     pool: pool))
            seq += 1
        }
        return items
    }

    // MARK: - XML

    /// 解析本地 XML 弹幕文件（B 站格式或弹弹play 桌面端格式）
    static func parse(xmlData: Data) -> [DanmakuItem] {
        let delegate = XMLDanmakuDelegate()
        let parser = XMLParser(data: xmlData)
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }

    // MARK: - JSON

    /// 解析本地 JSON 弹幕文件，兼容两种结构：
    ///   1. { "comments": [ { "p": "...", "m": "..." } ] }
    ///   2. [ { "time": 1.2, "text": "..." , "color": "#FFFFFF", "mode": 1 } ]
    static func parse(jsonData: Data) -> [DanmakuItem] {
        // 1) 弹弹play 标准结构：{ "comments": [ { "p": "...", "m": "..." } ] }
        struct PComment: Decodable { let p: String?; let m: String? }
        struct PWrapper: Decodable { let comments: [PComment]? }
        if let w = try? JSONDecoder().decode(PWrapper.self, from: jsonData),
           let cs = w.comments, cs.contains(where: { $0.p != nil }) {
            let raws = cs.compactMap { c -> RawComment? in
                guard let p = c.p, let m = c.m else { return nil }
                return RawComment(p: p, m: m)
            }
            if !raws.isEmpty { return parse(rawComments: raws) }
        }

        // 2) 通用结构：{ "comments": [ { "time", "text", "color", "mode" } ] } 或顶层为数组
        struct LooseComment: Decodable {
            let time: Double?
            let text: String?
            let content: String?
            let m: String?
            let color: String?
            let colorValue: Int?
            let mode: Int?
            let fontSize: Int?
            let size: Int?
        }
        struct LWrapper: Decodable { let comments: [LooseComment]? }

        func toItems(_ list: [LooseComment]) -> [DanmakuItem] {
            var items: [DanmakuItem] = []
            var seq: Int64 = 1
            for c in list {
                let text = c.text ?? c.content ?? c.m ?? ""
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                let color: UIColor
                if let cv = c.colorValue {
                    color = DanmakuItem.color(fromDecimal: cv)
                } else if let hex = c.color {
                    color = UIColor(hexString: hex)
                } else {
                    color = .white
                }
                items.append(DanmakuItem(id: seq,
                                         time: max(0, c.time ?? 0),
                                         mode: DanmakuMode(rawValue: c.mode ?? 1) ?? .scroll,
                                         fontSize: c.fontSize ?? c.size ?? 25,
                                         color: color,
                                         text: text))
                seq += 1
            }
            return items
        }

        if let w = try? JSONDecoder().decode(LWrapper.self, from: jsonData), let cs = w.comments {
            let r = toItems(cs)
            if !r.isEmpty { return r }
        }
        if let arr = try? JSONDecoder().decode([LooseComment].self, from: jsonData) {
            let r = toItems(arr)
            if !r.isEmpty { return r }
        }
        return []
    }

    /// 根据文件扩展名自动选择解析器
    static func parse(fileURL: URL) -> [DanmakuItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        switch fileURL.pathExtension.lowercased() {
        case "xml": return parse(xmlData: data)
        case "json": return parse(jsonData: data)
        default: return parse(jsonData: data)
        }
    }
}

// MARK: - XMLParserDelegate

private final class XMLDanmakuDelegate: NSObject, XMLParserDelegate {
    var items: [DanmakuItem] = []
    private var currentText = ""
    private var seq: Int64 = 1

    // B 站格式 <d p="...">
    private func handleBilibiliElement(attributes: [String: String], text: String) {
        guard let p = attributes["p"] else { return }
        let parts = p.split(separator: ",").map(String.init)
        guard parts.count >= 4, let time = Double(parts[0]) else { return }
        let mode = Int(parts[1]) ?? 1
        let size = Int(parts[2]) ?? 25
        let color = Int(parts[3]) ?? 0xFFFFFF
        let ts = parts.count > 4 ? (Int(parts[4]) ?? 0) : 0
        let pool = parts.count > 5 ? (Int(parts[5]) ?? 0) : 0
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty { return }
        items.append(DanmakuItem(id: seq, time: max(0, time),
                                 mode: DanmakuMode(rawValue: mode) ?? .scroll,
                                 fontSize: size,
                                 color: DanmakuItem.color(fromDecimal: color),
                                 text: content, timestamp: ts, pool: pool))
        seq += 1
    }

    // 弹弹play 桌面端 <VisualDmItem Time=".." Mode=".." Color=".." Size="..">
    private func handleVisualElement(attributes: [String: String], text: String) {
        guard let timeStr = attributes["Time"], let time = Double(timeStr) else { return }
        let modeStr = (attributes["Mode"] ?? "Normal").lowercased()
        let mode: DanmakuMode
        switch modeStr {
        case "top": mode = .top
        case "bottom": mode = .bottom
        default: mode = .scroll
        }
        let size = Int(attributes["Size"] ?? "25") ?? 25
        let color = Int(attributes["Color"] ?? "16777215") ?? 0xFFFFFF
        let ts = Int(attributes["Timestamp"] ?? "0") ?? 0
        let pool = Int(attributes["Pool"] ?? "0") ?? 0
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty { return }
        items.append(DanmakuItem(id: seq, time: max(0, time), mode: mode,
                                 fontSize: size, color: DanmakuItem.color(fromDecimal: color),
                                 text: content, timestamp: ts, pool: pool))
        seq += 1
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentText = ""
        switch elementName.lowercased() {
        case "d":
            pendingAttrs = attributeDict
            pendingName = elementName
        case "visualdmitem":
            pendingAttrs = attributeDict
            pendingName = elementName
        default:
            pendingAttrs = nil
            pendingName = nil
        }
    }

    private var pendingAttrs: [String: String]?
    private var pendingName: String?

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if pendingAttrs != nil { currentText += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard let attrs = pendingAttrs else { return }
        let text = currentText
        switch elementName.lowercased() {
        case "d": handleBilibiliElement(attributes: attrs, text: text)
        case "visualdmitem": handleVisualElement(attributes: attrs, text: text)
        default: break
        }
        pendingAttrs = nil
        currentText = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        pendingAttrs = nil
    }
}

// MARK: - UIColor 十六进制

extension UIColor {
    convenience init(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        if hex.hasPrefix("0x") || hex.hasPrefix("0X") { hex = String(hex.dropFirst(2)) }
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }

    convenience init(hexString: String?) {
        self.init(hexString: hexString ?? "#FFFFFF")
    }
}
