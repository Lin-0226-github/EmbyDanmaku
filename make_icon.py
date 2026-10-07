#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 Lplayers 应用图标（v24：整体放大，圆环更粗、播放三角更大）：
白色底 + 靛蓝→紫→品红→橙 的锥形渐变圆环（带立体明暗）+ 白色圆润播放三角。
输出 1024 主图，并按 AppIcon.appiconset 需要的尺寸缩放。
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "Resources", "Assets.xcassets", "AppIcon.appiconset")

S = 1024
SS = 4                      # 超采样倍数，先画大图再缩小，边缘平滑
W = S * SS

BG = (246, 246, 249, 255)   # 白底（参考图的浅白）

CX = CY = W / 2.0
R_OUTER = 310 * SS
R_INNER = 196 * SS

# 圆环锥形渐变色标（PIL/numpy 角度：0°=正右，顺时针增加）
STOPS = [
    (0,   (255, 106, 61)),    # 右：橙红
    (45,  (255, 148, 64)),    # 右下：橙
    (90,  (240, 90, 140)),    # 下：粉红
    (135, (201, 59, 180)),    # 左下：品紫
    (180, (59, 45, 181)),     # 左：靛蓝
    (225, (123, 54, 216)),    # 左上：紫
    (270, (162, 59, 224)),    # 上：亮紫
    (315, (225, 58, 150)),    # 右上：品红
    (360, (255, 106, 61)),
]


def color_at(angle):
    """角度（0~360）→ RGB，按 STOPS 线性插值"""
    a = angle % 360.0
    for i in range(len(STOPS) - 1):
        a0, c0 = STOPS[i]
        a1, c1 = STOPS[i + 1]
        if a0 <= a <= a1:
            t = 0.0 if a1 == a0 else (a - a0) / (a1 - a0)
            return tuple(int(round(c0[k] + (c1[k] - c0[k]) * t)) for k in range(3))
    return STOPS[0][1]


def build_ring():
    """锥形渐变圆环（numpy 逐像素），带内侧变暗的立体感 + 顶部一圈加深的『环叠环』暗示"""
    yy, xx = np.mgrid[0:W, 0:W].astype(np.float64)
    dx = xx - CX
    dy = yy - CY
    dist = np.sqrt(dx * dx + dy * dy)
    ang = np.degrees(np.arctan2(dy, dx)) % 360.0          # 0=右，顺时针

    # 环形遮罩（离边缘越近越透明，天然抗锯齿）
    edge = np.minimum(R_OUTER - dist, dist - R_INNER) / (2.0 * SS)
    ring_a = np.clip(edge, 0.0, 1.0)

    inside = ring_a > 0
    # 角度 → 颜色（只算环内像素，省时间）
    idx = np.clip((ang / 360.0 * 720.0).astype(np.int64), 0, 719)
    lut = np.array([color_at(i * 0.5) for i in range(720)], dtype=np.float64)
    rgb = lut[idx]

    # 立体感：靠内缘略暗（0.82 → 1.0）
    t = np.clip((dist - R_INNER) / max(1.0, (R_OUTER - R_INNER)), 0.0, 1.0)
    shade = 0.82 + 0.18 * t
    rgb = rgb * shade[:, :, None]

    # 『环叠环』：150°~255° 一段整体加深，两端用 smoothstep 平滑过渡，模拟参考图的圆环自叠
    def smoothstep(x):
        x = np.clip(x, 0.0, 1.0)
        return x * x * (3.0 - 2.0 * x)

    def soft_band(a, lo, hi, feather=26.0):
        span = (hi - lo) % 360.0
        d = (a - lo) % 360.0                 # 距起始角的顺时针距离
        rise = smoothstep(d / feather)       # 进入段渐入
        fall = smoothstep((span - d) / feather)  # 退出段渐出
        return rise * fall

    band = soft_band(ang, 150.0, 255.0)
    rgb = rgb * (1.0 - 0.16 * band[:, :, None])

    alpha = (ring_a * 255.0)
    out = np.zeros((W, W, 4), dtype=np.uint8)
    out[:, :, :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    out[:, :, 3] = alpha.astype(np.uint8)
    return out, (ring_a > 0).astype(np.uint8) * 255


def inset_polygon(pts, r):
    """把多边形每条边向内平移 r，返回内缩后的顶点（用于画圆角）"""
    n = len(pts)
    out = []
    for i in range(n):
        p = np.array(pts[i], dtype=float)
        prev = np.array(pts[(i - 1) % n], dtype=float)
        nxt = np.array(pts[(i + 1) % n], dtype=float)
        v1 = (prev - p) / np.linalg.norm(prev - p)
        v2 = (nxt - p) / np.linalg.norm(nxt - p)
        ang = np.arccos(np.clip(np.dot(v1, v2), -1.0, 1.0))
        d = r / max(0.2, np.sin(ang / 2.0))
        bis = v1 + v2
        bis = bis / np.linalg.norm(bis)
        out.append(tuple(p + bis * d))
    return out


def rounded_solid_triangle(draw, pts, corner):
    """实心圆角三角：内缩多边形填充 + 同样内缩后 2r 描边（joint=curve 圆滑外角）"""
    ip = inset_polygon(pts, corner)
    ip_closed = ip + [ip[0]]
    draw.polygon(ip, fill=255)
    draw.line(ip_closed, fill=255, width=int(2 * corner), joint="curve")
    # 三个顶点补圆头，保证转角完全圆滑
    for p in ip:
        draw.ellipse([p[0] - corner, p[1] - corner, p[0] + corner, p[1] + corner], fill=255)


def build_master():
    ring_rgba, ring_mask = build_ring()

    # 1) 白底
    img = Image.new("RGBA", (W, W), BG)

    # 2) 圆环投影（很淡的一层，贴参考图）
    ring_img = Image.fromarray(ring_rgba, "RGBA")
    shadow_src = Image.fromarray(ring_mask, "L").filter(ImageFilter.GaussianBlur(10 * SS))
    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    shadow.paste(Image.new("RGBA", (W, W), (90, 80, 120, 46)), (0, 0), shadow_src)
    img = Image.alpha_composite(img, shadow)
    # 3) 圆环
    img = Image.alpha_composite(img, ring_img)

    # 4) 白色播放三角（右尖角恰好搭在环内缘上，参考图同款比例）
    tri = [(708 * SS, 512 * SS), (390 * SS, 342 * SS), (390 * SS, 682 * SS)]
    tri_mask = Image.new("L", (W, W), 0)
    dm = ImageDraw.Draw(tri_mask)
    rounded_solid_triangle(dm, tri, corner=52 * SS)

    tri_shadow_src = tri_mask.filter(ImageFilter.GaussianBlur(7 * SS))
    tri_shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    tri_shadow.paste(Image.new("RGBA", (W, W), (70, 50, 130, 70)), (0, 0), tri_shadow_src)
    img = Image.alpha_composite(img, tri_shadow)

    white = Image.new("RGBA", (W, W), (255, 255, 255, 255))
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    layer.paste(white, (0, 0), tri_mask)
    img = Image.alpha_composite(img, layer)

    return img.resize((S, S), Image.LANCZOS)


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
