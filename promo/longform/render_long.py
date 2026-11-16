#!/usr/bin/env python3
"""本編レイアウト案Bで、連続する撮影区間に声・字幕・口パクを付ける。

python3 promo/longform/render_long.py <台本.json> --out <出力フォルダ> --prepare-only
python3 promo/longform/render_long.py <台本.json> --out <出力フォルダ>
前者だけ音声エンジンが必要。出力を上書きしない。冒頭・区切り・締めはまだ扱わない。
"""

import argparse
import json
import math
from pathlib import Path
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

from full_preview import audio_data, speaking

ROOT = Path(__file__).resolve().parents[2]
FPS = 24
SIZE = (1920, 1080)
GAME_SIZE = (1920, 864)


def load_project(path):
    project = json.loads(path.read_text())
    if project.get("profile") != "akane":
        raise ValueError("いまの試作はアカネのみ")
    source = ROOT / project["source"]
    aligned = json.loads((ROOT / project["events"]).read_text())
    event_video = Path(aligned["capture"]) / aligned["video"]
    capture_meta = json.loads((Path(aligned["capture"]) / "capture.json").read_text())
    if aligned.get("rejected") or capture_meta.get("status") != "recorded_unaligned":
        raise ValueError("このテイクは不採用または録画に失敗しています")
    if not capture_meta.get("audio_guard", {}).get("checks", 0):
        raise ValueError("音声の再生元を監視していないテイクです")
    if source.resolve() != event_video.resolve():
        raise ValueError("録画と出来事ログの組み合わせが一致しません")
    if not source.is_file():
        raise ValueError("録画がありません")
    start, duration = float(project["source_start"]), float(project["duration"])
    if not all(math.isfinite(x) for x in (start, duration)) or start < 0 or duration <= 0 or start + duration > aligned["safe_end"]:
        raise ValueError("録画の範囲外、またはボスを含む区間です")
    events = {e["seq"]: e for e in aligned["events"]}
    last = -1
    for line in project["lines"]:
        if not isinstance(line["text"], str) or not line["text"].strip():
            raise ValueError("空の台詞があります")
        t = float(line["start"])
        if not math.isfinite(t) or not last < t < duration or t < 0:
            raise ValueError("台詞は時刻順に、区間内に置いてください")
        last = t
        if "event_seq" in line:
            event = events[line["event_seq"]]
            actual = event["video_s"] - start
            if not 0 <= actual < duration or not 0 <= t - actual <= 1.5:
                raise ValueError("反応が出来事の直後に配置されていません")
        expression = line.get("expression", "normal")
        for state in ("closed", "open"):
            if not (ROOT / f"promo/characters/bust/akane/{expression}_{state}.png").is_file():
                raise ValueError(f"表情がありません: {expression}")
    return project


def prepare(project, out):
    sys.path.insert(0, str(ROOT / "promo/editor"))
    from render import synthesize, voice_timing, VOICE_PROFILES
    if any(out.iterdir()):
        raise FileExistsError("音声の出力先は空のフォルダを指定してください")
    timed, problems = voice_timing(project["lines"], project["duration"], print, profile=project["profile"])
    if problems:
        raise ValueError(" / ".join(problems))
    for i, line in enumerate(timed):
        (out / f"voice-{i:03}.wav").write_bytes(synthesize(line["text"], project["profile"])[0])
    (out / "prepared.json").write_text(json.dumps({"project": project, "timed": timed,
        "profile": VOICE_PROFILES[project["profile"]]}, ensure_ascii=False, indent=2) + "\n")
    print("音声と台詞の長さを保存しました", flush=True)


def draw_text(draw, xy, text, font, fill="white"):
    draw.text(xy, text, font=font, fill=fill)


def wrap(text, font, width):
    lines, current = [], ""
    # 字幕の行頭に句読点や閉じ括弧を置かない。
    for char in text:
        if current and font.getlength(current + char) > width and char not in "、。！？!?)）」』":
            lines.append(current)
            current = ""
        current += char
    if current:
        lines.append(current)
    if len(lines) > 3:
        raise ValueError(f"字幕が3行に収まりません: {text}")
    return lines


def render(project, out):
    movie = out / "preview.mp4"
    if movie.exists() or (out / "mix.wav").exists():
        raise FileExistsError("出力動画か合成音声が既にあります。上書きしません")
    prepared = json.loads((out / "prepared.json").read_text())
    if project != prepared["project"]:
        raise ValueError("台本が音声作成時から変わっています。別の出力先で音声を作り直してください")
    lines = [{**line, **timed, "audio": audio_data(out / f"voice-{i:03}.wav")}
             for i, (line, timed) in enumerate(zip(project["lines"], prepared["timed"]))]
    source, start, duration = ROOT / project["source"], project["source_start"], project["duration"]
    inputs = ["-ss", str(start), "-t", str(duration), "-i", str(source)]
    filters = ["[0:a]aresample=48000,aformat=channel_layouts=stereo,volume=0.38[game]"]
    tracks = ["[game]"]
    for i, line in enumerate(lines):
        inputs += ["-i", str(out / f"voice-{i:03}.wav")]
        filters.append(f"[{i+1}:a]aresample=48000,aformat=channel_layouts=stereo,adelay={round(line['start']*1000)}:all=1[v{i}]")
        tracks.append(f"[v{i}]")
    filters.append("".join(tracks) + f"amix=inputs={len(tracks)}:normalize=0,alimiter=limit=0.95:latency=1,apad,atrim=duration={duration}[mix]")
    subprocess.run(["ffmpeg", "-v", "error", "-n", *inputs, "-filter_complex", ";".join(filters),
                    "-map", "[mix]", "-c:a", "pcm_s16le", str(out / "mix.wav")], check=True)
    subtitle_font = ImageFont.truetype(str(ROOT / "promo/build/fonts/NotoSansCJK-Bold.ttc"), 42)
    small = ImageFont.truetype(str(ROOT / "promo/build/fonts/NotoSansCJK-Bold.ttc"), 24)
    belt = Image.new("RGB", SIZE, "#2c191c")
    d = ImageDraw.Draw(belt)
    d.rounded_rectangle((368, 890, 1888, 1054), radius=22, fill="#130e11", outline="#d5372c", width=3)
    sprites = {}
    for expression in {"normal", *[l.get("expression", "normal") for l in lines]}:
        for state in ("closed", "open"):
            im = Image.open(ROOT / f"promo/characters/bust/akane/{expression}_{state}.png").convert("RGBA")
            sprites[expression, state] = im.resize((347, 340), Image.Resampling.LANCZOS)
    blink = Image.open(ROOT / "promo/characters/bust/akane/normal_blink.png").convert("RGBA").resize((347, 340), Image.Resampling.LANCZOS)
    for line in lines:
        line["caption"] = wrap(line["text"], subtitle_font, 1430)
    overlays = []
    for asset, xy, width in [("logo/title-logo.png", (24, 20), 220), ("tags/akane_tag_endless.png", (1580, 24), 300)]:
        im = Image.open(ROOT / "promo/assets" / asset).convert("RGBA")
        im = im.resize((width, round(im.height * width / im.width)), Image.Resampling.LANCZOS)
        overlays.append((im, xy))
    decode = ["ffmpeg", "-v", "error", "-ss", str(start), "-i", str(source), "-t", str(duration),
              "-vf", "scale=1920:864,fps=24", "-an", "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"]
    encode = ["ffmpeg", "-v", "error", "-n", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "1920x1080", "-r", str(FPS),
              "-i", "pipe:0", "-i", str(out / "mix.wav"), "-map", "0:v", "-map", "1:a", "-c:v", "libx264",
              "-preset", "veryfast", "-crf", "19", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k",
              "-movflags", "+faststart", "-t", str(duration), str(movie)]
    expected = round(duration * FPS)
    frame_bytes = GAME_SIZE[0] * GAME_SIZE[1] * 3
    with subprocess.Popen(decode, stdout=subprocess.PIPE) as reader, subprocess.Popen(encode, stdin=subprocess.PIPE) as writer:
        try:
            for n in range(expected):
                raw = reader.stdout.read(frame_bytes)
                if len(raw) != frame_bytes:
                    raise RuntimeError(f"録画が途中で終わりました: {n}/{expected}コマ")
                frame = belt.copy()
                frame.paste(Image.frombytes("RGB", GAME_SIZE, raw), (0, 0))
                for im, xy in overlays:
                    frame.paste(im, xy, im)
                draw = ImageDraw.Draw(frame)
                draw.text((1720, 826), "自動プレイ映像", font=small, fill="white", stroke_width=2, stroke_fill="#130e11")
                draw.text((22, 1050), "音声：AivisSpeech 中2", font=small, fill="#c3aeb2")
                t = n / FPS
                current = next((l for l in lines if l["start"] <= t < l["end"]), None)
                expression = current.get("expression", "normal") if current else "normal"
                state = "open" if current and speaking(current["audio"], t - current["start"]) else "closed"
                sprite = sprites[expression, state]
                if current is None and 3.25 <= t % 4.2 < 3.4:
                    sprite = blink
                frame.paste(sprite, (12, 712), sprite)
                if current:
                    captions = current["caption"]
                    top = 972 - len(captions) * 28
                    for i, caption in enumerate(captions):
                        draw_text(draw, (406, top + 56 * i), caption, subtitle_font)
                writer.stdin.write(frame.tobytes())
                if n in (FPS * 3, FPS * 15, FPS * 30):
                    frame.save(out / f"still-{n//FPS:02}.jpg", quality=93)
                if n and n % (FPS * 10) == 0:
                    print(f"{n//FPS}/{duration}秒", flush=True)
        except BaseException:
            reader.terminate()
            writer.terminate()
            raise
        finally:
            reader.stdout.close()
            writer.stdin.close()
        if reader.wait() or writer.wait():
            raise RuntimeError("ffmpegの読み込みか書き出しが失敗しました")
    report = {"frames": expected, "fps": FPS, "duration": duration, "source_start": start,
              "timed": prepared["timed"], "game_volume": .38}
    (out / "timing.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(movie, flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    project = load_project(args.project)
    if args.prepare_only:
        prepare(project, args.out)
    else:
        render(project, args.out)
