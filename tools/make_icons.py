#!/usr/bin/env python3
"""アイコンと起動画面の画像を、16 色のドット絵で描いて書き出す。

    python3 tools/make_icons.py

色は app/lib/render/palette.dart の Dot から取る。64 × 64 ドットで描き、
元画像 (app/branding/icons/) と、flutter_launcher_icons / flutter_native_splash が
作るのと同じ名前・大きさの画像 (iOS / Android / Web) を書き出す。
Flutter の環境があれば、元画像だけ使って `dart run flutter_launcher_icons` と
`dart run flutter_native_splash:create` で作り直してもよい。
"""
import math
from pathlib import Path

from PIL import Image

APP = Path(__file__).resolve().parent.parent / "app"
N = 64  # ドットの数 (1 辺)


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


INK = rgb("07060A")
DITHER = rgb("1D1830")
EDGE = rgb("3B3352")
WHITE = rgb("FFFFFF")
BRICK = rgb("F2381F")
MUSTARD = rgb("FFC414")
SKY = rgb("2E7BFF")
VIOLET = rgb("9A45FF")
ORANGE = rgb("FF7A0F")


def light(c):
    return lerp(c, WHITE, 0.55)


def dark(c):
    return lerp(c, INK, 0.6)


def draw():
    im = Image.new("RGB", (N, N), INK)
    px = im.load()

    def rect(x, y, w, h, c):
        for j in range(y, y + h):
            for i in range(x, x + w):
                if 0 <= i < N and 0 <= j < N:
                    px[i, j] = c

    def bevel(x, y, w, h, c):
        # 上と左が明るく、下と右が暗い (pixel.dart の bevelRect と同じ)
        rect(x, y, w, h, c)
        rect(x, y, w, 1, light(c))
        rect(x, y, 1, h, light(c))
        rect(x, y + h - 1, w, 1, dark(c))
        rect(x + w - 1, y + 1, 1, h - 1, dark(c))

    # 床のディザ (下に行くほど濃い)
    for j in range(44, N):
        t = (j - 44) / (N - 44)
        for i in range(N):
            on = (i + j) % 2 == 0 if t > 0.6 else (i % 2 == 0 and j % 2 == 0) if t > 0.3 else (i % 4 == 0 and j % 4 == 0)
            if on:
                px[i, j] = DITHER

    # ブロック 3 列 × 3 段。中央の上は白い要石、右下は壊れて空いている
    rows = [
        (ORANGE, WHITE, ORANGE),
        (VIOLET, VIOLET, VIOLET),
        (MUSTARD, MUSTARD, None),
    ]
    bw, bh, gap = 13, 6, 2
    x0 = (N - (bw * 3 + gap * 2)) // 2
    for r, cols in enumerate(rows):
        for k, c in enumerate(cols):
            if c:
                bevel(x0 + k * (bw + gap), 11 + r * (bh + gap), bw, bh, c)

    # パドル (自分の色は青)
    pw, ph, py = 22, 4, 52
    pxl = (N - pw) // 2
    bevel(pxl, py, pw, ph, SKY)

    # パリィした瞬間の火花 (黄)。弾いた点から放射状に短い線
    sx, sy = 29, py - 1
    for dx, dy in [(-1, -1), (0, -1), (-1, 0), (1, 0)]:
        for k in range(2, 5):
            px[sx + dx * k, sy - 1 + dy * k] = MUSTARD

    # ボールの軌跡 (パドルで弾いて、空いた穴へ向かう)。根元ほど暗い
    bx, by = 45, 33
    steps = 6
    for s in range(2, steps):
        t = s / steps
        i, j = sx + (bx - sx) * t, sy + (by - sy) * t
        c = lerp(BRICK, WHITE, (t - 0.4) / 0.6) if t > 0.4 else lerp(EDGE, BRICK, t / 0.4)
        rect(round(i - 1), round(j - 1), 2, 2, c)

    # ボール (角を落とした白い四角)
    rect(bx - 2, by - 3, 4, 6, WHITE)
    rect(bx - 3, by - 2, 6, 4, WHITE)
    return im


def scaled(art, size):
    """ドットを崩さずに拡大する。割り切れない大きさは、大きく描いてから縮める。"""
    if size % N == 0:
        return art.resize((size, size), Image.NEAREST)
    big = art.resize((N * math.ceil(size / N), N * math.ceil(size / N)), Image.NEAREST)
    return big.resize((size, size), Image.LANCZOS)


def save(art, size, path):
    p = APP / path
    p.parent.mkdir(parents=True, exist_ok=True)
    scaled(art, size).save(p)


def main():
    art = draw()
    res = "android/app/src/main/res"

    # 元画像
    for size, name in [(1024, "icon-1024"), (512, "icon-512"), (512, "icon-maskable-512"),
                       (192, "icon-192"), (180, "apple-touch-icon")]:
        save(art, size, f"branding/icons/{name}.png")

    # iOS のアプリアイコン
    for pt, scales in [(20, (1, 2, 3)), (29, (1, 2, 3)), (40, (1, 2, 3)), (50, (1, 2)), (57, (1, 2)),
                       (60, (2, 3)), (72, (1, 2)), (76, (1, 2)), (83.5, (2,)), (1024, (1,))]:
        for s in scales:
            name = f"{pt:g}x{pt:g}@{s}x"
            save(art, round(pt * s), f"ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-{name}.png")

    # Android のランチャーアイコン (アダプティブアイコンの前景は 108dp)
    for d, k in [("mdpi", 1), ("hdpi", 1.5), ("xhdpi", 2), ("xxhdpi", 3), ("xxxhdpi", 4)]:
        save(art, round(48 * k), f"{res}/mipmap-{d}/ic_launcher.png")
        save(art, round(108 * k), f"{res}/drawable-{d}/ic_launcher_foreground.png")
        # 起動画面
        save(art, round(128 * k), f"{res}/drawable-{d}/splash.png")
        save(art, round(128 * k), f"{res}/drawable-{d}/android12splash.png")
        save(art, round(128 * k), f"{res}/drawable-night-{d}/android12splash.png")

    # 起動画面の背景 (1 × 1)
    for path in [f"{res}/drawable/background.png", f"{res}/drawable-v21/background.png",
                 "ios/Runner/Assets.xcassets/LaunchBackground.imageset/background.png"]:
        Image.new("RGB", (1, 1), INK).save(APP / path)

    # iOS の起動画面
    for s, suffix in [(1, ""), (2, "@2x"), (3, "@3x")]:
        save(art, 128 * s, f"ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage{suffix}.png")

    # Web
    for size, name in [(192, "Icon-192"), (512, "Icon-512"), (192, "Icon-maskable-192"), (512, "Icon-maskable-512")]:
        save(art, size, f"web/icons/{name}.png")
    save(art, 16, "web/favicon.png")


if __name__ == "__main__":
    main()
