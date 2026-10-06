//
//  PosterCard.swift
//  EmbyDanmaku
//
//  海报卡片、横幅卡片与远程图片加载（带内存缓存）。
//

import SwiftUI
import UIKit

// MARK: - 图片缓存

final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private init() {
        cache.countLimit = 400
        cache.totalCostLimit = 80 * 1024 * 1024
    }
    func image(for key: String) -> UIImage? { cache.object(forKey: key as NSString) }
    func set(_ image: UIImage, for key: String) {
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
}

/// 带占位与缓存的远程图片
struct RemoteImageView: View {
    let url: URL?
    var contentMode: SwiftUI.ContentMode = .fill
    var placeholderSystemImage: String = "film"

    @State private var uiImage: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let img = uiImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                ZStack {
                    Color(.secondarySystemBackground)
                    Image(systemName: placeholderSystemImage)
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .task(id: url?.absoluteString) {
            await load()
        }
    }

    private func load() async {
        guard let url else { uiImage = nil; return }
        let key = url.absoluteString
        if let cached = ImageCache.shared.image(for: key) {
            uiImage = cached
            return
        }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let img = UIImage(data: data) else { return }
        ImageCache.shared.set(img, for: key)
        uiImage = img
    }
}

// MARK: - 海报卡片

struct PosterCard: View {
    let item: BaseItem
    let client: EmbyClient
    var width: CGFloat = 108
    var aspect: CGFloat = 2.0 / 3.0

    private var imageURL: URL? {
        if item.isEpisode, let seriesId = item.SeriesId ?? item.ParentBackdropItemId {
            if let tag = item.SeriesPrimaryImageTag {
                return client.imageURL(itemId: seriesId, tag: tag, maxWidth: 400)
            }
            if let parentId = item.ParentPrimaryImageItemId {
                return client.imageURL(itemId: parentId, tag: item.SeriesPrimaryImageTag, maxWidth: 400)
            }
        }
        return client.imageURL(itemId: item.id, tag: item.primaryImageTag, maxWidth: 400)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottomLeading) {
                RemoteImageView(url: imageURL, placeholderSystemImage: item.isEpisode ? "tv" : "film")
                    .frame(width: width, height: width * aspect)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if item.watched {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.white, .green)
                                .font(.system(size: 16))
                                .padding(5)
                        } else if let c = item.UserData?.UnplayedItemCount, c > 0 {
                            Text("\(c)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.65), in: Capsule())
                                .padding(5)
                        }
                    }
                // 播放进度
                if item.progress > 0.01 {
                    GeometryReader { geo in
                        VStack(spacing: 0) {
                            Spacer()
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(width: geo.size.width * CGFloat(item.progress), height: 3)
                        }
                    }
                    .frame(height: width * aspect)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            Text(item.Name ?? "")
                .font(.footnote.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: width, alignment: .leading)

            if let sub = item.subtitleText {
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: width)
        .contentShape(Rectangle())
    }
}

// MARK: - 宽卡片（带背景图，用于「继续观看」）

struct WideCard: View {
    let item: BaseItem
    let client: EmbyClient
    var width: CGFloat = 260

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                RemoteImageView(url: backdropURL, placeholderSystemImage: "photo")
                    .frame(width: width, height: width * 9 / 16)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(alignment: .center) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(radius: 4)
                    }
                    .overlay(alignment: .bottom) {
                        if item.progress > 0.01 {
                            ProgressView(value: item.progress)
                                .progressViewStyle(.linear)
                                .padding(.horizontal, 8)
                                .padding(.bottom, 6)
                        }
                    }
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if let sub = item.subtitleText {
                Text(sub)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: width)
    }

    private var title: String {
        item.isEpisode ? (item.SeriesName ?? item.Name ?? "") : (item.Name ?? "")
    }

    private var backdropURL: URL? {
        let id = item.ParentBackdropItemId ?? item.SeriesId ?? item.id
        let tag = item.ParentBackdropImageTags?.first ?? item.backdropImageTag
        return client.backdropURL(itemId: id, tag: tag, maxWidth: 800)
    }
}
