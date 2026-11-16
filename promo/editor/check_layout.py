#!/usr/bin/env python3
"""編集ツールのプロジェクトの配置を、書き出す前に確かめる。

    python3 promo/editor/check_layout.py akane-play [akane-modes ...]

確かめること (1080×1920):
- 文字・画像・ゲーム映像の枠・キャラの絵が、上 130px・下 480px (y>1440)・左右 100px の帯に入っていない。
- ショートの右のボタン列 (本人のスマホの YouTube アプリで測った範囲。x>930 かつ y>1220) に何もない。
- キャラの絵 (透明な余白を除く) が、吹き出し・ゲーム映像・タイトル・「ストアで検索」・モードのタグに重なっていない。
- 声の台詞が重ならず、尺に収まる (VOICEVOX が起動している必要がある)。
背景の飾り (斜線・ハート・葉・線) は帯や重なりを気にしないので見ない。問題があれば一覧を出して 1 で終わる。
"""
import sys

import render

TOP, BOTTOM, LEFT, RIGHT = 130, 1440, 100, 980
BUTTONS = (930, 1220)  # この x より右、この y より下はショートのボタン列
AVOID = ("bubble", "store-search", "game", "logo", "logo-parry", "logo-break", "tag")


def visible(layer):
    """レイヤーの、見えている範囲 (キャラは透明な余白を除き、上下の揺れも含める)。"""
    if layer["type"] != "character":
        return [round(v) for v in render._box(layer)]
    l, t, r, b = render.character_pixels(layer).getbbox()
    amp = layer.get("bobAmplitude", 4) if layer.get("bob", True) else 0
    return [layer["x"] + l, layer["y"] + t - amp, layer["x"] + r, layer["y"] + b + amp]


def overlap(character, other):
    """キャラの絵と、ほかのレイヤーの見えている画素が重なる数。"""
    alpha = render.character_pixels(character).getchannel("A").load()
    w, h = render.character_pixels(character).size
    x0, y0, x1, y1 = [round(v) for v in render._box(other)]
    other_alpha = render.image_pixels(other).getchannel("A").load() if other["type"] == "image" else None
    n = 0
    for y in range(max(y0, character["y"]), min(y1, character["y"] + h)):
        for x in range(max(x0, character["x"]), min(x1, character["x"] + w)):
            if alpha[x - character["x"], y - character["y"]] > 40 and (
                    other_alpha is None or other_alpha[x - other["x"], y - other["y"]] > 40):
                n += 1
    return n


def check(name):
    project = render.load_project(name)
    render.check(project)
    problems = []
    for scene in project["scenes"]:
        layers = {l["id"]: l for l in scene["layers"]}
        for layer in scene["layers"]:
            if not layer.get("visible", True) or (layer["type"] == "rect" and layer["id"] != "frame"):
                continue
            x0, y0, x1, y1 = visible(layer)
            where = f"{scene['id']} の {layer.get('name') or layer['id']} ({x0}, {y0})-({x1}, {y1})"
            if y0 < TOP or y1 > BOTTOM or x0 < LEFT or x1 > RIGHT:
                problems.append(f"{where}: 上下左右の帯に入っている")
            if x1 > BUTTONS[0] and y1 > BUTTONS[1]:
                problems.append(f"{where}: ショートのボタン列にかかる")
        character = layers.get("character")
        if character:
            for lid in AVOID:
                if lid in layers and (n := overlap(character, layers[lid])):
                    problems.append(f"{scene['id']}: キャラの絵が {layers[lid].get('name') or lid} に {n} 画素重なる")
    try:
        _, voice = render.voice_timing(render.voice_lines(project), sum(s["duration"] for s in project["scenes"]),
                                       profile=render.voice_profile(project))
        problems += voice
    except render.ExportError as e:
        problems.append(f"声を確かめられない ({e})")
    return problems


def main():
    bad = False
    for name in sys.argv[1:]:
        problems = check(name)
        print(f"{name}: " + ("OK" if not problems else f"{len(problems)} 件"))
        for p in problems:
            print("  - " + p)
        bad |= bool(problems)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
