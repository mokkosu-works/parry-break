#!/usr/bin/env python3
"""アカネの場面構成案v01を既存素材で合成する。本編のレンダラーではない。

python3 promo/longform/scene_proposals.py
必要な背景のコマは同じスクリプトで既存録画から取得する。
既存の構成案は上書きしない。改訂するときは旧版をdesign/old/へ退避する。
"""

from pathlib import Path
import subprocess

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
DESIGN = ROOT / "promo/design"
ASSETS = ROOT / "promo/assets"
FULL = ROOT / "promo/characters/full/akane"
SIZE = (1920, 1080)
FONT = str(ROOT / "promo/build/fonts/NotoSansCJK-Bold.ttc")


def put(canvas, path, xy, *, width=None, height=None):
    im = Image.open(path).convert("RGBA")
    bbox = im.getchannel("A").getbbox()
    if bbox:
        im = im.crop(bbox)
    if width:
        im = im.resize((width, round(im.height * width / im.width)), Image.Resampling.LANCZOS)
    elif height:
        im = im.resize((round(im.width * height / im.height), height), Image.Resampling.LANCZOS)
    canvas.alpha_composite(im, xy)
    return im.size


def text(canvas, xy, words, size, fill="#fff5ed", anchor=None):
    ImageDraw.Draw(canvas).text(xy, words, font=ImageFont.truetype(FONT, size), fill=fill, anchor=anchor)


def background(frame, brightness=.30, blur=18):
    im = Image.open(frame).convert("RGB")
    # 画面の縦横比が異なるため、背景用に上下を中央でトリミングする。
    target = im.height * SIZE[0] / SIZE[1]
    left = round((im.width - target) / 2)
    im = im.crop((left, 0, left + round(target), im.height)).resize(SIZE, Image.Resampling.LANCZOS)
    return ImageEnhance.Brightness(im.filter(ImageFilter.GaussianBlur(blur))).enhance(brightness).convert("RGBA")


def subtitle(canvas, lines):
    ImageDraw.Draw(canvas).rounded_rectangle((730, 820, 1820, 1000), radius=22,
                                             fill="#171015", outline="#71322f", width=2)
    for i, line in enumerate(lines):
        text(canvas, (775, 847 + i * 66), line, 38)


def main():
    names = ("opening", "chapter", "ending")
    paths = [DESIGN / f"akane-longform-{name}-v01.png" for name in names]
    board = DESIGN / "checks/akane-longform-scenes-v01.jpg"
    if any(p.exists() for p in [*paths, board]):
        raise SystemExit("既存の構成案があります。上書きせず、改訂版の置き場所を決めてください。")
    frame = DESIGN / "codex/longform-scenes/ref/endless-frame.png"
    if not frame.exists():
        subprocess.run(["ffmpeg", "-v", "error", "-ss", "25", "-i", str(ROOT / "promo/capture/raw/mendless_v151.mp4"),
                        "-frames:v", "1", "-update", "1", str(frame)], check=True)
    logo = ASSETS / "logo/title-logo.png"
    tag = ASSETS / "tags/akane_tag_endless.png"
    headings = ASSETS / "text/longform"
    scenes = []

    opening = background(frame, .44)
    d = ImageDraw.Draw(opening)
    d.polygon([(0, 0), (700, 0), (575, 1080), (0, 1080)], fill="#361619")
    d.line([(700, 0), (575, 1080)], fill="#ce3b2c", width=6)
    put(opening, FULL / "greet_closed.png", (80, 150), height=870)
    put(opening, tag, (1430, 64), width=370)
    put(opening, logo, (850, 175), width=650)
    put(opening, headings / "akane-opening-v01.png", (755, 580), width=1060)
    subtitle(opening, ["よしっ、アカネだよ！", "今日は、エンドレスを見ていこう！"])
    scenes.append(opening)

    chapter = background(frame, .26, 24)
    d = ImageDraw.Draw(chapter)
    d.rectangle((0, 0, 1920, 12), fill="#d8382d")
    d.rectangle((0, 1068, 1920, 1080), fill="#d8382d")
    put(chapter, logo, (80, 62), width=290)
    put(chapter, tag, (1430, 64), width=370)
    d.rounded_rectangle((580, 328, 1820, 718), radius=24, fill="#24151c", outline="#d8382d", width=4)
    d.rectangle((580, 400, 596, 645), fill="#e94a35")
    text(chapter, (660, 345), "01", 80, fill="#f6b14a")
    put(chapter, headings / "akane-chapter-v01.png", (650, 480), width=1080)
    put(chapter, FULL / "guide_closed.png", (70, 244), height=760)
    scenes.append(chapter)

    ending = background(frame, .20, 28)
    d = ImageDraw.Draw(ending)
    d.rectangle((0, 0, 1920, 12), fill="#d8382d")
    d.line((1060, 95, 1060, 1010), fill="#80302d", width=3)
    put(ending, FULL / "close_closed.png", (55, 278), height=755)
    put(ending, logo, (555, 175), width=440)
    put(ending, headings / "akane-ending-v01.png", (545, 500), width=455)
    # 以下の枠とラベルは配置確認用。本番には枠も説明文字も焼き込まない。
    d.rounded_rectangle((1160, 170, 1800, 530), radius=16, fill="#30272d", outline="#87787f", width=2)
    text(ending, (1480, 350), "おすすめ動画", 40, fill="#d6c9ce", anchor="mm")
    d.ellipse((1360, 650, 1600, 890), fill="#30272d", outline="#87787f", width=2)
    text(ending, (1480, 770), "チャンネル", 27, fill="#d6c9ce", anchor="mm")
    text(ending, (1480, 955), "終了画面の要素を置く場所", 25, fill="#ac999e", anchor="mm")
    text(ending, (530, 745), "ボールひとつで、", 34)
    text(ending, (530, 799), "記録に挑戦！", 34)
    scenes.append(ending)

    labels = ("01  オープニング  /  10〜15秒", "02  チャプターの区切り  /  2〜3秒", "03  エンディング  /  約20秒")
    contact = Image.new("RGB", (1440, 3 * 870), "#eee8e2")
    for i, (scene, path, label) in enumerate(zip(scenes, paths, labels)):
        text(scene, (1820, 1040), "自動プレイ映像", 24, fill="#b9a8b1", anchor="rm")
        scene.convert("RGB").save(path)
        text(contact, (38, i * 870 + 14), label, 28, fill="#352b2d")
        contact.paste(scene.convert("RGB").resize((1440, 810), Image.Resampling.LANCZOS), (0, i * 870 + 60))
        print(path.relative_to(ROOT))
    contact.save(board, quality=93)
    print(board.relative_to(ROOT))


if __name__ == "__main__":
    main()
