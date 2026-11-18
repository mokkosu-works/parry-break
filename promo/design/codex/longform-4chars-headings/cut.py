#!/usr/bin/env python3
"""run.sh で作った見出しのシートを 1 行ずつ切り出し、promo/assets/text/longform/ に置く。

python3 promo/design/codex/longform-4chars-headings/cut.py            # できているシートを全部
python3 promo/design/codex/longform-4chars-headings/cut.py akane-a    # 指定したシートだけ

ごく薄い画素(生成のノイズ)を透明に塗り直し、透明な行で区切って、上から順に名前を付ける。行の数が合わない・背景が透明でない
シートは切り出さずに止まる(作り直すか、手で直す)。既にある画像は上書きしない。
"""

from pathlib import Path
import sys

from PIL import Image

HERE = Path(__file__).resolve().parent
DEST = HERE.parents[2] / "assets/text/longform"
# シートの上から順に、置く名前(<名前>-<場面>-v01.png。版を付けた名前はそのまま)。場面の番号は絵コンテの章と同じ。
SHEETS = {
    "akane-a": ["akane-ch02", "akane-ch03", "akane-ch04"],
    "akane-c": ["akane-ending-v02"],  # 「!」付きに作り直した版(2026-11-18)
    "shizuku-a": ["shizuku-opening", "shizuku-ch01", "shizuku-ch02"],
    "shizuku-b": ["shizuku-ch03", "shizuku-ch04", "shizuku-ch05"],
    "shizuku-c": ["shizuku-ending"],
    "momoka-a": ["momoka-opening", "momoka-ch01", "momoka-ch02"],
    "momoka-b": ["momoka-ch03", "momoka-ch04"],
    "wakana-a": ["wakana-opening", "wakana-ch01", "wakana-ch02"],
    "wakana-b": ["wakana-ch03", "wakana-ch04"],
}
ALPHA = 24      # これより薄い画素は透明とみなす(縁のにじみを拾わない)
MIN_GAP = 12    # 行と行のあいだの透明な高さ(これより短い切れ目は 1 行の中とみなす)
MIN_BAND = 40   # これより低いかたまりはごみとして捨てる
PAD = 8


def bands(im):
    alpha = im.getchannel("A").point(lambda a: 255 if a >= ALPHA else 0)
    width, height = alpha.size
    rows = [alpha.crop((0, y, width, y + 1)).getbbox() is not None for y in range(height)]
    found, start, gap = [], None, 0
    for y, filled in enumerate(rows + [False] * MIN_GAP):
        if filled:
            if start is None:
                start = y
            gap = 0
        elif start is not None:
            gap += 1
            if gap >= MIN_GAP:
                end = y - gap + 1
                if end - start >= MIN_BAND:
                    found.append((start, end))
                start, gap = None, 0
    return found


def cut(key):
    sheet = HERE / f"out/headings_{key}.png"
    names = SHEETS[key]
    im = Image.open(sheet).convert("RGBA")
    # 画像生成は、地にごく薄い画素(アルファ 1〜23)を散らすことがある。透明に塗り直してから扱う。
    im.putalpha(im.getchannel("A").point(lambda a: a if a >= ALPHA else 0))
    histogram = im.getchannel("A").histogram()
    transparent = histogram[0] / (im.width * im.height)
    if transparent < 0.3:
        raise SystemExit(f"{key}: 背景が透明ではありません(透明 {transparent:.0%})。作り直してください")
    found = bands(im)
    if len(found) != len(names):
        raise SystemExit(f"{key}: 行が {len(found)} 個見つかりました({len(names)} 個のはず)。シートを見て直してください")
    for (top, bottom), name in zip(found, names):
        dest = DEST / (f"{name}.png" if name[-4:-2] == "-v" else f"{name}-v01.png")
        if dest.exists():
            print(f"既にあります(飛ばす): {dest.name}")
            continue
        row = im.crop((0, top, im.width, bottom))
        row = row.crop(row.getchannel("A").point(lambda a: 255 if a >= ALPHA else 0).getbbox())
        out = Image.new("RGBA", (row.width + PAD * 2, row.height + PAD * 2), (0, 0, 0, 0))
        out.alpha_composite(row, (PAD, PAD))
        out.save(dest)
        print(f"{dest.relative_to(HERE.parents[3])} {out.size}")


def main():
    keys = sys.argv[1:] or [k for k in SHEETS if (HERE / f"out/headings_{k}.png").exists()]
    for key in keys:
        if key not in SHEETS:
            raise SystemExit(f"知らないシートです: {key}({', '.join(SHEETS)})")
        cut(key)


if __name__ == "__main__":
    main()
