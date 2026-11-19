#!/usr/bin/env python3
"""字形を確かめ済みの見出しの縁の色だけを、別のキャラの色に塗り替える(画像生成を使わない)。

python3 promo/design/codex/longform-4chars-headings/recolor.py shizuku-ending-v01.png momoka-ending-v01.png 180,14,68

元の縁の濃い色(いちばん多い暗い色)から白までの明るさを、新しい縁の色から白までに写す。白い文字はそのまま、
外側の明るい縁は薄い新しい色になる。透明度は変えない。既にある画像は上書きしない。
2026-11-19、モモカの「ストアで検索!」をシズクの版から作った。
"""

from collections import Counter
from pathlib import Path
import sys

from PIL import Image

DEST = Path(__file__).resolve().parents[3] / "assets/text/longform"


def recolor(src, dest, color):
    if dest.exists():
        raise SystemExit(f"既にあります(上書きしません): {dest}")
    im = Image.open(src).convert("RGBA")
    pixels = list(im.getdata())
    dark = Counter(p[:3] for p in pixels if p[3] > 250 and sum(p[:3]) < 300).most_common(1)[0][0]
    base = sum(dark) / 3
    out = []
    for r, g, b, a in pixels:
        t = min(1.0, max(0.0, ((r + g + b) / 3 - base) / (255 - base)))
        out.append(tuple(round(c * (1 - t) + 255 * t) for c in color) + (a,))
    im.putdata(out)
    im.save(dest)
    print(f"{dest} {im.size} 元の縁 {dark} → {color}")


if __name__ == "__main__":
    src, dest, color = sys.argv[1:4]
    recolor(DEST / src, DEST / dest, tuple(int(c) for c in color.split(",")))
