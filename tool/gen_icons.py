"""Genera los iconos de la app (libro abierto + marcador) en tool/android_res/."""
import os
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "android_res")
BG = (0x4B, 0x4B, 0xC8)
BG2 = (0x7A, 0x6B, 0xF0)
PAGE = (0xFF, 0xFF, 0xFF)
PAGE_SHADE = (0xDD, 0xDD, 0xF7)
LINE = (0xB9, 0xB9, 0xE8)
RIBBON = (0xFF, 0x6B, 0x6B)

def draw_book(d, S, k=1.0, mono=False):
    cx, cy = S / 2, S / 2 + 0.01 * S
    u = lambda v: v * S * k
    page = (0, 0, 0, 255) if mono else PAGE
    shade = (0, 0, 0, 255) if mono else PAGE_SHADE
    line = (0, 0, 0, 0) if mono else LINE
    ribbon = (0, 0, 0, 255) if mono else RIBBON
    # base/cubierta inferior
    for sgn in (-1, 1):
        d.polygon([(cx, cy - u(.17) + u(.05)), (cx + sgn * u(.285), cy - u(.235) + u(.05)),
                   (cx + sgn * u(.285), cy + u(.17) + u(.05)), (cx, cy + u(.235) + u(.05))], fill=shade)
    # páginas
    for sgn in (-1, 1):
        d.polygon([(cx + sgn * u(.012), cy - u(.17)), (cx + sgn * u(.26), cy - u(.235)),
                   (cx + sgn * u(.26), cy + u(.16)), (cx + sgn * u(.012), cy + u(.225))], fill=page)
        for i in range(4):
            y0 = -0.10 + i * 0.07
            d.line([(cx + sgn * u(.06), cy + u(y0) + u(.01)), (cx + sgn * u(.21), cy + u(y0) - u(.025))],
                   fill=line, width=max(2, int(u(.012))))
    # marcador
    x0, x1 = cx + u(.09), cx + u(.165)
    top, bot = cy - u(.215), cy + u(.05)
    d.polygon([(x0, top), (x1, top - u(.012)), (x1, bot), ((x0 + x1) / 2, bot - u(.04)), (x0, bot + u(.012))], fill=ribbon)

def gradient(S):
    img = Image.new("RGB", (S, S), BG)
    px = img.load()
    for y in range(S):
        for x in range(S):
            t = (x + y) / (2 * S)
            px[x, y] = tuple(int(BG[i] + (BG2[i] - BG[i]) * t) for i in range(3))
    return img

def render(size, kind):
    SS = 4
    S = size * SS
    if kind == "legacy":
        img = gradient(S).convert("RGBA")
        mask = Image.new("L", (S, S), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * .22), fill=255)
        img.putalpha(mask)
        draw_book(ImageDraw.Draw(img), S, k=1.45)
    else:
        img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        draw_book(ImageDraw.Draw(img), S, k=1.0, mono=(kind == "mono"))
    return img.resize((size, size), Image.LANCZOS)

dens = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
for name, m in dens.items():
    d = os.path.join(OUT, f"mipmap-{name}")
    os.makedirs(d, exist_ok=True)
    render(int(48 * m), "legacy").save(os.path.join(d, "ic_launcher.png"))
    render(int(108 * m), "fg").save(os.path.join(d, "ic_launcher_foreground.png"))
    render(int(108 * m), "mono").save(os.path.join(d, "ic_launcher_monochrome.png"))

v26 = os.path.join(OUT, "mipmap-anydpi-v26")
os.makedirs(v26, exist_ok=True)
open(os.path.join(v26, "ic_launcher.xml"), "w").write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>
</adaptive-icon>
''')
vals = os.path.join(OUT, "values")
os.makedirs(vals, exist_ok=True)
open(os.path.join(vals, "ic_launcher_background.xml"), "w").write('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#5B5BD6</color>
</resources>
''')
# vista previa
prev = render(512, "legacy")
prev.save(os.path.join(os.path.dirname(__file__), "icon_preview.png"))
print("ok")
