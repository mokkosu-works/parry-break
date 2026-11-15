"""ゲームモード紹介の動画 (キャラごとに 1 本、character-<名前>-mode01) を作る。

各キャラの v05 (create_character_layout.py) を土台に、色・飾り・アウトロの配置 (本人が調整したもの) はそのまま、
録画・見出し・吹き出し・台詞・ポーズを差し替える。録画は 1.5.0 の撮影用アプリで撮ったもの
(promo/capture/capture_mode.sh、raw/m<モード>_<テイク>.mp4)。

    python3 promo/build/create_mode_videos.py [名前 ...]

既にあるプロジェクトは上書きせず飛ばす。文字の画像 (作り方は promo/design/character-series-v05.md) を
promo/characters/text/<名前>_mode01_*.png に置いてから実行する。
"""
import copy
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import create_character_layout as base  # noqa: E402

PROJECTS = base.PROJECTS
# ゲーム画面を大きく見せる配置 (本人の指摘「プレイ画面小さくないかな？」)。見出しを少し低く上に寄せ、
# ゲーム画面を左右 100px の帯いっぱい (枠の線まで含めて x=100〜980) に広げる。キャラの絵の高さはほぼ同じ
base.HEADLINE_TOP, base.HEADLINE_H = 140, 140
base.GAME = {"x": 109, "y": 300, "width": 862, "height": 517}
base.BUBBLE = {"x": 470, "y": 860, "width": 470}
NAME = "mode01"
RAW = "../../capture/raw/"
# 1.5.0 の録画 (2400x1080)。プレイ中は盤面 (x=360〜2160) だけ、メニューや結果は画面全体を見せる
PLAY = {"x": 360, "y": 0, "width": 1800, "height": 1080}
FULL = {"x": 0, "y": 0, "width": 2400, "height": 1080}
# 約 1.1 倍に寄せる。上のスコア表示は削れるが、パドル (y=1011〜1022) と左右の壁の近くは残る。
# スコアやラウンド、練習の集計を見せたい場面では使わない
ZOOM = {"x": 440, "y": 72, "width": 1640, "height": 984}
# ショートの右のボタン列 (実機の画面で測った値。動画の座標で x>930、y>1220) を避ける右端
BUTTONS_X, BUTTONS_Y = 900, 1200

# シーンごとに (録画, 開始秒, 切り出し, ポーズ)。ポーズ: 0 通常 1 集中 2 予想外 3 失敗 4 成功 5 固有
VIDEOS = {
    "mitsuba": {
        "scenes": [("mtitle_01", 0.5, FULL, 5), ("mstage_01", 4.5, FULL, 0), ("mdaily_01", 48, ZOOM, 2)],
        "outro_pose": 4,
        "voice": [(0.1, "どれで遊ぶ？4つあるよ！"), (3.3, "ステージは、一面ずつ。"), (7.0, "星を集めるのも、楽しい！"),
                  (11.3, "デイリーは、毎日ちがう！"), (15.3, "エンドレスと練習もあるよ。"),
                  (19, "パリィブレイク。ストアで検索！"), (21.5, "好きなのから、どうぞ！")],
    },
    "wakana": {
        "scenes": [("mstage_01", 4.8, FULL, 0), ("mstage_01", 9.5, ZOOM, 1), ("mstage_01", 34, FULL, 4)],
        "outro_pose": 4,
        "voice": [(0.1, "ステージは、ここから。"), (3.3, "目標は、ブロックを全部壊すこと。"), (7.8, "焦らなくていいよ。"),
                  (11.3, "条件を満たすと、星がもらえるの。"), (15.6, "星3つ、そろったね。"),
                  (19, "パリィブレイク。ストアで検索。"), (21.8, "次の面も、待ってるよ。")],
    },
    "akane": {
        "scenes": [("mendless_01", 22, PLAY, 5), ("mendless_01", 44, PLAY, 1), ("mendless_01", 62, PLAY, 4)],
        "outro_pose": 0,
        "voice": [(0.1, "エンドレス、勝負だ！"), (3.2, "ラウンドが、どんどん続く！"), (7.8, "まだ止まらないよ！"),
                  (11.4, "点が、どんどん増えてく！"), (15.5, "次のラウンドへ！"),
                  (19, "パリィブレイク。ストアで検索！"), (21.5, "キミの記録、見せてよ！")],
    },
    "shizuku": {
        "scenes": [("mpractice_01", 3.5, PLAY, 0), ("mpractice_01", 7, PLAY, 5), ("mpractice_01", 24, PLAY, 1)],
        "outro_pose": 4,
        "voice": [(0.1, "ここは、練習場。"), (3.3, "ずれが、数字で出る。"), (7.2, "遅いか、早いか、分かる。"),
                  (11.3, "落としても、終わらない。"), (15.3, "何度でも、合わせて。"),
                  (19, "パリィブレイク。ストアで検索。"), (21.8, "ジャスト、狙ってみて。")],
    },
    "momoka": {
        "scenes": [("mdaily_01", 4, ZOOM, 0), ("mdaily_01", 11, ZOOM, 2), ("mdaily_01", 28, ZOOM, 1)],
        "outro_pose": 4,
        "voice": [(0.1, "今日のデイリー、やった？"), (3.3, "今日は、みんな同じ配置なの。"), (7.5, "どこで差がつくかな？"),
                  (11.3, "ミスしたら、そこで終わり。"), (15.5, "ドキドキするね！"),
                  (19, "パリィブレイク。ストアで検索！"), (21.5, "明日も、一緒にやろうね！")],
    },
}


# ゲーム画面の右下に重ねるモードのタグ (シーンごと。None はタグなし)。画像は <名前>_mode01_tag_<モード>.png
TAGS = {
    "mitsuba": [None, "stage", "daily"],
    "wakana": ["stage"] * 3,
    "akane": ["endless"] * 3,
    "shizuku": ["practice"] * 3,
    "momoka": ["daily"] * 3,
}


def tag_layer(chara, mode, frame):
    tag = base.image_layer("tag", "モードのタグ", f"{chara}_{NAME}_tag_{mode}.png", 0, 0, height=60)
    tag["x"] = frame["x"] + frame["width"] - tag["width"] - 12
    tag["y"] = frame["y"] + frame["height"] - 32  # 枠の下の線にかけて置く (構成案と同じ)
    return tag


def asset(chara, kind, i):
    return f"{chara}_{NAME}_{kind}_{i}.png"


def game_layers(video, start, crop):
    """ゲーム映像と枠。画面全体を見せるときは横長になるので、プレイ時の枠の高さの中で上下中央に置く。"""
    g = base.GAME
    height = round(g["width"] * crop["height"] / crop["width"])
    y = g["y"] + (g["height"] - height) // 2
    game = {"id": "game", "type": "video", "name": "ゲーム映像", "visible": True, "x": g["x"], "y": y,
            "width": g["width"], "height": height, "src": RAW + video + ".mp4", "start": start, "crop": dict(crop)}
    frame = {"id": "frame", "name": "frame", "type": "rect", "visible": True,
             "x": g["x"] - 9, "y": y - 9, "width": g["width"] + 18, "height": height + 18,
             "color": "#1E1B24", "strokeWidth": 4, "shape": "rect", "tail": "left", "radius": 14, "fill": "#1E1B24"}
    return [frame, game]


def build(chara):
    src = json.loads((PROJECTS / f"character-{chara}-v05.json").read_text())
    spec = VIDEOS[chara]
    project = copy.deepcopy(src)
    project["name"] = f"character-{chara}-{NAME}"
    project["voice"]["lines"] = [{"start": s, "text": t} for s, t in spec["voice"]]
    for i, scene in enumerate(project["scenes"]):
        layers = {l["id"]: l for l in scene["layers"]}
        keep = [l for l in scene["layers"] if l["type"] == "rect" and l["id"] != "frame"]  # 背景の飾り
        if scene["id"] == "outro":
            out = []
            for l in scene["layers"]:
                if l["type"] == "rect" and l["id"] != "frame":
                    continue
                l = copy.deepcopy(l)
                if l["id"] == "character":
                    l["pose"] = spec["outro_pose"]
                    l["x"] = layers["character"]["x"]
                    # ポーズを替えると髪の高さが変わる。タイトルの下から下 480px の帯の上までに収める
                    sys.path.insert(0, str(base.ROOT / "promo/editor"))
                    import render
                    title_bottom = render._box(layers["logo-break"])[3] + 10
                    _, top, _, bottom = base.visible_box(l)
                    if l["y"] + top < title_bottom:
                        room = base.SAFE_B - 5 - title_bottom
                        if bottom - top > room:
                            l["height"] = int(l["height"] * room / (bottom - top))
                            _, top, _, bottom = base.visible_box(l)
                        l["y"] = round(title_bottom - top)
                    left = base.visible_box(l)[0]
                    l["x"] = max(l["x"], base.SAFE_L + 10 - left)
                out.append(l)
            char = out[0]
            old = next(l for l in out if l["id"] == "bubble")
            new = base.bubble(asset(chara, "bubble", 4), old["x"], 0, 504, 250)
            box = {"x": 469, "y": 587, "width": 504, "height": 170}  # 本人が調整したミツバのアウトロの吹き出しの枠
            new["x"] = box["x"]
            new["y"] = round(box["y"] + box["height"] / 2 - new["height"] / 2)
            base.avoid_character(new, char, box)
            out[[l["id"] for l in out].index("bubble")] = new
            search = next(l for l in out if l["id"] == "store-search")
            base.avoid_character(search, char, {"y": search["y"], "height": search["height"]})
            # バッジとクレジットの右端をボタン列より左に (実機では Google Play のバッジがハートのボタンに近かった)
            # 「ストアで検索」は左へ動かすとキャラの手にかかるので、左端はそのままで縮める
            sys.path.insert(0, str(base.ROOT / "promo/editor"))
            import render
            for l in out:
                if l["id"] not in ("badge-appstore", "badge-googleplay", "credit", "store-search"):
                    continue
                right = render._box(l)[2]
                if right <= BUTTONS_X:
                    continue
                if l["id"] == "store-search":
                    w, h = l["width"], l["height"]
                    l["width"] = BUTTONS_X - l["x"]
                    l["height"] = round(h * l["width"] / w)
                    l["y"] = round(l["y"] + (h - l["height"]) / 2)
                else:
                    l["x"] = round(l["x"] - (right - BUTTONS_X))
            scene["layers"] = keep + out
            scene["background"]["src"] = RAW + spec["scenes"][-1][0] + ".mp4"
            scene["background"]["time"] = spec["scenes"][-1][1]
            continue
        video, start, crop, pose = spec["scenes"][i]
        scene["background"]["src"] = RAW + video + ".mp4"
        scene["background"]["time"] = start
        character = copy.deepcopy(layers["character"])
        character.update(base.CHAR)
        character["pose"] = pose
        base.fit_character(character)
        speech = base.bubble(asset(chara, "bubble", i + 1), base.BUBBLE["x"], base.BUBBLE["y"], base.BUBBLE["width"], 300)
        speech["x"] = min(speech["x"], base.SAFE_R - speech["width"])
        speech["y"] += max(0, (300 - speech["height"]) // 3)
        # タイトルは少し小さくし、右端をボタン列より左に (実機で「Y」「K」にボタンが重なった)
        titles = base.title(layers, BUTTONS_X - base.title_width(layers, 76), size=76)
        frame, game = game_layers(video, start, crop)
        tag = [tag_layer(chara, TAGS[chara][i], frame)] if TAGS[chara][i] else []
        scene["layers"] = keep + [base.headline(asset(chara, "headline", i + 1)), frame, game, *tag,
                                  character, speech, *titles]
    return project


def main():
    for chara in sys.argv[1:] or list(VIDEOS):
        dest = PROJECTS / f"character-{chara}-{NAME}.json"
        if dest.exists():
            print(f"{dest.relative_to(base.ROOT)} は既にあります。上書きしません。")
            continue
        dest.write_text(json.dumps(build(chara), ensure_ascii=False, indent=2) + "\n")
        print(dest.relative_to(base.ROOT))


if __name__ == "__main__":
    main()
