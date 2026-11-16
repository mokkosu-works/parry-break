#!/usr/bin/env python3
"""全身3ポーズの口・目だけを合成する。python3 promo/longform/full.py akane

全身はバストアップより顔が小さいため、顔・口・目の範囲を別に設定する。
素材を作り直す場合は既存を同じ場所の old/ へ退避してから実行する。
"""

import argparse
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter
from bust import align, cells, fit_to, largest_blob, shifted

ROOT = Path(__file__).resolve().parents[2]
FULL = ROOT / "promo/characters/full"
POSES = ("greet", "guide", "close")
# akane_full_sheet.png を margin=16 で切り出した320×504pxの枠内の座標。
# 口の範囲は目・輪郭・手を含めず、開いた口全体と周囲の肌を含める。
AKANE = {
    "greet": {"face": [108, 108, 247, 225], "align": [121, 137, 237, 181], "mouth": [164, 182, 204, 212]},
    "guide": {"face": [108, 108, 247, 225], "align": [121, 137, 237, 181], "mouth": [164, 182, 204, 212]},
    "close": {"face": [108, 108, 247, 225], "align": [121, 137, 237, 181], "mouth": [164, 182, 204, 212]},
}


def paste_region(base, donor, area, align_area, reach=10):
    dx, dy = align(base, donor, align_area, reach=reach)
    donor = shifted(donor, dx, dy)
    mask = Image.new("L", base.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(area, radius=5, fill=255)
    # 合成の端を肌になじませる。ぼかした範囲も指定の箱内に限る。
    mask = mask.filter(ImageFilter.GaussianBlur(1.5))
    limit = Image.new("L", base.size, 0)
    ImageDraw.Draw(limit).rectangle(area, fill=255)
    mask = ImageChops.multiply(mask, limit)
    mask = ImageChops.multiply(mask, donor.getchannel("A"))
    out = base.copy()
    out.paste(donor, (0, 0), mask)
    out.putalpha(base.getchannel("A"))
    diff = ImageChops.difference(base, out).convert("RGB").getbbox()
    if not diff:
        raise ValueError("合成後に変化がありません")
    if not (area[0] <= diff[0] < diff[2] <= area[2] + 1 and area[1] <= diff[1] < diff[3] <= area[3] + 1):
        raise ValueError(f"合成範囲の外が変化しました: {diff}")
    return out, {"offset": [dx, dy], "changed_box": list(diff)}


def main(name):
    out = FULL / name
    out.mkdir(exist_ok=True)
    expected = [out / f"{p}_{s}.png" for p in POSES for s in ("closed", "open")]
    expected += [out / "greet_blink.png", out / "regions.json"]
    if any(p.exists() for p in expected):
        raise SystemExit("既存素材があります。作り直す前に同じ場所の old/ へ退避してください。")
    grid = cells(FULL / f"{name}_full_sheet.png", cols=3, rows=2, margin=16)
    if grid[0][0].size != (320, 504):
        raise SystemExit("シートの大きさが変わっています。顔・口・目の座標を確認してください。")
    report = {}
    frames = {}
    for i, pose in enumerate(POSES):
        base = grid[0][i]
        config = AKANE[pose]
        mouth, details = paste_region(base, grid[1][i], config["mouth"], config["align"])
        frames[pose] = {"closed": base, "open": mouth}
        report[pose] = {**config, "mouth_result": details}
    base = frames["greet"]["closed"]
    donor = largest_blob(Image.open(FULL / f"{name}_full_blink.png").convert("RGBA"))
    donor = fit_to(donor, base)
    # 目を閉じると目自体は位置合わせに使えないため、頭頂・髪飾りの範囲で合わせる。
    eyes = [123, 143, 237, 184]
    blink, details = paste_region(base, donor, eyes, [85, 45, 245, 138], reach=12)
    frames["greet"]["blink"] = blink
    report["greet"]["eyes"] = eyes
    report["greet"]["blink_result"] = details
    for pose, states in frames.items():
        for state, im in states.items():
            # アルファ0のRGBは生成時の色を持つことがあるため、完全透明の画素だけ0へ揃える。
            clean = Image.new("RGBA", im.size)
            clean.paste(im, (0, 0))
            pixels = clean.load()
            for y in range(clean.height):
                for x in range(clean.width):
                    if pixels[x, y][3] == 0:
                        pixels[x, y] = (0, 0, 0, 0)
            clean.save(out / f"{pose}_{state}.png")
    (out / "regions.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("name", choices=["akane"])
    main(parser.parse_args().name)
