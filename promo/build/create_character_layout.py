"""キャラ別動画 v05: 画面構成案 (promo/design/character-layout-comparison-v01.png) の見た目に揃える。

v02 のプロジェクトから録画・ポーズ・背景の飾りを引き継ぎ、配置を構成案に合わせる。
- 見出し・吹き出し・「ストアで検索」は、構成案を参考に Codex (画像生成) で作った透過 PNG
  (promo/characters/text/)。文言を変えるときは画像を作り直す。
- タイトルはゲームの Silkscreen の PARRY / BREAK (構成案のロゴは画像生成が描いたもので、ゲームのものではない)。
- アウトロは、本人が編集ツールで調整したミツバ v05 の配置を型にする (OUTRO_TEMPLATE)。
  キャラ・アイコン・タイトル・「ストアで検索」・ストアのバッジ・吹き出し・クレジットだけで、ゲーム映像なし。
- 本人の指示で、全員キャラを左に置く (構成案ではアカネとモモカが右)。
- キャラの絵はゲーム画面の枠と重ならないよう、枠の下から下 480px の帯の上までに収まる大きさにする。

    python3 promo/build/create_character_layout.py akane shizuku momoka wakana

既にあるプロジェクトは上書きせず飛ばす。微調整は編集ツールで行う。経緯は promo/design/shorts-play.md。
"""
import copy
import json
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
PROJECTS = ROOT / "promo/editor/projects"
ASSETS = ROOT / "promo/characters/text"
REL = "../../characters/text/"
SILKSCREEN = "../../../app/assets/fonts/Silkscreen-Bold.ttf"
VERSION = "v05"
OUTRO_TEMPLATE = "mitsuba-play"

# 1080×1920 の配置。左右 100px の内側、上 130px と下 480px (y>1440) は編集ツールのセーフエリアに合わせて空ける。
SAFE_L, SAFE_R, SAFE_B = 100, 980, 1440
HEADLINE_TOP, HEADLINE_H = 175, 170
GAME = {"x": 150, "y": 380, "width": 780, "height": 468}
CHAR = {"x": 85, "y": 736, "height": 704}
BUBBLE = {"x": 470, "y": 880, "width": 470}

FINAL_LINE = 19  # アウトロの声: 19 秒に「パリィブレイク。ストアで検索！」、21.5 秒にキャラの締めの一言
CLOSING_LINE = 21.5

CHARACTERS = {
    "mitsuba": {
        "background": "#FDF3D3", "accent": "#F2C230", "dots": True,
        "headlines": ["mitsuba_v05_headline_1.png", "mitsuba_v05_headline_2b.png", "mitsuba_headline_3.png"],
        "bubbles": ["mitsuba_v05_bubble_1.png", "mitsuba_v05_bubble_2.png", "mitsuba_v05_bubble_3.png",
                    "mitsuba_bubble_4.png"],
        "store_search": "mitsuba_v05_store_search.png",
        "voice": [(0.1, "この弾、打ち返せる？"), (3.3, "パドルに当たる直前に、タップ！"), (7.2, "わっ、打ち返せた！"),
                  (11.3, "白いブロックを壊すと……"), (15.5, "一気に、崩れた！"),
                  (FINAL_LINE, "パリィブレイク。ストアで検索！"), (CLOSING_LINE, "一緒に遊ぼう！")],
    },
    "akane": {
        "background": "#28181C",
        "voice": [(0.1, "くっ、今の惜しい！"), (3.2, "次こそ打ち返す！"), (8, "よし、いくよ！"),
                  (11.4, "まだまだ、点を伸ばす！"),
                  (FINAL_LINE, "パリィブレイク。ストアで検索！"), (CLOSING_LINE, "もう一勝負！")],
    },
    "shizuku": {
        "background": "#121F35",
        "voice": [(0.1, "この音、聞いて。"), (3.3, "パドルに当たる直前に、合わせて。"), (11.3, "音が揃うと、気持ちいい。"),
                  (FINAL_LINE, "パリィブレイク。ストアで検索。"), (CLOSING_LINE, "次は、あなたの番。")],
    },
    "momoka": {
        "background": "#FFF0F5",
        # 全員キャラを左に置くので、しっぽを左向きにした吹き出し (枠だけ反転して文字を戻したもの)
        "bubbles": [f"momoka_v05_bubble_{i}_left.png" for i in (1, 2, 3)] + ["momoka_v05_bubble_4.png"],
        "voice": [(0.1, "今の、見てた？"), (3.3, "少し前から、もう一回！"), (7, "ここが、好きなの。"),
                  (11.3, "これ、見せたくなるよね。"),
                  (FINAL_LINE, "パリィブレイク。ストアで検索！"), (CLOSING_LINE, "あなたも、遊んでみて！")],
    },
    "wakana": {
        "background": "#EFF5E8",
        "voice": [(0.1, "今日は、一面ずつ。"), (3.3, "まずは、目の前の一面から。"), (11.3, "うん、クリアできたね。"),
                  (16, "次も、あなたのペースで。"),
                  (FINAL_LINE, "パリィブレイク。ストアで検索。"), (CLOSING_LINE + 0.3, "ゆっくりで、大丈夫。")],  # 声がゆっくりなので後ろへ
    },
}
for _name, _style in CHARACTERS.items():
    _style.setdefault("headlines", [f"{_name}_v05_headline_{i}.png" for i in (1, 2, 3)])
    _style.setdefault("bubbles", [f"{_name}_v05_bubble_{i}.png" for i in (1, 2, 3, 4)])
    _style.setdefault("tag", f"{_name}_tag_stage.png")  # プレイ紹介はステージの録画なので、全員「ステージ」
    _style.setdefault("store_search", f"{_name}_v05_store_search.png")

NOT_DECOR = ("frame", "speech-panel", "headline-swoosh", "spark-", "dot-")


def dots(color):
    """右上の四角いドットの面と、左下の三角形のドットの面 (ミツバの構成案の飾り)。"""
    out = [(850 + c * 30, 40 + r * 30) for r in range(5) for c in range(7)]
    out += [(30 + c * 30, 1610 + r * 30) for r in range(6) for c in range(6 - r)]
    return [{"id": f"dot-{i}", "name": f"dot-{i}", "type": "rect", "visible": True, "x": x, "y": y,
             "width": 10, "height": 10, "color": color, "strokeWidth": 1, "shape": "dot", "tail": "left", "fill": color}
            for i, (x, y) in enumerate(out)]


def decor(scene, style):
    """v02 の背景の飾り (斜線・線・ハート・葉)。見出しの下線や吹き出しの枠は除く。"""
    out = [l for l in scene["layers"] if l["type"] == "rect" and not l["id"].startswith(NOT_DECOR)]
    return out + (dots(style["accent"]) if style.get("dots") else [])


def size_of(file):
    with Image.open(ASSETS / file) as im:
        return im.size


def image_layer(lid, name, file, x, y, width=None, height=None):
    w, h = size_of(file)
    if width is None:
        width = round(height * w / h)
    if height is None:
        height = round(width * h / w)
    return {"id": lid, "type": "image", "name": name, "visible": True, "x": round(x), "y": round(y),
            "width": round(width), "height": round(height), "src": REL + file, "opacity": 1, "resample": "lanczos"}


def headline(file):
    w, h = size_of(file)
    height = HEADLINE_H
    width = height * w / h
    if width > SAFE_R - SAFE_L:  # 長い見出しは幅で合わせる
        width = SAFE_R - SAFE_L
        height = width * h / w
    return image_layer("headline", "見出し", file, (1080 - width) / 2, HEADLINE_TOP + (HEADLINE_H - height) / 2,
                       width, height)


def bubble(file, x, y, max_width, max_height):
    """枠の中に収まる最大の大きさで置く。"""
    w, h = size_of(file)
    width = min(max_width, max_height * w / h)
    return image_layer("bubble", "吹き出し", file, x, y, width=width)


def text_width(word, size, stroke):
    font = ImageFont.truetype(str((PROJECTS / SILKSCREEN).resolve()), size)
    return ImageDraw.Draw(Image.new("RGBA", (1, 1))).textbbox((0, 0), word, font=font, stroke_width=stroke)[2]


LOGO_FILE = ROOT / "promo/build/assets/layout/title-logo.png"  # create_title_logo.py が作る、ゲームの実物のロゴ
LOGO_RATIO = 355 / 84  # 幅 / size。既存の動画の大きさに合わせる


def title_width(old=None, size=84):
    return round(size * LOGO_RATIO)


def title(old, x, y=1245, size=84):
    """ゲームの PARRY BREAK のロゴ (画像 1 枚)。左端を x に揃える。"""
    w, h = Image.open(LOGO_FILE).size
    width = title_width(size=size)
    return [{"id": "logo", "type": "image", "name": "ロゴ", "visible": True, "x": round(x), "y": y,
             "width": width, "height": round(width * h / w), "src": "../../build/assets/layout/title-logo.png",
             "opacity": 1, "resample": "bicubic"}]


def visible_box(character):
    """キャラの絵の、透明な余白を除いた範囲 (レイヤーの左上からの相対)。"""
    sys.path.insert(0, str(ROOT / "promo/editor"))
    import render
    return render.character_pixels(character).getbbox()


def fit_character(character):
    """絵 (透明な余白を除く) をゲーム枠の下から y=1435 までに収め、左端を 100px の内側に揃える。"""
    top = GAME["y"] + GAME["height"] + 9 + 16  # 枠の線 + 揺れ (4px) + すき間
    bottom = SAFE_B - 5 - character.get("bobAmplitude", 4)
    _, t, _, b = visible_box(character)
    if b - t > bottom - top:  # 髪やリボンが高いポーズは縮める
        character["height"] = int(character["height"] * (bottom - top) / (b - t))
        _, t, _, b = visible_box(character)
    character["y"] = round(bottom - b)
    if character["y"] + t < top:
        character["y"] = round(top - t)
    l, _, _, _ = visible_box(character)
    character["x"] = max(CHAR["x"], SAFE_L + 10 - l)


def play_layers(old, style, i):
    game = copy.deepcopy(old["game"])
    game.update(GAME)
    frame = {"id": "frame", "name": "frame", "type": "rect", "visible": True,
             "x": GAME["x"] - 9, "y": GAME["y"] - 9, "width": GAME["width"] + 18, "height": GAME["height"] + 18,
             "color": "#1E1B24", "strokeWidth": 4, "shape": "rect", "tail": "left", "radius": 14, "fill": "#1E1B24"}
    character = copy.deepcopy(old["character"])
    character.update(CHAR)
    fit_character(character)
    speech = bubble(style["bubbles"][i], BUBBLE["x"], BUBBLE["y"], BUBBLE["width"], 300)
    speech["x"] = min(speech["x"], SAFE_R - speech["width"])
    title_x = SAFE_R - 30 - title_width(old)
    # 横長の吹き出しは少し下げて、キャラの顔の高さに合わせる
    speech["y"] += max(0, (300 - speech["height"]) // 3)
    layers = [headline(style["headlines"][i]), frame, game]
    if style.get("tag"):  # ゲーム画面の右下に重ねるモードのタグ
        tag = image_layer("tag", "モードのタグ", style["tag"], 0, 0, height=60)  # 大きさと位置はモード紹介と同じ
        tag.update({"x": frame["x"] + frame["width"] - tag["width"] - 12, "y": frame["y"] + frame["height"] - 32})
        layers.append(tag)
    return layers + [character, speech, *title(old, title_x)]


def character_right(character, y0, y1):
    """キャラの絵 (透明な余白を除く) の、y0〜y1 の行での右端。"""
    sys.path.insert(0, str(ROOT / "promo/editor"))
    import render
    px = render.character_pixels(character)
    alpha = px.getchannel("A").load()
    w, h = px.size
    right = 0
    for yy in range(max(0, y0 - character["y"]), min(h, y1 - character["y"])):
        for xx in range(w - 1, right - 1, -1):
            if alpha[xx, yy] > 40:
                right = xx
                break
    return character["x"] + right


def avoid_character(layer, character, box, gap=12):
    """吹き出しをキャラの右に寄せ、はみ出す分は縮める (縦の中心は box に揃えたまま)。"""
    w, h = size_of(layer["src"].rsplit("/", 1)[1])
    for _ in range(4):
        right = character_right(character, layer["y"], layer["y"] + layer["height"])
        if layer["x"] >= right + gap:
            return
        layer["x"] = right + gap
        if layer["x"] + layer["width"] > SAFE_R:
            layer["width"] = SAFE_R - layer["x"]
            layer["height"] = round(layer["width"] * h / w)
            layer["y"] = round(box["y"] + box["height"] / 2 - layer["height"] / 2)


def outro_layers(old, style, template):
    """本人が調整したミツバのアウトロの配置を使い、絵と色だけキャラごとに替える。"""
    t = {l["id"]: l for l in template["layers"]}
    out = []
    for lid in [l["id"] for l in template["layers"] if not l["id"].startswith(("dot-", "top-stripe", "bottom-stripe"))]:
        if lid == "character":
            layer = copy.deepcopy(old["character"])
            layer.update({k: t[lid][k] for k in ("x", "y", "height", "bob")})
            l, _, _, _ = visible_box(layer)  # キャラごとに絵の幅が違うので、左端を 100px の内側に
            layer["x"] = max(layer["x"], SAFE_L + 10 - l)
        elif lid == "bubble":
            box = t[lid]  # この枠の中に収める。2 行の吹き出しは縦に伸びるので、中心を揃える
            layer = bubble(style["bubbles"][3], box["x"], 0, box["width"], 250)
            layer["y"] = round(box["y"] + box["height"] / 2 - layer["height"] / 2)
            layer["x"] = min(layer["x"], SAFE_R - layer["width"])
            avoid_character(layer, out[0], box)
        elif lid == "store-search":
            box = t[lid]
            layer = image_layer(lid, "ストアで検索", style["store_search"], 0, box["y"], height=box["height"])
            layer["x"] = round(box["x"] + box["width"] / 2 - layer["width"] / 2)
            avoid_character(layer, out[0], {"y": box["y"], "height": box["height"]})  # 差し出した手にかからないように
        elif lid in ("logo", "credit"):
            layer = copy.deepcopy(old[lid])  # 色は v02 のキャラごとの色のまま
            layer.update({k: t[lid][k] for k in ("x", "y", "fontSize")})
        else:  # app-icon, badge-*
            layer = copy.deepcopy(t[lid])
        out.append(layer)
    return out


def build(chara):
    src = json.loads((PROJECTS / "old" / f"character-{chara}-v02.json").read_text())
    template = json.loads((PROJECTS / f"{OUTRO_TEMPLATE}.json").read_text())["scenes"][-1]
    style = CHARACTERS[chara]
    project = copy.deepcopy(src)
    project["name"] = f"{chara}-play"
    project["voice"]["lines"] = [{"start": s, "text": t} for s, t in style["voice"]]
    for i, scene in enumerate(project["scenes"]):
        old = {l["id"]: l for l in scene["layers"]}
        layers = decor(scene, style)
        scene["background"]["color"] = style["background"]
        if scene["id"] == "outro":
            scene["layers"] = layers + outro_layers(old, style, template)
        else:
            scene["layers"] = layers + play_layers(old, style, i)
    return project


def main():
    names = sys.argv[1:] or [n for n in CHARACTERS if n != "mitsuba"]
    for chara in names:
        dest = PROJECTS / f"{chara}-play.json"
        if dest.exists():
            print(f"{dest.relative_to(ROOT)} は既にあります。上書きしません。")
            continue
        dest.write_text(json.dumps(build(chara), ensure_ascii=False, indent=2) + "\n")
        print(dest.relative_to(ROOT))


if __name__ == "__main__":
    main()
