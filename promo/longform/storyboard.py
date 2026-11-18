#!/usr/bin/env python3
"""通常尺の絵コンテの静止画を作る(本番の書き出しと同じ描き方で、コマを 1 枚ずつ合成して並べる)。

python3 promo/longform/storyboard.py <名前>            # promo/longform/storyboards/<名前>-v01.json から
python3 promo/longform/storyboard.py <名前> --version v02

出力は promo/design/checks/<名前>-storyboard-<版>.jpg(既にあれば上書きせずに止まる)。
オープニング・区切り・エンディングは assemble.py の *_layout、本編は render_long.py の compose_main を使う。
見出しの画像がまだない回は、見出しを Noto Sans CJK の仮の文字で描く(一覧の札に「仮の文字」と出す)。
録画がまだない場面は、近い録画で代わりにし、コマの指定に "provisional": true を書く(札に「仮の映像」と出す)。
"""

import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
from assemble import chapter_layout, ending_layout, full_body, name_tag, opening_layout  # noqa: E402
from render_long import (GAME_SIZE, PROFILES, ROOT, bust_size, compose_main, guest_card, main_belt,  # noqa: E402
                         overlay_asset, speaker_tag, wrap)

FONT = str(ROOT / "promo/build/fonts/NotoSansCJK-Bold.ttc")
SCENES = ("opening", "chapter", "main", "ending")
EXPRESSIONS = ("explain", "fired", "focus", "frustrated", "normal", "shock", "shy", "smug", "steam", "success",
               "surprise", "think")
THUMB = (640, 360)
COLUMNS = 3


def font(size):
    return ImageFont.truetype(FONT, size)


def placeholder_heading(text):
    """見出しの画像の代わり。本物と同じく、白い文字に濃い縁(明るい背景では assemble が入れ替える)。"""
    f = font(150)
    lines = text.split("\n")
    width = max(round(f.getlength(line)) for line in lines) + 60
    im = Image.new("RGBA", (width, 190 * len(lines) + 40), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for i, line in enumerate(lines):
        d.text((30, 20 + 190 * i), line, font=f, fill="white", stroke_width=10, stroke_fill="#1E1B24")
    return im


def heading_image(frame):
    """frame に "heading_file" があれば本物の見出し、なければ "heading" の仮の文字。"""
    if frame.get("heading_file"):
        return Image.open(ROOT / "promo/assets/text/longform" / frame["heading_file"]), False
    return placeholder_heading(frame["heading"]), True


def grab(source, at, cache):
    """録画の at 秒のコマ(1920×864)。"""
    key = cache / f"{abs(hash((source, at)))}.png"
    if not key.exists():
        subprocess.run(["ffmpeg", "-v", "error", "-ss", str(at), "-i", str(ROOT / source), "-frames:v", "1",
                        "-vf", f"scale={GAME_SIZE[0]}:{GAME_SIZE[1]}", "-update", "1", str(key)], check=True)
    return Image.open(key).convert("RGB")


def subtitle_on(frame, colors, box, width, size, text):
    """全身が話す場面の字幕(assemble.talking_scene と同じ描き方)。"""
    caption_font = font(size)
    d = ImageDraw.Draw(frame)
    d.rounded_rectangle(box, radius=22, fill=colors["box"], outline=colors["outline"], width=3)
    tag = name_tag(colors)
    frame.alpha_composite(tag, (box[0] + 24, box[1] - 22))
    captions = wrap(text, caption_font, width)
    step = round(size * 1.33)
    top = (box[1] + box[3]) // 2 - len(captions) * step // 2
    for i, caption in enumerate(captions):
        d.text((box[0] + 38, top + step * i), caption, font=caption_font, fill=colors["text"])


def render_frame(board, frame, sheets, cache):
    """1 コマを 1920×1080 で描く。戻り値は (画像, 仮の文字か)。"""
    profile = board["profile"]
    colors = PROFILES[profile]
    plan = {"profile": profile, "opening": {}, "ending": {}}
    scene = frame["scene"]
    if scene == "opening":
        heading, rough = heading_image(frame)
        bg, sprites, xy, (box, width, size) = opening_layout(plan, sheets, heading)
        image = bg.copy()
        image.alpha_composite(sprites["closed"], xy)
        if frame.get("line"):
            subtitle_on(image, colors, box, width, size, frame["line"])
        return image, rough
    if scene == "chapter":
        heading, rough = heading_image(frame)
        card, sprites, xy = chapter_layout(plan, frame["number"], {}, sheets, heading)
        image = card.copy()
        image.alpha_composite(sprites["closed"], xy)
        return image, rough
    if scene == "ending":
        heading, rough = heading_image(frame)
        bg, sprites, xy = ending_layout(plan, sheets, heading)
        image = bg.copy()
        image.alpha_composite(sprites["closed"], xy)
        return image, rough
    # 本編(案B)
    expression = frame.get("expression", "normal")
    talking = bool(frame.get("line"))
    sprite = bust_size(Image.open(ROOT / "promo/characters/bust" / profile /
                                  f"{expression}_{'open' if talking else 'closed'}.png").convert("RGBA"))
    small, subtitle_font = font(24), font(42)
    tag = frame.get("tag", colors["tag"])
    sys.path.insert(0, str(ROOT / "promo/editor"))
    from render import VOICE_PROFILES
    image = compose_main(
        main_belt(colors), grab(frame["source"], frame["at"], cache), colors, small, subtitle_font, sprite,
        credit=f"音声：AivisSpeech {VOICE_PROFILES[profile]['speakerName']}",
        logo=overlay_asset("logo/title-logo.png", 220) if frame.get("logo", True) else None,
        tag=overlay_asset(tag, 300) if tag else None,
        guest=guest_card(frame["guest"], FONT) if frame.get("guest") else None,
        autoplay=frame.get("autoplay", True),
        name_tag=speaker_tag(colors) if talking else None,
        captions=wrap(frame["line"], subtitle_font, 1430) if talking else ())
    return image.convert("RGBA"), False


def check(board):
    if board.get("profile") not in PROFILES or "belt" not in PROFILES[board["profile"]]:
        raise SystemExit(f"色が決まっていないキャラです: {board.get('profile')}(render_long.PROFILES)")
    for i, frame in enumerate(board["frames"], 1):
        where = f"コマ {i}"
        if frame.get("scene") not in SCENES:
            raise SystemExit(f"{where}: scene は {', '.join(SCENES)} のどれか")
        if frame["scene"] in ("opening", "chapter", "ending") and not (frame.get("heading") or frame.get("heading_file")):
            raise SystemExit(f"{where}: 見出し(heading)がありません")
        if frame["scene"] == "chapter" and not frame.get("number"):
            raise SystemExit(f"{where}: 章の番号(number)がありません")
        if frame["scene"] == "main":
            if not (ROOT / frame.get("source", "")).is_file():
                raise SystemExit(f"{where}: 録画がありません: {frame.get('source')}")
            if frame.get("expression", "normal") not in EXPRESSIONS:
                raise SystemExit(f"{where}: 表情は {', '.join(EXPRESSIONS)} のどれか")
            if frame.get("guest") and frame["guest"] not in PROFILES:
                raise SystemExit(f"{where}: メンバーとして出せないキャラです: {frame['guest']}")


def label_lines(text, f, width, limit=3):
    """一覧の札の台詞。長いときは limit 行で切って「…」。"""
    lines, current = [], ""
    for char in text:
        if current and f.getlength(current + char) > width:
            lines.append(current)
            current = ""
        current += char
    if current:
        lines.append(current)
    if len(lines) > limit:
        lines = lines[:limit]
        lines[-1] = lines[-1][:-1] + "…"
    return lines


def label(frame, number, rough):
    head = f"#{number}  {frame.get('time', '')}  {frame.get('chapter', '')}"
    notes = [n for n, on in (("仮の映像", frame.get("provisional")), ("仮の文字", rough)) if on]
    if notes:
        head += "  [" + "・".join(notes) + "]"
    return head, frame.get("line", "")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("name")
    parser.add_argument("--version", default="v01")
    args = parser.parse_args()
    spec = ROOT / f"promo/longform/storyboards/{args.name}-{args.version}.json"
    dest = ROOT / f"promo/design/checks/{args.name}-storyboard-{args.version}.jpg"
    if dest.exists():
        raise SystemExit(f"既にあります(上書きしません): {dest.relative_to(ROOT)}")
    board = json.loads(spec.read_text())
    check(board)
    sheets = full_body(board["profile"])
    head_font, line_font = font(22), font(20)
    cell_h = THUMB[1] + 116
    rows = (len(board["frames"]) + COLUMNS - 1) // COLUMNS
    sheet = Image.new("RGB", (COLUMNS * (THUMB[0] + 24) + 24, 90 + rows * (cell_h + 20)), "#EEE8E2")
    d = ImageDraw.Draw(sheet)
    d.text((24, 24), board.get("title", args.name), font=font(34), fill="#352B2D")
    with tempfile.TemporaryDirectory() as tmp:
        for i, frame in enumerate(board["frames"]):
            image, rough = render_frame(board, frame, sheets, Path(tmp))
            x = 24 + (i % COLUMNS) * (THUMB[0] + 24)
            y = 90 + (i // COLUMNS) * (cell_h + 20)
            sheet.paste(image.convert("RGB").resize(THUMB, Image.Resampling.LANCZOS), (x, y))
            head, line = label(frame, i + 1, rough)
            d.text((x, y + THUMB[1] + 8), head, font=head_font, fill="#352B2D")
            for j, part in enumerate(label_lines(line, line_font, THUMB[0] - 8)):
                d.text((x, y + THUMB[1] + 38 + 24 * j), part, font=line_font, fill="#5A4E50")
    sheet.save(dest, quality=90)
    print(dest.relative_to(ROOT))


if __name__ == "__main__":
    main()
