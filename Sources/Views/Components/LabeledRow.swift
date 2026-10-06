//
//  LabeledRow.swift
//  EmbyDanmaku
//
//  iOS 16 的 `LabeledContent` 在 iOS 15 上不存在，这里提供一个等价的替身：
//  左侧标题 + 右侧内容，常用于 Form / List 的信息行。
//

import SwiftUI

struct LabeledRow<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 12)
            content
        }
    }
}
