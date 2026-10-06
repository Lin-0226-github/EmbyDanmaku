#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 Lplayers 应用图标：黑底 + 绿色线条 + 播放器元素（播放三角 + 进度条）。
输出 1024 主图，并按 AppIcon.appiconset 需要的尺寸缩放。
"""
import os
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "Resources", "Assets.xcassets", "AppIcon.appiconset")

S = 1024                      # 画布
BG = (0, 0, 0, 255)           # 纯黑底
GREEN = (46, 224, 122, 255)   # 线条绿
GREEN_DIM = (46, 224, 122, 110)  # 进度条底槽（半透明绿）

# 播放器窗口外框（16:9）
FX0, FY0, FX1, FY1 = 200, 322, 824, 702
FRAME_W = 34
FRAME_R = 74

# 进度条
BAR_Y = 640
BAR_X0, BAR_X1 = 292, 732
BAR_H = 16
PLAYED = 0.46


def rounded_rect(draw, box, radius, fill=None, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def play_triangle(cx, cy, w, h):
    """居中的播放三角顶点（尖端向右）"""
    left = cx - w / 2.0
    right = cx + w / 2.0
    top = cy - h / 2.0
    bottom = cy + h / 2.0
    return [(left, top), (left, bottom), (right, cy)]


def main():
    img = Image.new("RGBA", (S, S), BG)
    d = ImageDraw.Draw(img)

    # 1) 播放器窗口：绿色描边圆角矩形
    rounded_rect(d, [FX0, FY0, FX1, FY1], FRAME_R, outline=GREEN, width=FRAME_W)

    # 2) 播放三角（描边，空心更简约）
    tri = play_triangle(500, 476, 168, 196)
    d.line([tri[0], tri[1], tri[2], tri[0]], fill=GREEN, width=36, joint="curve")
    # 让三角的转角更圆润：补三个小圆点
    r = 18
    for p in tri:
        d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=GREEN)

    # 3) 进度条：底槽 + 已播放段 + 圆点滑块
    rounded_rect(d, [BAR_X0, BAR_Y - BAR_H // 2, BAR_X1, BAR_Y + BAR_H // 2],
                 BAR_H // 2, fill=GREEN_DIM)
    px = BAR_X0 + (BAR_X1 - BAR_X0) * PLAYED
    rounded_rect(d, [BAR_X0, BAR_Y - BAR_H // 2, px, BAR_Y + BAR_H // 2],
                 BAR_H // 2, fill=GREEN)
    pr = 26
    d.ellipse([px - pr, BAR_Y - pr, px + pr, BAR_Y + pr], fill=GREEN)

    os.makedirs(OUT, exist_ok=True)
    master = os.path.join(OUT, "Icon-1024.png")
    img.save(master)

    # 各尺寸（像素 = pt * scale）
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
    for name in sorted(sizes):
        print("  ", name, sizes[name])


if __name__ == "__main__":
    main()
