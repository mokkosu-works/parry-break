#!/usr/bin/env python3
"""ゲームのタイトルロゴ (app/lib/ui/title/title_logo.dart の TitleLogo) を、透明な PNG に描く。

PARRY (からし色、れんが色の影) と BREAK (空色、すみれ色の影) の間に、ボールの軌跡の点線。
動画のロゴは、この画像を使う。ゲームのロゴを変えたら、このスクリプトの値を合わせて作り直す。
出力: promo/assets/logo/title-logo.png (git に入れない素材。既存のファイルは上書きしない場合は --force なしで止まる)
"""
import argparse
import math
import pathlib

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
FONT = ROOT / "app/assets/fonts/Silkscreen-Bold.ttf"
OUT = ROOT / "promo/assets/logo/title-logo.png"

MUSTARD, BRICK = (0xFF, 0xC4, 0x14), (0xF2, 0x38, 0x1F)  # Palette.main / sub
SKY, VIOLET = (0x2E, 0x7B, 0xFF), (0x9A, 0x45, 0xFF)  # Palette.accent / Dot.violet
INK, WHITE, BLACK = (0x07, 0x06, 0x0A), (255, 255, 255), (0, 0, 0)


def dark(c):  # Dot.dark: ink に 0.6 寄せる
    return tuple(round(a + (b - a) * 0.6) for a, b in zip(c, INK))


def render(s=128):
    """PARRY の文字の大きさ s で描く。ゲームと同じ比率 (BREAK は 0.8s、軌跡の幅は 4.7s)。"""
    d = max(3, round(s / 16))
    trail_w, trail_h = round(s * 4.7), d * 8
    gap = round(s * 0.12)
    pad = round(s * 0.7)
    s2 = s * 0.8
    o1, o2 = max(2, round(s / 12)), max(2, round(s2 / 12))
    w = max(round(s * 4.7), pad + round(s2 * 5)) + 2 * max(o1, o2) + 8
    h = s + gap + trail_h + gap + round(s2) + 2 * max(o1, o2) + 8
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)

    def word(text, size, x, y, color, shadow, o):
        font = ImageFont.truetype(str(FONT), round(size))
        base = y + size * 0.914  # 行の高さ size (height: 1) の中での、文字の下端 (実機のロゴで測った比率)
        for dx, col in ((o * 2, BLACK), (o, shadow), (0, color)):
            dr.text((x + dx, base + dx), text, font=font, fill=col + (255,), anchor="ls")

    word("PARRY", s, 0, 0, MUSTARD, BRICK, o1)
    ty = s + gap
    # 点線 (ゲームの _TrailPainter。animate=false の phase 0.3)
    phase, step = 0.3, d * 3
    off = (phase * step * 4) % step
    y = (trail_h / 2 / d // 1) * d
    for i in range(math.floor(trail_w / step)):
        x = i * step + off
        if x > trail_w - d * 6:
            break
        k = x / trail_w
        col = WHITE if k > 0.66 else BRICK if k > 0.33 else dark(BRICK)
        dr.rectangle([math.floor(x), ty + y, math.floor(x) + d - 1, ty + y + d - 1], fill=col + (255,))
    bx, by = trail_w - d * 4, y - d * 1.5 - (d if math.floor(phase * 4) % 2 == 0 else 0)
    dr.rectangle([bx + d, ty + by, bx + d * 3 - 1, ty + by + d * 4 - 1], fill=WHITE + (255,))
    dr.rectangle([bx, ty + by + d, bx + d * 4 - 1, ty + by + d * 3 - 1], fill=WHITE + (255,))
    word("BREAK", s2, pad, ty + trail_h + gap, SKY, VIOLET, o2)
    return im.crop(im.getbbox())


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", type=int, default=184)
    ap.add_argument("--out", default=str(OUT))
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    out = pathlib.Path(a.out)
    if out.exists() and not a.force:
        raise SystemExit(f"既にある: {out} (作り直すなら --force)")
    out.parent.mkdir(parents=True, exist_ok=True)
    img = render(a.size)
    img.save(out)
    print(out, img.size)
