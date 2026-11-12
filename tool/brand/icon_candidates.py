"""图标方向候选：一次渲染 4 个概念 ×（深 / 浅底）对比图，供挑选方向。

用法（在 app 目录）：python tool/brand/icon_candidates.py
输出：build/icon_candidates.png
"""

import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SS = 4  # 超采样

GREEN = (0x1E, 0xD7, 0x60)
MINT = (0x63, 0xEA, 0x8E)
DEEP = (0x0B, 0x7A, 0x3E)
INK = (0x0E, 0x14, 0x10)  # 近黑深绿


def superellipse(size, n=5.0, steps=720):
    half = size / 2
    pts = []
    for i in range(steps):
        a = 2 * math.pi * i / steps
        ca, sa = math.cos(a), math.sin(a)
        pts.append((half + half * math.copysign(abs(ca) ** (2 / n), ca),
                    half + half * math.copysign(abs(sa) ** (2 / n), sa)))
    return pts


def plate_mask(s, inset=0.0):
    m = Image.new('L', (s, s), 0)
    d = ImageDraw.Draw(m)
    pts = superellipse(s)
    if inset:
        cx = s / 2
        pts = [(cx + (x - cx) * (1 - 2 * inset), cx + (y - cx) * (1 - 2 * inset)) for x, y in pts]
    d.polygon(pts, fill=255)
    return m


def diag_gradient(s, c1, c2, mid=None):
    small = 128
    img = Image.new('RGB', (small, small))
    px = img.load()
    for y in range(small):
        for x in range(small):
            t = (x + y) / (2 * (small - 1))
            if mid and t > 0.5:
                a, b, t2 = mid, c2, (t - 0.5) * 2
            elif mid:
                a, b, t2 = c1, mid, t * 2
            else:
                a, b, t2 = c1, c2, t
            px[x, y] = tuple(round(aa + (bb - aa) * t2) for aa, bb in zip(a, b))
    return img.resize((s, s), Image.BICUBIC).convert('RGBA')


def with_plate(s, fill_img):
    out = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    out.paste(fill_img, (0, 0), plate_mask(s))
    return out


def rrect(draw, box, r, fill):
    draw.rounded_rectangle(box, radius=r, fill=fill)


# ---------------------------------------------------------------------------
# A. 极光声波：深空底板 + 绿渐变均衡器三条竖波 + 圆点
# ---------------------------------------------------------------------------
def concept_wave(s):
    img = with_plate(s, diag_gradient(s, (0x10, 0x1B, 0x14), (0x05, 0x08, 0x06)))
    d = ImageDraw.Draw(img)
    grad = diag_gradient(s, MINT, DEEP, mid=GREEN)
    bars = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bars)
    w = 0.105 * s
    xs = [0.30, 0.485, 0.67]
    tops = [0.42, 0.24, 0.36]
    bots = [0.58, 0.76, 0.64]
    for x, t, b in zip(xs, tops, bots):
        rrect(bd, (x * s, t * s, x * s + w, b * s), w / 2, (255, 255, 255, 255))
    bars.putalpha(Image.composite(grad.convert('L'), Image.new('L', (s, s), 0), bars.split()[3]))
    img.alpha_composite(bars)
    d = ImageDraw.Draw(img)
    d.ellipse((0.445 * s, 0.82 * s, 0.555 * s, 0.93 * s), fill=GREEN)
    return img


# ---------------------------------------------------------------------------
# B. 轨道播放：绿渐变底板 + 白色播放三角 + 环绕声弧
# ---------------------------------------------------------------------------
def concept_orbit(s):
    img = with_plate(s, diag_gradient(s, MINT, DEEP, mid=GREEN))
    d = ImageDraw.Draw(img)
    white = (255, 255, 255, 255)
    # 播放三角（圆角，用多边形 + 圆角近似：三个顶点圆盘 + 三角形）
    cx, cy, r = 0.47 * s, 0.52 * s, 0.20 * s
    pts = [(cx - r * 0.75, cy - r), (cx - r * 0.75, cy + r), (cx + r, cy)]
    d.polygon(pts, fill=white)
    pr = 0.055 * s
    for p in pts:
        d.ellipse((p[0] - pr, p[1] - pr, p[0] + pr, p[1] + pr), fill=white)
    # 两条环绕声弧（右上方）
    for i, rr in enumerate((0.30, 0.40)):
        bbox = (cx - rr * s, cy - rr * s, cx + rr * s, cy + rr * s)
        d.arc(bbox, start=-70, end=20, fill=white, width=int(0.045 * s))
    return img


# ---------------------------------------------------------------------------
# C. 黑胶：近黑底板 + 同心纹 + 极光绿芯
# ---------------------------------------------------------------------------
def concept_vinyl(s):
    img = with_plate(s, diag_gradient(s, (0x14, 0x1A, 0x16), (0x06, 0x09, 0x07)))
    d = ImageDraw.Draw(img)
    c = s / 2
    for i, rr in enumerate((0.36, 0.30, 0.24)):
        shade = 46 + i * 14
        d.ellipse((c - rr * s, c - rr * s, c + rr * s, c + rr * s),
                  outline=(shade, shade + 6, shade, 255), width=int(0.012 * s))
    core = 0.13 * s
    d.ellipse((c - core, c - core, c + core, c + core), fill=GREEN)
    hole = 0.035 * s
    d.ellipse((c - hole, c - hole, c + hole, c + hole), fill=(0x0A, 0x0E, 0x0B, 255))
    return img


# ---------------------------------------------------------------------------
# D. 声波 F：深底 + 一条连续声波曲线勾出的 f（极光绿发光）
# ---------------------------------------------------------------------------
def concept_pulse(s):
    img = with_plate(s, diag_gradient(s, (0x0D, 0x18, 0x11), (0x04, 0x0A, 0x06)))
    layer = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    # f 曲线：底部竖笔上行 → 顶部向右弯钩，中间一道横
    pts = []
    for i in range(101):
        t = i / 100
        y = 0.80 - 0.52 * t
        x = 0.42 + 0.06 * math.sin(t * math.pi * 0.9)
        if t > 0.86:  # 顶部弯钩
            u = (t - 0.86) / 0.14
            x += 0.20 * math.sin(u * math.pi / 2)
            y += 0.10 * (1 - math.cos(u * math.pi / 2))
        pts.append((x * s, y * s))
    d.line(pts, fill=GREEN, width=int(0.075 * s), joint='curve')
    for p in (pts[0], pts[-1]):
        r = 0.0375 * s
        d.ellipse((p[0] - r, p[1] - r, p[0] + r, p[1] + r), fill=GREEN)
    rrect(d, (0.28 * s, 0.485 * s, 0.62 * s, 0.56 * s), 0.0375 * s, GREEN)
    glow = layer.filter(ImageFilter.GaussianBlur(0.03 * s))
    img.alpha_composite(glow)
    img.alpha_composite(layer)
    return img


CONCEPTS = [('A 极光声波', concept_wave), ('B 轨道播放', concept_orbit),
            ('C 黑胶', concept_vinyl), ('D 声波 F', concept_pulse)]


def main():
    px = 256
    pad, label = 40, 46
    cols = len(CONCEPTS)
    rows = 2
    W = cols * (px + pad) + pad
    H = rows * (px + pad + label) + pad
    sheet = Image.new('RGB', (W, H), (0x20, 0x20, 0x20))
    for row, bg in enumerate(((0x12, 0x12, 0x12), (0xF2, 0xF2, 0xF2))):
        for col, (name, fn) in enumerate(CONCEPTS):
            x = pad + col * (px + pad)
            y = pad + row * (px + pad + label)
            tile = Image.new('RGB', (px, px + label), bg)
            icon = fn(px * SS).resize((px, px), Image.LANCZOS)
            tile.paste(icon, (0, 0), icon)
            sheet.paste(tile, (x, y))
    out = os.path.join(ROOT, 'build', 'icon_candidates.png')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sheet.save(out)
    print(out)


if __name__ == '__main__':
    main()
