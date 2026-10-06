#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 Lplayers 应用图标（参考 Infuse / EPlayerX 风格）：
白色底 + 橙→品红渐变的圆润播放三角 + 渐变进度条（播放器元素）。
输出 1024 主图，并按 AppIcon.appiconset 需要的尺寸缩放。
"""
import os
import numpy as np
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "Resources", "Assets.xcassets", "AppIcon.appiconset")

S = 1024
WHITE = (255, 255, 255, 255)
# 橙 → 品红 渐变（Infuse 的活力橙 + EPlayerX 的渐变感）
C1 = (255, 154, 26)     # #FF9A1A
C2 = (255, 61, 87)      # #FF3D57


def linear_gradient(size, c1, c2):
    """对角线渐变（左上 → 右下）"""
    xs = np.linspace(0, 1, size)
    ys = np.linspace(0, 1, size)
    xx, yy = np.meshgrid(xs, ys)
    t = ((xx + yy) / 2.0)[:, :, None]
    c1a = np.array(c1, dtype=float)[None, None, :]
    c2a = np.array(c2, dtype=float)[None, None, :]
    rgb = (c1a * (1 - t) + c2a * t).astype(np.uint8)
    alpha = np.full((size, size, 1), 255, dtype=np.uint8)
    return Image.fromarray(np.concatenate([rgb, alpha], axis=2), "RGBA")


def rounded_triangle(draw, pts, width):
    """带圆角连接的描边三角（线 + 圆头端点）；draw 目标是 L 模式蒙版，fill 用 255"""
    closed = pts + [pts[0]]
    draw.line(closed, fill=255, width=width, joint="curve")
    r = width / 2.0
    for p in pts:
        draw.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=255)


def build_master():
    img = Image.new("RGBA", (S, S), WHITE)
    grad = linear_gradient(S, C1, C2)

    # 1) 渐变圆角播放三角（居中，视觉上略偏左平衡）
    tri_mask = Image.new("L", (S, S), 0)
    dm = ImageDraw.Draw(tri_mask)
    tri = [(318, 288), (318, 736), (726, 512)]
    rounded_triangle(dm, tri, width=92)
    img.paste(grad, (0, 0), tri_mask)

    # 2) 渐变进度条（播放器元素）：底槽淡灰 + 已播放渐变 + 圆形滑块
    bar_y = 806
    bar_x0, bar_x1 = 300, 724
    bar_h = 26

    bar_mask = Image.new("L", (S, S), 0)
    bm = ImageDraw.Draw(bar_mask)
    bm.rounded_rectangle([bar_x0, bar_y - bar_h // 2, bar_x1, bar_y + bar_h // 2],
                         radius=bar_h // 2, fill=255)
    # 已播放段（60%）+ 滑块圆点
    px = bar_x0 + (bar_x1 - bar_x0) * 0.60
    played_mask = Image.new("L", (S, S), 0)
    pm = ImageDraw.Draw(played_mask)
    pm.rounded_rectangle([bar_x0, bar_y - bar_h // 2, px, bar_y + bar_h // 2],
                         radius=bar_h // 2, fill=255)
    pr = 52
    pm.ellipse([px - pr, bar_y - pr, px + pr, bar_y + pr], fill=255)

    # 底槽：淡灰
    trough = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    trough.paste(Image.new("RGBA", (S, S), (18, 18, 22, 26)), (0, 0), bar_mask)
    img = Image.alpha_composite(img, trough)
    # 已播放：渐变
    img = Image.alpha_composite(img, Image.new("RGBA", (S, S), (0, 0, 0, 0)))
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    layer.paste(grad, (0, 0), played_mask)
    img = Image.alpha_composite(img, layer)
    return img


def main():
    img = build_master()
    os.makedirs(OUT, exist_ok=True)
    master = os.path.join(OUT, "Icon-1024.png")
    img.save(master)

    sizes = {
        "Icon-20@2x.png": 40,
        "Icon-20@3x.png": 60,
        "Icon-29.png": 29,
        "Icon-29@2x.png": 58,
        "Icon-29@3x.png": 87,
        "Icon-40.png": 40,
        "Icon-40@2x.png": 80,
        "Icon-40@3x.png": 120,
        "Icon-60@2x.png": 120,
        "Icon-60@3x.png": 180,
        "Icon-76.png": 76,
        "Icon-76@2x.png": 152,
        "Icon-83.5@2x.png": 167,
    }
    for name, px in sizes.items():
        img.resize((px, px), Image.LANCZOS).save(os.path.join(OUT, name))

    print("图标已生成：", master)


if __name__ == "__main__":
    main()
