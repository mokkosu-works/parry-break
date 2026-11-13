#!/usr/bin/env python3
"""キャラクター主体の24秒試作。既存の公開動画と記録は変更しない。"""

import json
import pathlib
import subprocess
import tempfile
import urllib.parse
import urllib.request
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "promo/build/out/character-promo-v12.mp4"
SHEET = ROOT / "promo/characters/character_sheet_v2.png"
APP_ICON = ROOT / "app/branding/icons/icon-512.png"
FONT = ROOT / "promo/build/fonts/DotGothic16-Regular.ttf"
PIXEL_FONT = ROOT / "app/assets/fonts/Silkscreen-Bold.ttf"
ENGINE = "http://127.0.0.1:50021"
SPEAKER = 54  # 春歌ナナ・ノーマル
LINES = [(0.15, 3, "この弾、返せる？"),
         (3.2, 8, "当たる瞬間に、タップ！"),
         (11.2, 16, "白いブロックを壊すと……"),
         (16.0, 19, "まとめて、どーん！"),
         (19.3, 24, "パリィブレイク。ストアで検索！")]


def run(*args):
    subprocess.run([str(x) for x in args], check=True)


def duration(path):
    return float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries",
        "format=duration", "-of", "csv=p=0", str(path)]))


def api(path, data=None, content_type=None):
    headers = {"Content-Type": content_type} if content_type else {}
    req = urllib.request.Request(ENGINE + path, data=data, headers=headers)
    with urllib.request.urlopen(req, timeout=120) as response:
        return response.read()


def font(size, pixel=False):
    return ImageFont.truetype(str(PIXEL_FONT if pixel else FONT), size)


def base(frame):
    with Image.open(frame) as original:
        width = round(original.width * 1920 / original.height)
        enlarged = original.resize((width, 1920), Image.Resampling.BICUBIC)
        left = (width - 1080) // 2
        im = enlarged.crop((left, 0, left + 1080, 1920)).filter(ImageFilter.GaussianBlur(44))
    im = ImageEnhance.Brightness(im).enhance(0.52)
    return Image.blend(im, Image.new("RGB", im.size, "#29142e"), 0.32)


def label(im, xy, text, size, color="#ffffff", stroke=3):
    pixel = text in {"PARRY", "BREAK", "PARRY BREAK"}
    border = "#8a1c00" if color == "#ffc61a" else "#0b0b1a"
    ImageDraw.Draw(im).text(xy, text, font=font(size, pixel), fill=color,
        stroke_width=max(stroke, 7) if color == "#ffc61a" else stroke, stroke_fill=border)


def character(im, pose, x, y, height):
    with Image.open(SHEET) as sheet:
        sprite = sheet.crop((362 * pose, 0, 362 * (pose + 1), 724))
        sprite = sprite.resize((height // 2, height), Image.Resampling.LANCZOS)
        im.paste(sprite, (x, y), sprite)


def character_sprite(pose, height, path):
    with Image.open(SHEET) as sheet:
        sprite = sheet.crop((362 * pose, 0, 362 * (pose + 1), 724))
        sprite = sprite.resize((height // 2, height), Image.Resampling.LANCZOS)
        sprite.save(path)


def character_motion(tmp, name, seconds, pose, height):
    sprite_path = tmp / f"{name}-sprite.png"
    character_sprite(pose, height, sprite_path)
    with Image.open(sprite_path) as image:
        sprite = image.convert("RGBA")
    frames = round(seconds * 30)
    for index in range(frames):
        frame = tmp / f"{name}-character-{index:04d}.png"
        sprite.save(frame)


def credit(im):
    label(im, (510, 1330), "VOICEVOX:春歌ナナ", 32, "#d9d9e2", 1)


def store_badges(im, x, y, width=270):
    badges = [ROOT / "promo/build/assets/badges/appstore.png",
              ROOT / "promo/build/assets/badges/googleplay.png"]
    for i, path in enumerate(badges):
        if path.exists():
            badge = Image.open(path).convert("RGBA")
            badge.thumbnail((width, round(width * 110 / 390)))
            im.paste(badge, (x + i * (width + 18), y), badge)


def artwork(tmp):
    frames = [("intro", ROOT / "promo/capture/raw/s4-7_sloppy_02.mp4", 19),
              ("parry", ROOT / "promo/capture/raw/s4-7_sloppy_02.mp4", 22),
              ("collapse", ROOT / "promo/capture/raw/s3-3_just_01.mp4", 5),
              ("outro", ROOT / "promo/capture/raw/s3-3_just_01.mp4", 9)]
    for name, source, second in frames:
        run("ffmpeg", "-y", "-v", "error", "-ss", second, "-i", source,
            "-frames:v", "1", tmp / f"{name}-frame.png")
    intro = base(tmp / "intro-frame.png")
    label(intro, (85, 105), "この弾、返せる？", 94, "#ffc61a")
    ImageDraw.Draw(intro).rectangle((70, 330, 1010, 902), outline="#ffc61a", width=10)
    label(intro, (180, 915), "当たる瞬間に、タップ！", 52)
    intro.save(tmp / "intro.png")

    for name, pose, caption in [("parry", 1, "弾を撃ち返せ！"),
                                ("collapse", 4, "まとめて崩れる！")]:
        im = base(tmp / f"{name}-frame.png")
        label(im, (75, 140), caption, 81, "#ffc61a")
        ImageDraw.Draw(im).rectangle((30, 290, 1050, 918), outline="#ffc61a", width=10)
        label(im, (485, 1035), "当たる瞬間にタップ！" if name == "parry" else "白いブロックを壊せ！", 52)
        label(im, (485, 1140), "PARRY", 82, "#ffc61a")
        label(im, (485, 1230), "BREAK", 82, "#ffc61a")
        icon = Image.open(APP_ICON).convert("RGBA")
        icon.thumbnail((108, 108), Image.Resampling.LANCZOS)
        im.paste(icon, (485, 1350), icon)
        label(im, (615, 1375), "ストアで検索", 46)
        store_badges(im, 485, 1470)
        im.save(tmp / f"{name}.png")

    outro = base(tmp / "outro-frame.png")
    label(outro, (520, 420), "PARRY", 90, "#ffc61a")
    label(outro, (520, 530), "BREAK", 90, "#ffc61a")
    label(outro, (520, 750), "ストアで検索", 54)
    badges = [ROOT / "promo/build/assets/badges/appstore.png",
              ROOT / "promo/build/assets/badges/googleplay.png"]
    for i, path in enumerate(badges):
        if path.exists():
            badge = Image.open(path).convert("RGBA")
            badge.thumbnail((390, 110))
            outro.paste(badge, (520, 880 + i * 125), badge)
    credit(outro)
    outro.save(tmp / "outro.png")


def scene(tmp, name, seconds, source=None, start=0, game_box=(40, 304, 1000, 600),
          character_pose=1, character_height=850, character_position=(115, 1000), bob=True):
    png, dest = tmp / f"{name}.png", tmp / f"{name}.mp4"
    if source:
        x, y, width, height = game_box
        inputs = ["-loop", "1", "-i", png, "-ss", start, "-t", seconds, "-i", source]
        character_motion(tmp, name, seconds, character_pose, character_height)
        inputs += ["-framerate", "30", "-i", tmp / f"{name}-character-%04d.png"]
        character_y = f"'{character_position[1]}+4*sin(2*PI*t*1.8)'" if bob else str(character_position[1])
        video_filter = (f"[1:v]crop=1800:1080:245:0,scale={width}:{height}:flags=neighbor[game];"
            f"[0:v][game]overlay={x}:{y}:shortest=1[bg];"
            f"[bg][2:v]overlay={character_position[0]}:{character_y}:shortest=1[v];"
            "[1:a]volume=0.52[a]")
        run("ffmpeg", "-y", "-v", "error", *inputs,
            "-filter_complex", video_filter,
            "-map", "[v]", "-map", "[a]", "-t", seconds,
            "-r", "30", "-c:v", "libx264", "-preset", "veryfast", "-crf", "19",
            "-pix_fmt", "yuv420p", "-c:a", "aac", "-ar", "48000", dest)
    else:
        character_motion(tmp, name, seconds, character_pose, character_height)
        run("ffmpeg", "-y", "-v", "error", "-loop", "1", "-i", png,
            "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo",
            "-framerate", "30", "-i", tmp / f"{name}-character-%04d.png",
            "-filter_complex", f"[0:v][2:v]overlay={character_position[0]}:{character_position[1]}:shortest=1[v]",
            "-map", "[v]", "-map", "1:a", "-t", seconds, "-r", "30", "-c:v", "libx264", "-preset", "veryfast",
            "-crf", "19", "-pix_fmt", "yuv420p", "-c:a", "aac", "-ar", "48000", dest)
    return dest


def main():
    if OUT.exists():
        raise SystemExit(f"既にあります: {OUT}")
    OUT.parent.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory() as t:
        tmp = pathlib.Path(t)
        artwork(tmp)
        scenes = [scene(tmp, "intro", 3, ROOT / "promo/capture/raw/s4-7_sloppy_02.mp4", 20,
                        game_box=(80, 340, 920, 552), character_pose=1,
                        character_height=850, character_position=(327, 1015)),
                  scene(tmp, "parry", 8, ROOT / "promo/capture/raw/s4-7_sloppy_02.mp4", 18,
                        character_pose=1, character_height=850, character_position=(20, 970)),
                  scene(tmp, "collapse", 8, ROOT / "promo/capture/raw/s3-3_just_01.mp4", 3.5,
                        character_pose=4, character_height=850, character_position=(20, 970)),
                  scene(tmp, "outro", 5, character_pose=5, character_height=1000,
                        character_position=(5, 420), bob=False)]
        listfile = tmp / "list.txt"
        listfile.write_text("".join(f"file '{p}'\n" for p in scenes))
        joined = tmp / "joined.mp4"
        run("ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", listfile,
            "-c", "copy", joined)
        voices = []
        for i, (start, end, text) in enumerate(LINES):
            params = urllib.parse.urlencode({"text": text, "speaker": SPEAKER})
            query = json.loads(api(f"/audio_query?{params}", b""))
            query["speedScale"] = 1.12
            query["intonationScale"] = 1.18
            voice = tmp / f"voice{i}.wav"
            voice.write_bytes(api(f"/synthesis?speaker={SPEAKER}", json.dumps(query).encode(), "application/json"))
            if start + duration(voice) > end:
                raise SystemExit(f"音声が枠を超えます: {text}")
            voices.append(voice)
        inputs = ["-i", str(joined)]
        filters, mix = [], ["[0:a]"]
        for i, voice in enumerate(voices):
            inputs += ["-i", str(voice)]
            filters.append(f"[{i+1}:a]aresample=48000,volume=1.35,adelay={round(LINES[i][0]*1000)}:all=1[a{i}]")
            mix.append(f"[a{i}]")
        filters.append("".join(mix) + f"amix=inputs={len(mix)}:duration=first:normalize=0,alimiter=limit=0.95[aout]")
        run("ffmpeg", "-n", "-v", "error", *inputs, "-filter_complex", ";".join(filters),
            "-map", "0:v", "-map", "[aout]", "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
            "-t", "24", "-movflags", "+faststart", OUT)
    print(OUT)


if __name__ == "__main__":
    main()
