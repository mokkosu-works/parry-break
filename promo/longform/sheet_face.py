#!/usr/bin/env python3
"""全身 6 ポーズのシートに、口パク・目パチ用の絵を足す。ショートと通常尺で共通に使う。

python3 promo/longform/sheet_face.py mitsuba

入力:
  promo/characters/sheets/<名前>_sheet.png            元のシート(2172×724、1 ポーズ 362×724 が 6 つ)
  promo/design/codex/sheets-face/out/<名前>_mouth.png  口だけを反対の状態にしたシート(Codex)
  promo/design/codex/sheets-face/out/<名前>_blink.png  目だけを閉じたシート(Codex)
  promo/design/codex/sheets-face/out/<名前>_blink_<ポーズ>.png  シートでうまくいかなかったポーズだけ、1 体で作り直した目パチ(あれば使う)
出力(どれも元のシートと同じ 2172×724。不透明な部分の形も元と同じ):
  promo/characters/sheets/<名前>/closed.png  全ポーズが口を閉じた版
  promo/characters/sheets/<名前>/open.png    全ポーズが口を開いた版
  promo/characters/sheets/<名前>/blink.png   全ポーズが目を閉じた版(目を閉じたポーズは closed と同じ)
  promo/characters/sheets/<名前>/regions.json

土台は元のシートの枠そのもの。生成した絵は位置を合わせ、口と目のまわりだけを貼る。
元の絵は閉じ・開きのどちらか片方としてそのまま使う。アルファは元と同じなので、
ショートの「輪郭で分離」(editor/sprites.py の isolate_sheet)で、元と同じ位置・大きさに切り出される。
既存の出力は上書きしない。作り直すときは同じ場所の old/ へ退避してから実行する。
"""

import argparse
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter
from bust import align, shifted

ROOT = Path(__file__).resolve().parents[2]
SHEETS = ROOT / "promo/characters/sheets"
DRAFTS = ROOT / "promo/design/codex/sheets-face/out"
CELL = (362, 724)
POSES = ("normal", "focus", "surprise", "fail", "success", "special")  # 通常・集中・予想外・失敗・成功・固有

# キャラ × ポーズの設定。座標は 362×724 の枠の中。
# natural: 元の絵の口が closed(閉じ)か open(開き)か。もう片方を合成する。
# mouth: 口を貼る範囲(閉じ・開きの両方の口と周りの肌を含め、目・輪郭・手を含めない)
# eyes: 目を貼る範囲。None は目を閉じたポーズ(目パチを作らない)
# face: 確認用に顔を拡大するときの範囲(省略したら口と目から決める。face_box)
# blink_align: 目パチの位置合わせに使う範囲(省略したら目の上の前髪と額)
CHARS = {
    "mitsuba": {
        "normal":   {"natural": "closed", "mouth": [212, 288, 286, 328], "eyes": [155, 225, 305, 296], "face": [120, 160, 330, 345]},
        "focus":    {"natural": "closed", "mouth": [204, 302, 276, 338], "eyes": [150, 240, 310, 312], "face": [120, 180, 330, 355]},
        "surprise": {"natural": "open",   "mouth": [188, 284, 252, 326], "eyes": [125, 222, 288, 300], "face": [100, 160, 310, 340]},
        "fail":     {"natural": "closed", "mouth": [188, 342, 250, 378], "eyes": [148, 278, 302, 346], "face": [110, 220, 320, 390]},
        "success":  {"natural": "open",   "mouth": [168, 270, 250, 334], "eyes": None,                 "face": [100, 180, 300, 350]},
        "special":  {"natural": "open",   "mouth": [168, 283, 246, 336], "eyes": [114, 204, 278, 296], "face": [90, 150, 300, 345]},
    },
    "akane": {
        "normal":   {"natural": "closed", "mouth": [202, 272, 262, 318], "eyes": [158, 212, 316, 272]},
        "focus":    {"natural": "closed", "mouth": [222, 312, 258, 346], "eyes": [170, 255, 316, 306]},
        "surprise": {"natural": "open",   "mouth": [230, 262, 266, 292], "eyes": [120, 200, 286, 266]},
        "fail":     {"natural": "closed", "mouth": [212, 330, 268, 376], "eyes": [160, 284, 316, 332]},
        "success":  {"natural": "open",   "mouth": [210, 224, 266, 284], "eyes": None},
        "special":  {"natural": "closed", "mouth": [174, 284, 236, 330], "eyes": [122, 214, 290, 298]},
    },
    "shizuku": {
        "normal":   {"natural": "closed", "mouth": [234, 264, 278, 290], "eyes": [172, 212, 316, 268]},
        "focus":    {"natural": "closed", "mouth": [240, 274, 274, 294], "eyes": [170, 210, 316, 272]},
        "surprise": {"natural": "open",   "mouth": [232, 268, 262, 292], "eyes": [148, 204, 306, 276]},
        "fail":     {"natural": "closed", "mouth": [198, 292, 238, 314], "eyes": [136, 236, 290, 290]},
        "success":  {"natural": "closed", "mouth": [190, 262, 234, 290], "eyes": [132, 196, 272, 262]},
        "special":  {"natural": "closed", "mouth": [196, 262, 240, 286], "eyes": [122, 196, 272, 262]},
    },
    "momoka": {
        "normal":   {"natural": "open",   "mouth": [250, 278, 298, 314], "eyes": [184, 218, 338, 282]},
        "focus":    {"natural": "closed", "mouth": [240, 298, 282, 322], "eyes": [176, 240, 322, 296]},
        "surprise": {"natural": "open",   "mouth": [246, 278, 280, 310], "eyes": [154, 226, 330, 284]},
        "fail":     {"natural": "closed", "mouth": [240, 290, 282, 320], "eyes": [160, 236, 316, 296]},
        "success":  {"natural": "open",   "mouth": [226, 272, 280, 310], "eyes": None},
        "special":  {"natural": "closed", "mouth": [218, 302, 272, 328], "eyes": [150, 236, 316, 302]},
    },
    "wakana": {
        "normal":   {"natural": "closed", "mouth": [246, 268, 296, 294], "eyes": [178, 212, 322, 270]},
        "focus":    {"natural": "closed", "mouth": [234, 274, 272, 300], "eyes": [172, 212, 316, 270]},
        "surprise": {"natural": "open",   "mouth": [236, 268, 268, 294], "eyes": [152, 212, 290, 268]},
        "fail":     {"natural": "open",   "mouth": [226, 274, 262, 302], "eyes": [148, 222, 296, 272]},
        "success":  {"natural": "closed", "mouth": [212, 270, 264, 304], "eyes": None},
        "special":  {"natural": "closed", "mouth": [204, 270, 252, 298], "eyes": [142, 222, 292, 270]},
    },
}


def face_box(c):
    """確認用に顔を拡大する範囲。指定がなければ口と目の範囲から決める。"""
    if "face" in c:
        return c["face"]
    boxes = [c["mouth"]] + ([c["eyes"]] if c["eyes"] else [])
    top = min(b[1] for b in boxes)
    return [min(b[0] for b in boxes) - 40, top - 70, max(b[2] for b in boxes) + 30, c["mouth"][3] + 25]


def paste_region(base, donor, area, align_area, reach=12):
    """donor を align_area で base に合わせ、area の中だけを貼る。area の外が変わったら止める。"""
    dx, dy = align(base, donor, align_area, reach=reach)
    donor = shifted(donor, dx, dy)
    mask = Image.new("L", base.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(area, radius=6, fill=255)
    # 合成の端を肌になじませる。ぼかした範囲も指定の箱の中に限る。
    mask = mask.filter(ImageFilter.GaussianBlur(1.5))
    limit = Image.new("L", base.size, 0)
    ImageDraw.Draw(limit).rectangle(area, fill=255)
    mask = ImageChops.multiply(ImageChops.multiply(mask, limit), donor.getchannel("A"))
    out = base.copy()
    out.paste(donor, (0, 0), mask)
    out.putalpha(base.getchannel("A"))
    diff = ImageChops.difference(base, out).convert("RGB").getbbox()
    if not diff:
        raise ValueError("合成後に変化がありません")
    if not (area[0] <= diff[0] < diff[2] <= area[2] + 1 and area[1] <= diff[1] < diff[3] <= area[3] + 1):
        raise ValueError(f"合成範囲の外が変化しました: {diff}")
    return out, {"offset": [dx, dy], "changed_box": list(diff)}


def cell(sheet, i):
    return sheet.crop((CELL[0] * i, 0, CELL[0] * (i + 1), CELL[1]))


def clean(im):
    """アルファ0の画素の色を0にそろえる(生成時の色が残ることがあるため)。"""
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    mask = im.getchannel("A").point(lambda a: 255 if a else 0)
    out.paste(im, (0, 0), mask)
    out.putalpha(im.getchannel("A"))
    return out


def blink_donor(name, pose, blink_sheet, i):
    """目パチの元の絵。シートでうまくいかなかったポーズは、1 体だけ作り直した <名前>_blink_<ポーズ>.png を使う。"""
    single = DRAFTS / f"{name}_blink_{pose}.png"
    if not single.exists():
        return cell(blink_sheet, i)
    donor = Image.open(single).convert("RGBA")
    if donor.size != CELL:
        # 枠をそのまま拡大した大きさで返ってくる。縦横比が違うときは位置が合わないので止める。
        if abs(donor.width / donor.height - CELL[0] / CELL[1]) > .01:
            raise SystemExit(f"{single.name}: 縦横比が枠(362×724)と違います")
        donor = donor.resize(CELL, Image.Resampling.LANCZOS)
    return donor


def main(name):
    config = CHARS[name]
    out_dir = SHEETS / name
    out_dir.mkdir(exist_ok=True)
    expected = [out_dir / f"{s}.png" for s in ("closed", "open", "blink")] + [out_dir / "regions.json"]
    if any(p.exists() for p in expected):
        raise SystemExit("既存の素材があります。作り直す前に同じ場所の old/ へ退避してください。")
    sheet = Image.open(SHEETS / f"{name}_sheet.png").convert("RGBA")
    mouth_sheet = Image.open(DRAFTS / f"{name}_mouth.png").convert("RGBA")
    blink_sheet = Image.open(DRAFTS / f"{name}_blink.png").convert("RGBA")
    for im in (sheet, mouth_sheet, blink_sheet):
        if im.size != (CELL[0] * 6, CELL[1]):
            raise SystemExit(f"シートの大きさが {im.size} です({CELL[0] * 6}×{CELL[1]} のはず)。")
    outs = {s: sheet.copy() for s in ("closed", "open", "blink")}
    report = {}
    for i, pose in enumerate(POSES):
        c = config[pose]
        base = cell(sheet, i)
        eyes = c["eyes"]
        # 口の位置合わせは、口を含まない顔の上半分(目のまわり)で行う。目を閉じたポーズは口の上の帯を使う。
        mouth_align = eyes or [c["mouth"][0] - 30, c["mouth"][1] - 70, c["mouth"][2] + 30, c["mouth"][1] - 4]
        other, mouth_result = paste_region(base, cell(mouth_sheet, i), c["mouth"], mouth_align)
        states = {c["natural"]: base, ("open" if c["natural"] == "closed" else "closed"): other}
        entry = {**c, "face": face_box(c), "mouth_result": mouth_result}
        if eyes:
            # 目を閉じると目では合わせられないので、目の上(前髪と額)で合わせる。
            # 前髪だけでは縦のずれを見誤るポーズは、blink_align で頭全体などを指定する。
            blink_align = c.get("blink_align") or [eyes[0], max(0, eyes[1] - 80), eyes[2], eyes[1] - 4]
            states["blink"], entry["blink_result"] = paste_region(states["closed"], blink_donor(name, pose, blink_sheet, i), eyes, blink_align)
        else:
            states["blink"] = states["closed"]
        # 枠ごと貼り戻す。枠の中の、隣の人物の髪などは元のままなので変わらない。
        for state, im in states.items():
            outs[state].paste(im, (CELL[0] * i, 0))
        report[pose] = entry
    for state, im in outs.items():
        if im.getchannel("A").tobytes() != sheet.getchannel("A").tobytes():
            raise SystemExit(f"{state}: アルファが元のシートと違います")
        clean(im).save(out_dir / f"{state}.png")
    (out_dir / "regions.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    for pose, entry in report.items():
        print(pose, "口", entry["mouth_result"], "目", entry.get("blink_result", "なし"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("name", choices=sorted(CHARS))
    main(parser.parse_args().name)
