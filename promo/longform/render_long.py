#!/usr/bin/env python3
"""本編レイアウト案Bで、連続する撮影区間に声・字幕・口パクを付ける。

python3 promo/longform/render_long.py <台本.json> --out <出力フォルダ> --prepare-only
python3 promo/longform/render_long.py <台本.json> --out <出力フォルダ>
python3 promo/longform/render_long.py <台本.json> --out <新しい出力フォルダ> --voices-from <声を作った出力フォルダ>
最初のものだけ音声エンジンが必要。出力を上書きしない。冒頭・区切り・締めはまだ扱わない。
台本の任意の "bgm" で、Windows の DAW で作った BGM を重ねる(promo/longform/bgm.md)。
"bgm" だけを変えた台本は、--voices-from で前の声を写して書き出せる。
"""

import argparse
import json
import math
from pathlib import Path
import shutil
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

from full_preview import audio_data, speaking

ROOT = Path(__file__).resolve().parents[2]
FPS = 24
SIZE = (1920, 1080)
GAME_SIZE = (1920, 864)
GAME_VOLUME = 0.38
# キャラごとの色と、右上のタグ(担当のモードがないキャラは None。台本の "tag" で替えられる)。
# belt: 背景(ゲーム映像の下の帯、オープニングなどの地)。ショートの背景と同じ色(editor/projects/<名前>-modes.json)。
# box・outline・text: 字幕の枠・枠線(差し色)・字幕の文字。name_text: 名札の文字。credit: 声のクレジットの文字。
# accent: ショートの差し色。06 章などでメンバーとして紹介するときの名札の色(accent_text はその文字の色)。
# ミツバは明るい背景なので、文字を焦げ茶(#302719)にする。
PROFILES = {
    "akane": {"name": "アカネ", "belt": "#28181C", "box": "#130e11", "outline": "#d5372c", "text": "white",
              "name_text": "#130e11", "credit": "#c3aeb2", "tag": "tags/akane_tag_endless.png",
              "accent": "#FF6B62", "accent_text": "#1E1B24"},
    "mitsuba": {"name": "ミツバ", "belt": "#FDF3D3", "box": "#FFFBEF", "outline": "#E9B400", "text": "#302719",
                "name_text": "#302719", "credit": "#6B5A3A", "tag": None,
                "accent": "#E9B400", "accent_text": "#302719"},
    "shizuku": {"name": "シズク", "accent": "#7CCCE5", "accent_text": "#1E1B24"},
    "momoka": {"name": "モモカ", "accent": "#D74F86", "accent_text": "white"},
    "wakana": {"name": "ワカナ", "accent": "#91B469", "accent_text": "#1E1B24"},
}
# 本編の書き出しに使えるキャラ(帯の色などが決まっているもの)。
NARRATORS = {k for k, v in PROFILES.items() if "belt" in v}
# ゲーム映像の上の「自動プレイ映像」は、映像が暗いので白い文字に暗い縁取り。
OVER_GAME_STROKE = "#1E1B24"
# 声の間だけ BGM を下げる強さ。声の合計を鍵にする。
DUCK = "sidechaincompress=threshold=0.03:ratio=6:attack=30:release=500:makeup=1"


def without_bgm(project):
    """声の作り直しが要るかどうかは、BGM 以外で比べる。"""
    return {k: v for k, v in project.items() if k != "bgm"}


def media_duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
                         capture_output=True, text=True, check=True).stdout
    return float(out.strip())


def check_bgm(bgm, duration):
    if not isinstance(bgm, dict) or not isinstance(bgm.get("file"), str):
        raise ValueError("bgm には file が要ります")
    path = ROOT / bgm["file"]
    if not path.is_file():
        raise ValueError(f"BGM がありません: {bgm['file']}")
    start = float(bgm.get("start", 0))
    volume = float(bgm.get("volume", 0.2))
    fade_in, fade_out = float(bgm.get("fade_in", 0.5)), float(bgm.get("fade_out", 2.0))
    if not all(math.isfinite(x) for x in (start, volume, fade_in, fade_out)):
        raise ValueError("bgm の数値が正しくありません")
    if start < 0 or not 0 < volume <= 1 or fade_in < 0 or fade_out < 0 or fade_in + fade_out > duration:
        raise ValueError("bgm の start・volume(0〜1)・fade_in・fade_out を確かめてください")
    if media_duration(path) + 1e-3 < start + duration:
        raise ValueError("BGM が本編より短いです(start から本編の長さ以上が要ります)")


def clips_of(project):
    """台本の映像の区間の並び。"clips" がなければ、source・source_start の 1 区間。"""
    default_tag = project.get("tag", PROFILES[project["profile"]]["tag"])
    if "clips" not in project:
        return [{"source": project["source"], "events": project["events"], "start": float(project["source_start"]),
                 "duration": float(project["duration"]), "tag": default_tag, "autoplay": True, "logo": True,
                 "guest": None}]
    return [{"source": c["source"], "events": c.get("events"), "audio_note": c.get("audio_note"),
             "start": float(c["start"]), "duration": float(c["duration"]), "tag": c.get("tag", default_tag),
             "autoplay": c.get("autoplay", True), "logo": c.get("logo", True), "guest": c.get("guest")}
            for c in project["clips"]]


def check_logged_clip(source, events_path, start, duration):
    """出来事ログのある録画: 音声の監視・ログとの組み合わせ・使える範囲を確かめ、換算済みのログを返す。"""
    source = ROOT / source
    aligned = json.loads((ROOT / events_path).read_text())
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
    if not all(math.isfinite(x) for x in (start, duration)) or start < 0 or duration <= 0 or start + duration > aligned["safe_end"]:
        raise ValueError("録画の範囲外、またはボスを含む区間です")
    return aligned


def check_unlogged_clip(clip):
    """ログのない録画(タイトル・設定などの画面操作)。音声の確かめ方を台本に書いてあるものだけ使う。"""
    source = ROOT / clip["source"]
    if not source.is_file():
        raise ValueError(f"録画がありません: {clip['source']}")
    if not isinstance(clip.get("audio_note"), str) or not clip["audio_note"].strip():
        raise ValueError(f"ログのない録画には、ほかのアプリの音が入っていないことの確かめ方 (audio_note) が要ります: {clip['source']}")
    start, duration = clip["start"], clip["duration"]
    if not all(math.isfinite(x) for x in (start, duration)) or start < 0 or duration <= 0 or start + duration > media_duration(source):
        raise ValueError(f"録画の範囲外です: {clip['source']}")


def check_guest(guest, profile):
    """メンバーとして紹介するキャラ。話している本人以外で、色とバストアップの絵があること。"""
    if guest not in PROFILES or guest == profile:
        raise ValueError(f"メンバーとして紹介できないキャラです: {guest}")
    if not (ROOT / f"promo/characters/bust/{guest}/normal_closed.png").is_file():
        raise ValueError(f"{guest} のバストアップの絵がありません")


def guest_card(guest, font_path):
    """メンバーの紹介: バストアップの下に「メンバー」と名前の札。ゲーム映像の右側に置く。"""
    colors = PROFILES[guest]
    bust = Image.open(ROOT / f"promo/characters/bust/{guest}/normal_closed.png").convert("RGBA")
    bust = bust.crop(bust.getchannel("A").getbbox())
    bust = bust.resize((round(bust.width * 250 / bust.height), 250), Image.Resampling.LANCZOS)
    small, big = ImageFont.truetype(font_path, 20), ImageFont.truetype(font_path, 34)
    width = max(bust.width, round(big.getlength(colors["name"])) + 40, 150)
    card = Image.new("RGBA", (width, 250 + 78), (0, 0, 0, 0))
    card.alpha_composite(bust, ((width - bust.width) // 2, 0))
    d = ImageDraw.Draw(card)
    d.rounded_rectangle((0, 238, width - 1, 327), radius=14, fill=colors["accent"], outline="white", width=3)
    d.text((width / 2, 258), "メンバー", font=small, fill=colors["accent_text"], anchor="mm")
    d.text((width / 2, 296), colors["name"], font=big, fill=colors["accent_text"], anchor="mm")
    return card


def load_project(path):
    project = json.loads(path.read_text())
    if project.get("profile") not in NARRATORS:
        raise ValueError(f"帯の色などが決まっていないキャラです: {project.get('profile')}")
    clips = clips_of(project)
    for clip in clips:
        if clip["tag"] is not None and not (ROOT / "promo/assets" / clip["tag"]).is_file():
            raise ValueError(f"タグの画像がありません: {clip['tag']}")
        if clip["guest"] is not None:
            check_guest(clip["guest"], project["profile"])
    duration = float(project["duration"])
    if "clips" in project:
        if not clips or abs(sum(c["duration"] for c in clips) - duration) > 1e-6:
            raise ValueError("clips の長さの合計が duration と一致しません")
        if any("event_seq" in line for line in project["lines"]):
            raise ValueError("clips を使う台本では、出来事に合わせた反応はまだ使えません")
        for clip in clips:
            if clip["events"]:
                check_logged_clip(clip["source"], clip["events"], clip["start"], clip["duration"])
            else:
                check_unlogged_clip(clip)
        aligned, start = {"events": []}, 0
    else:
        start = float(project["source_start"])
        aligned = check_logged_clip(project["source"], project["events"], start, duration)
    if "bgm" in project:
        check_bgm(project["bgm"], duration)
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
            if not (ROOT / f"promo/characters/bust/{project['profile']}/{expression}_{state}.png").is_file():
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


def draw_text(draw, xy, text, font, fill):
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


def audio_graph(project, out, starts, parts=("game", "voice", "bgm")):
    """mix.wav を作る ffmpeg の入力とフィルタ。parts で、見本パック用に一部の音だけにできる。"""
    duration = project["duration"]
    bgm = project.get("bgm") if "bgm" in parts else None
    inputs, filters, tracks = [], [], []
    if "game" in parts and "clips" not in project:
        inputs += ["-ss", str(project["source_start"]), "-t", str(duration), "-i", str(ROOT / project["source"])]
        filters.append(f"[0:a]aresample=48000,aformat=channel_layouts=stereo,volume={GAME_VOLUME}[game]")
        tracks.append("[game]")
    elif "game" in parts:
        # 区間ごとに長さをそろえてからつなぐ(録画の音声が映像より少し短くても、後ろがずれないように)。
        clips = clips_of(project)
        for i, clip in enumerate(clips):
            inputs += ["-ss", str(clip["start"]), "-t", str(clip["duration"]), "-i", str(ROOT / clip["source"])]
            filters.append(f"[{i}:a]aresample=48000,aformat=channel_layouts=stereo,apad,"
                           f"atrim=duration={clip['duration']},asetpts=PTS-STARTPTS[g{i}]")
        filters.append("".join(f"[g{i}]" for i in range(len(clips))) +
                       f"concat=n={len(clips)}:v=0:a=1,volume={GAME_VOLUME}[game]")
        tracks.append("[game]")
    voices = []
    if "voice" in parts:
        for i, t in enumerate(starts):
            n = sum(1 for x in inputs if x == "-i")
            inputs += ["-i", str(out / f"voice-{i:03}.wav")]
            filters.append(f"[{n}:a]aresample=48000,aformat=channel_layouts=stereo,adelay={round(t*1000)}:all=1[v{i}]")
            voices.append(f"[v{i}]")
    if bgm:
        n = sum(1 for x in inputs if x == "-i")
        inputs += ["-i", str(ROOT / bgm["file"])]
        b_start, volume = float(bgm.get("start", 0)), float(bgm.get("volume", 0.2))
        fade_in, fade_out = float(bgm.get("fade_in", 0.5)), float(bgm.get("fade_out", 2.0))
        chain = (f"[{n}:a]aresample=48000,aformat=channel_layouts=stereo,atrim=start={b_start}:duration={duration},"
                 f"asetpts=PTS-STARTPTS,volume={volume}")
        if fade_in:
            chain += f",afade=t=in:d={fade_in}"
        if fade_out:
            chain += f",afade=t=out:st={duration - fade_out}:d={fade_out}"
        if bgm.get("duck", True) and voices:
            filters.append(chain + "[bgmraw]")
            filters.append("".join(voices) + f"amix=inputs={len(voices)}:normalize=0,apad,atrim=duration={duration},asplit=2[voice][key]")
            filters.append(f"[bgmraw][key]{DUCK}[bgm]")
            voices = ["[voice]"]
        else:
            filters.append(chain + "[bgm]")
        tracks += voices + ["[bgm]"]
    else:
        tracks += voices
    filters.append("".join(tracks) + f"amix=inputs={len(tracks)}:normalize=0,alimiter=limit=0.95:latency=1,apad,atrim=duration={duration}[mix]")
    return inputs, filters


def copy_voices(project, out, source):
    """BGM だけを変えた台本のために、前の出力フォルダの声と台詞の長さを写す。"""
    if any(out.iterdir()):
        raise FileExistsError("出力先は空のフォルダを指定してください")
    prepared = json.loads((source / "prepared.json").read_text())
    if without_bgm(project) != without_bgm(prepared["project"]):
        raise ValueError("BGM 以外の台本が、声を作ったときと違います。--prepare-only で声を作り直してください")
    for i in range(len(prepared["timed"])):
        shutil.copy2(source / f"voice-{i:03}.wav", out / f"voice-{i:03}.wav")
    prepared["project"] = project
    prepared["voices_from"] = str(source)
    (out / "prepared.json").write_text(json.dumps(prepared, ensure_ascii=False, indent=2) + "\n")
    print(f"{source} の声を写しました", flush=True)


def render(project, out):
    movie = out / "preview.mp4"
    if movie.exists() or (out / "mix.wav").exists():
        raise FileExistsError("出力動画か合成音声が既にあります。上書きしません")
    prepared = json.loads((out / "prepared.json").read_text())
    if project != prepared["project"]:
        raise ValueError("台本が音声作成時から変わっています。別の出力先で音声を作り直してください")
    lines = [{**line, **timed, "audio": audio_data(out / f"voice-{i:03}.wav")}
             for i, (line, timed) in enumerate(zip(project["lines"], prepared["timed"]))]
    duration = project["duration"]
    clips = clips_of(project)
    inputs, filters = audio_graph(project, out, [line["start"] for line in lines])
    subprocess.run(["ffmpeg", "-v", "error", "-n", *inputs, "-filter_complex", ";".join(filters),
                    "-map", "[mix]", "-c:a", "pcm_s16le", str(out / "mix.wav")], check=True)
    subtitle_font = ImageFont.truetype(str(ROOT / "promo/build/fonts/NotoSansCJK-Bold.ttc"), 42)
    small = ImageFont.truetype(str(ROOT / "promo/build/fonts/NotoSansCJK-Bold.ttc"), 24)
    colors = PROFILES[project["profile"]]
    bust = ROOT / "promo/characters/bust" / project["profile"]
    belt = Image.new("RGB", SIZE, colors["belt"])
    d = ImageDraw.Draw(belt)
    d.rounded_rectangle((368, 890, 1888, 1054), radius=22, fill=colors["box"], outline=colors["outline"], width=3)
    sprites = {}
    for expression in {"normal", *[l.get("expression", "normal") for l in lines]}:
        for state in ("closed", "open"):
            im = Image.open(bust / f"{expression}_{state}.png").convert("RGBA")
            sprites[expression, state] = im.resize((347, 340), Image.Resampling.LANCZOS)
    blink = Image.open(bust / "normal_blink.png").convert("RGBA").resize((347, 340), Image.Resampling.LANCZOS)
    for line in lines:
        line["caption"] = wrap(line["text"], subtitle_font, 1430)
    # 話している人の名札。字幕の枠の左上にかけて置き、話している間だけ出す(掛け合いに備える)。
    name_font = ImageFont.truetype(str(ROOT / "promo/build/fonts/NotoSansCJK-Bold.ttc"), 26)
    name = colors["name"]
    name_width = round(name_font.getlength(name)) + 36
    name_tag = Image.new("RGBA", (name_width, 38), (0, 0, 0, 0))
    ImageDraw.Draw(name_tag).rounded_rectangle((0, 0, name_width - 1, 37), radius=10, fill=colors["outline"])
    ImageDraw.Draw(name_tag).text((name_width / 2, 18), name, font=name_font, fill=colors["name_text"], anchor="mm")
    def overlay(asset, width):
        im = Image.open(ROOT / "promo/assets" / asset).convert("RGBA")
        return im.resize((width, round(im.height * width / im.width)), Image.Resampling.LANCZOS)
    logo = overlay("logo/title-logo.png", 220)
    tags = {c["tag"]: overlay(c["tag"], 300) for c in clips if c["tag"]}
    guests = {c["guest"]: guest_card(c["guest"], str(ROOT / "promo/build/fonts/NotoSansCJK-Bold.ttc"))
              for c in clips if c["guest"]}
    # 区間ごとのコマの範囲。四捨五入の誤差がたまらないように、累計の秒からコマ番号を決める。
    bounds, elapsed = [], 0.0
    for clip in clips:
        bounds.append((round(elapsed * FPS), round((elapsed + clip["duration"]) * FPS), clip))
        elapsed += clip["duration"]

    def decode(clip):
        return ["ffmpeg", "-v", "error", "-ss", str(clip["start"]), "-i", str(ROOT / clip["source"]), "-t", str(clip["duration"]),
                "-vf", "scale=1920:864,fps=24", "-an", "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"]
    encode = ["ffmpeg", "-v", "error", "-n", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "1920x1080", "-r", str(FPS),
              "-i", "pipe:0", "-i", str(out / "mix.wav"), "-map", "0:v", "-map", "1:a", "-c:v", "libx264",
              "-preset", "veryfast", "-crf", "19", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k",
              "-movflags", "+faststart", "-t", str(duration), str(movie)]
    expected = round(duration * FPS)
    frame_bytes = GAME_SIZE[0] * GAME_SIZE[1] * 3
    reader = None
    with subprocess.Popen(encode, stdin=subprocess.PIPE) as writer:
        try:
            for n in range(expected):
                first, _, clip = next(b for b in bounds if b[0] <= n < b[1])
                if n == first:
                    if reader:
                        reader.stdout.close()
                        if reader.wait():
                            raise RuntimeError("ffmpegの読み込みが失敗しました")
                    reader = subprocess.Popen(decode(clip), stdout=subprocess.PIPE)
                raw = reader.stdout.read(frame_bytes)
                if len(raw) != frame_bytes:
                    raise RuntimeError(f"録画が途中で終わりました: {n}/{expected}コマ ({clip['source']})")
                frame = belt.copy()
                frame.paste(Image.frombytes("RGB", GAME_SIZE, raw), (0, 0))
                # タイトル・設定の画面は、画面の中にロゴや見出しがあるので重ねない("logo": false)。
                if clip["logo"]:
                    frame.paste(logo, (24, 20), logo)
                if clip["tag"]:
                    frame.paste(tags[clip["tag"]], (1580, 24), tags[clip["tag"]])
                if clip["guest"]:
                    card = guests[clip["guest"]]
                    frame.paste(card, (1900 - card.width, 130), card)
                draw = ImageDraw.Draw(frame)
                if clip["autoplay"]:
                    draw.text((1720, 826), "自動プレイ映像", font=small, fill="white", stroke_width=2, stroke_fill=OVER_GAME_STROKE)
                draw.text((22, 1050), f"音声：AivisSpeech {prepared['profile']['speakerName']}", font=small, fill=colors["credit"])
                t = n / FPS
                current = next((l for l in lines if l["start"] <= t < l["end"]), None)
                expression = current.get("expression", "normal") if current else "normal"
                state = "open" if current and speaking(current["audio"], t - current["start"]) else "closed"
                sprite = sprites[expression, state]
                if current is None and 3.25 <= t % 4.2 < 3.4:
                    sprite = blink
                frame.paste(sprite, (12, 712), sprite)
                if current:
                    frame.paste(name_tag, (392, 868), name_tag)
                    captions = current["caption"]
                    top = 972 - len(captions) * 28
                    for i, caption in enumerate(captions):
                        draw_text(draw, (406, top + 56 * i), caption, subtitle_font, colors["text"])
                writer.stdin.write(frame.tobytes())
                if n in (FPS * 3, FPS * 15, FPS * 30):
                    frame.save(out / f"still-{n//FPS:02}.jpg", quality=93)
                if n and n % (FPS * 10) == 0:
                    print(f"{n//FPS}/{duration}秒", flush=True)
        except BaseException:
            if reader:
                reader.terminate()
            writer.terminate()
            raise
        finally:
            if reader:
                reader.stdout.close()
            writer.stdin.close()
        if (reader and reader.wait()) or writer.wait():
            raise RuntimeError("ffmpegの読み込みか書き出しが失敗しました")
    report = {"frames": expected, "fps": FPS, "duration": duration,
              "clips": [{k: c[k] for k in ("source", "start", "duration", "tag")} for c in clips],
              "timed": prepared["timed"], "game_volume": GAME_VOLUME}
    if "bgm" in project:
        report["bgm"] = project["bgm"]
    (out / "timing.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(movie, flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--voices-from", type=Path, help="BGM だけを変えた台本のとき、声を作った出力フォルダ")
    args = parser.parse_args()
    if args.prepare_only and args.voices_from:
        parser.error("--prepare-only と --voices-from は一緒に使えません")
    args.out.mkdir(parents=True, exist_ok=True)
    project = load_project(args.project)
    if args.prepare_only:
        prepare(project, args.out)
    elif args.voices_from:
        copy_voices(project, args.out, args.voices_from)
        render(project, args.out)
    else:
        render(project, args.out)
