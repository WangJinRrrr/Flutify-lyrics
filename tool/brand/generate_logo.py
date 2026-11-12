"""Flutify 品牌标生成器：一套几何参数 → SVG 母版 + 各平台图标。

设计：连续曲率圆角方块（superellipse，n=5，接近 iOS 图标轮廓）+ 薄荷 → 品牌绿 → 深青绿三段对角渐变
（叠左上径向光泽）；白色字形为三条全圆角均衡器声波（中条最高，左右起伏）。
App 内的 `FlutifyMark`（lib/ui/screens/auth/widgets/flutify_mark.dart）按同一组比例绘制，改这里要同步改那里。

用法（在 app 目录）：python tool/brand/generate_logo.py
输出：
  assets/brand/flutify_logo.svg / flutify_logo_1024.png / flutify_glyph.svg
  windows/runner/resources/app_icon.ico
  android/app/src/main/res/mipmap-*/ic_launcher.png（旧版启动器）
  android/app/src/main/res/mipmap-*/ic_launcher_foreground.png + mipmap-anydpi-v26/ic_launcher.xml（自适应图标）
"""

import math
import os

from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

# ---------------------------------------------------------------------------
# 几何（以边长 1 为单位）
# ---------------------------------------------------------------------------
# 三段对角渐变：薄荷（左上）→ 品牌绿（中段）→ 深青绿（右下），
# 再叠一层左上径向光泽，图标在任务栏小尺寸下也有立体感
GREEN_MINT = (0x63, 0xEA, 0x8E)  # 左上
GREEN_BRAND = (0x1E, 0xD7, 0x60)  # 中段：品牌绿
GREEN_DEEP = (0x0B, 0x7A, 0x3E)  # 右下：偏青的深绿，白字对比更足
SHEEN_ALPHA = 0.16  # 左上径向光泽强度
SUPERELLIPSE_N = 5.0

T = 0.105  # 声波条粗细（全圆角，半径 T/2）
BAR_XS = (0.32, 0.50, 0.68)  # 三条声波的圆心 x
BAR_TOPS = (0.355, 0.240, 0.320)  # 各条顶缘（中条最高，节奏感）
BAR_BOTS = (0.645, 0.760, 0.680)  # 各条底缘

# 字形元素：(类型, 参数)，矩形均为全圆角（半径 T/2）
GLYPH = [
    ('rect', (x - T / 2, t, x + T / 2, b)) for x, t, b in zip(BAR_XS, BAR_TOPS, BAR_BOTS)
]


def superellipse(size, inset=0.0, steps=720):
    """边长 size 的方框内（四周留 inset 比例）的 superellipse 轮廓点。"""
    half = size * (1 - 2 * inset) / 2
    c = size / 2
    pts = []
    for i in range(steps):
        a = 2 * math.pi * i / steps
        ca, sa = math.cos(a), math.sin(a)
        x = math.copysign(abs(ca) ** (2 / SUPERELLIPSE_N), ca)
        y = math.copysign(abs(sa) ** (2 / SUPERELLIPSE_N), sa)
        pts.append((c + half * x, c + half * y))
    return pts


# ---------------------------------------------------------------------------
# SVG
# ---------------------------------------------------------------------------
def glyph_svg(scale=1024, offset=0.0, fill='#FFFFFF'):
    parts = []
    r = T / 2 * scale
    for kind, p in GLYPH:
        if kind == 'rect':
            x0, y0, x1, y1 = (v * scale + offset for v in p)
            parts.append(f'<rect x="{x0:.1f}" y="{y0:.1f}" width="{x1 - x0:.1f}" height="{y1 - y0:.1f}" '
                         f'rx="{r:.1f}" fill="{fill}"/>')
        else:
            cx, cy, cr = p
            parts.append(f'<circle cx="{cx * scale + offset:.1f}" cy="{cy * scale + offset:.1f}" r="{cr * scale:.1f}" '
                         f'fill="{fill}"/>')
    return '\n  '.join(parts)


def write_svgs():
    s = 1024
    pts = superellipse(s)
    path = 'M' + ' L'.join(f'{x:.1f},{y:.1f}' for x, y in pts) + ' Z'
    hex_ = lambda c: '#%02X%02X%02X' % c
    logo = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {s} {s}" width="{s}" height="{s}">
  <!-- Flutify 品牌标（由 tool/brand/generate_logo.py 生成，勿手改） -->
  <defs>
    <linearGradient id="plate" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="{hex_(GREEN_MINT)}"/>
      <stop offset="0.52" stop-color="{hex_(GREEN_BRAND)}"/>
      <stop offset="1" stop-color="{hex_(GREEN_DEEP)}"/>
    </linearGradient>
    <radialGradient id="sheen" cx="0.18" cy="0.10" r="0.9">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="{SHEEN_ALPHA}"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <path d="{path}" fill="url(#plate)"/>
  <path d="{path}" fill="url(#sheen)"/>
  {glyph_svg(s)}
</svg>
'''
    glyph = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {s} {s}" width="{s}" height="{s}">
  <!-- Flutify 字形（单色，可用于单色场景 / 通知图标），由 tool/brand/generate_logo.py 生成 -->
  {glyph_svg(s, fill='#000000')}
</svg>
'''
    out = os.path.join(ROOT, 'assets', 'brand')
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, 'flutify_logo.svg'), 'w', encoding='utf-8') as f:
        f.write(logo)
    with open(os.path.join(out, 'flutify_glyph.svg'), 'w', encoding='utf-8') as f:
        f.write(glyph)


# ---------------------------------------------------------------------------
# 栅格化（4 倍超采样后 LANCZOS 缩小，边缘平滑）
# ---------------------------------------------------------------------------
SS = 4


def draw_glyph(img, size, scale=1.0, offset=(0.0, 0.0), fill=(255, 255, 255, 255)):
    """在 size 画布上绘制声波字形；scale / offset 用于自适应图标把字形缩进安全区。"""
    draw = ImageDraw.Draw(img)
    ox, oy = offset
    r = T / 2 * size * scale
    tf = lambda v, o: (v * scale) * size + o
    for kind, p in GLYPH:
        if kind == 'rect':
            x0, y0, x1, y1 = p
            draw.rounded_rectangle((tf(x0, ox), tf(y0, oy), tf(x1, ox), tf(y1, oy)), radius=r, fill=fill)
        else:
            cx, cy, cr = p
            cx, cy, cr = tf(cx, ox), tf(cy, oy), cr * size * scale
            draw.ellipse((cx - cr, cy - cr, cx + cr, cy + cr), fill=fill)


def gradient(size):
    """左上 → 右下的三段对角渐变 + 左上径向光泽。"""
    small = 256
    img = Image.new('RGB', (small, small))
    px = img.load()
    for y in range(small):
        for x in range(small):
            t = (x + y) / (2 * (small - 1))
            if t < 0.52:  # 薄荷 → 品牌绿
                a, b, u = GREEN_MINT, GREEN_BRAND, t / 0.52
            else:  # 品牌绿 → 深青绿
                a, b, u = GREEN_BRAND, GREEN_DEEP, (t - 0.52) / 0.48
            base = [aa + (bb - aa) * u for aa, bb in zip(a, b)]
            # 径向光泽：左上方一团柔光，按距离平方衰减
            d = math.hypot(x / small - 0.18, y / small - 0.10) / 0.9
            sheen = SHEEN_ALPHA * max(0.0, 1 - d) ** 2 * 255
            px[x, y] = tuple(round(c + (255 - c) * sheen / 255) for c in base)
    return img.resize((size, size), Image.BICUBIC)


def render_logo(px, inset=0.0):
    """完整品牌标（squircle 底板 + 字形）；inset 为四周留白比例。"""
    s = px * SS
    mask = Image.new('L', (s, s), 0)
    ImageDraw.Draw(mask).polygon(superellipse(s, inset), fill=255)
    img = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    img.paste(gradient(s), (0, 0), mask)
    # 字形随底板一起缩进
    inner = 1 - 2 * inset
    draw_glyph(img, s, scale=inner, offset=(s * inset, s * inset))
    return img.resize((px, px), Image.LANCZOS)


def render_foreground(px):
    """自适应图标前景：108dp 画布，字形缩进 72dp 区域（安全区 66dp 内留足余量）。"""
    s = px * SS
    img = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    scale = 72 / 108
    off = s * (1 - scale) / 2
    draw_glyph(img, s, scale=scale, offset=(off, off))
    return img.resize((px, px), Image.LANCZOS)


def write_rasters():
    brand = os.path.join(ROOT, 'assets', 'brand')
    render_logo(1024).save(os.path.join(brand, 'flutify_logo_1024.png'))

    # Windows：多尺寸 ICO，四周留 3% 与系统图标视觉大小一致
    ico_sizes = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]
    base = render_logo(256, inset=0.03)
    frames = [render_logo(n, inset=0.03) for n in ico_sizes]
    base.save(os.path.join(ROOT, 'windows', 'runner', 'resources', 'app_icon.ico'),
              sizes=[(n, n) for n in ico_sizes], append_images=frames)

    # Android
    res = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')
    densities = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
    for name, k in densities.items():
        folder = os.path.join(res, f'mipmap-{name}')
        os.makedirs(folder, exist_ok=True)
        render_logo(round(48 * k), inset=0.06).save(os.path.join(folder, 'ic_launcher.png'))
        render_foreground(round(108 * k)).save(os.path.join(folder, 'ic_launcher_foreground.png'))

    anydpi = os.path.join(res, 'mipmap-anydpi-v26')
    os.makedirs(anydpi, exist_ok=True)
    with open(os.path.join(anydpi, 'ic_launcher.xml'), 'w', encoding='utf-8') as f:
        f.write('''<?xml version="1.0" encoding="utf-8"?>
<!-- 自适应图标：渐变底 + 白色字形（由 tool/brand/generate_logo.py 生成） -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
''')
    drawable = os.path.join(res, 'drawable')
    hex_ = lambda c: '#FF%02X%02X%02X' % c
    with open(os.path.join(drawable, 'ic_launcher_background.xml'), 'w', encoding='utf-8') as f:
        f.write(f'''<?xml version="1.0" encoding="utf-8"?>
<!-- 自适应图标背景：与品牌标相同的对角渐变（由 tool/brand/generate_logo.py 生成） -->
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <gradient
        android:angle="315"
        android:startColor="{hex_(GREEN_MINT)}"
        android:centerColor="{hex_(GREEN_BRAND)}"
        android:endColor="{hex_(GREEN_DEEP)}"/>
</shape>
''')


if __name__ == '__main__':
    write_svgs()
    write_rasters()
    print('done')
