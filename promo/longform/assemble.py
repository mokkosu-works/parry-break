#!/usr/bin/env python3
"""通常尺の完成版を 1 本にまとめる: オープニング → (章の区切り → 本編) × 章の数 → エンディング。

python3 promo/longform/assemble.py <構成.json> --out <出力フォルダ> --prepare-only   # 声を作る(AivisSpeech が要る)
python3 promo/longform/assemble.py <構成.json> --out <出力フォルダ>                  # 組み立てる(音声エンジン不要)

本編は render_long.py で書き出し済みのものを使う。構成に書いた台本と、書き出したときの台本が違えば止まる。
配置はアカネの構成案(scene_proposals.py、本人確認済み)を土台にし、色はキャラごと(render_long.PROFILES)。
変わり目の「間」は構成の "gaps" にそろえる(場面の後ろの無音を切り、区切りの長さをタイトルに合わせる)。
BGM はまだ入れない(本人が DAW で作る。bgm.md)。出力は上書きしない。
"""

import argparse
import json
from pathlib import Path
import subprocess
import sys

from PIL import Image, ImageColor, ImageDraw, ImageFont, ImageOps

from full_preview import POSES, audio_data, speaking
from render_long import PROFILES, NARRATORS, wrap

ROOT = Path(__file__).resolve().parents[2]
FPS = 24
SIZE = (1920, 1080)
FONT = str(ROOT / "promo/build/fonts/NotoSansCJK-Bold.ttc")
HEADINGS = ROOT / "promo/assets/text/longform"
LOGO = ROOT / "promo/assets/logo/title-logo.png"
ICON = ROOT / "app/branding/icons/icon-512.png"
BADGES = [ROOT / "promo/build/assets/badges/googleplay.png", ROOT / "promo/build/assets/badges/appstore.png"]
# 体を動かさない場面のまばたき(render.py の BLINK_* と同じ間隔)。
BLINK_FIRST, BLINK_EVERY, BLINK_LENGTH = 1.2, 3.4, 0.13
# 区切りでタイトルを読み始める前の、最低限の間。
MIN_LEAD = 0.3
# 場面の後ろを切ったところで、音を小さくしていく長さ。
FADE = 0.3
ENCODE = ["-c:v", "libx264", "-preset", "veryfast", "-crf", "19", "-pix_fmt", "yuv420p", "-r", str(FPS),
          "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2", "-movflags", "+faststart"]


def font(size):
    return ImageFont.truetype(FONT, size)


def put(canvas, im, xy, *, width=None, height=None):
    bbox = im.getchannel("A").getbbox()
    if bbox:
        im = im.crop(bbox)
    if width:
        im = im.resize((width, round(im.height * width / im.width)), Image.Resampling.LANCZOS)
    elif height:
        im = im.resize((round(im.width * height / im.height), height), Image.Resampling.LANCZOS)
    canvas.alpha_composite(im, xy)
    return im


def fit(im, *, width=None, height=None):
    bbox = im.getchannel("A").getbbox()
    if bbox:
        im = im.crop(bbox)
    if width:
        return im.resize((width, round(im.height * width / im.width)), Image.Resampling.LANCZOS)
    return im.resize((round(im.width * height / im.height), height), Image.Resampling.LANCZOS)


def swap_light_dark(im, dark):
    """白い文字に濃い縁の見出しを、濃い文字に白い縁へ入れ替える(明るい背景の上で読めるように)。元の画像は変えない。"""
    rgba = im.convert("RGBA")
    lightness = ImageOps.invert(rgba.convert("L"))  # 白→0、濃い→255
    swapped = ImageOps.colorize(lightness, black=dark, white="white").convert("RGBA")
    swapped.putalpha(rgba.getchannel("A"))
    return swapped


def mix(base, accent, amount):
    """base に accent を amount の割合で混ぜた色(不透明)。"""
    rgb = [round(x * (1 - amount) + y * amount) for x, y in zip(ImageColor.getrgb(base)[:3], ImageColor.getrgb(accent)[:3])]
    return "#%02X%02X%02X" % tuple(rgb)


def rounded(im, radius):
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, im.width - 1, im.height - 1), radius=radius, fill=255)
    out = im.convert("RGBA")
    out.putalpha(mask)
    return out


def name_tag(colors):
    f = font(26)
    width = round(f.getlength(colors["name"])) + 36
    tag = Image.new("RGBA", (width, 38), (0, 0, 0, 0))
    d = ImageDraw.Draw(tag)
    d.rounded_rectangle((0, 0, width - 1, 37), radius=10, fill=colors["outline"])
    d.text((width / 2, 18), colors["name"], font=f, fill=colors["name_text"], anchor="mm")
    return tag


def full_body(profile):
    """ショートと同じ 6 ポーズのシートから、閉じ・開き・まばたきの絵を切り出す(editor/sprites.py)。"""
    sys.path.insert(0, str(ROOT / "promo/editor"))
    from sprites import isolate_sheet
    folder = ROOT / "promo/characters/sheets" / profile
    return {s: isolate_sheet(str(folder / f"{s}.png"), (folder / f"{s}.png").stat().st_mtime_ns)
            for s in ("closed", "open", "blink")}


# ---- 変わり目の間の計算(ほかに影響しないので、テストで確かめる) ----

def trimmed_length(length, last_end, gaps):
    """場面の最後の台詞のあとに残す無音を、「タイトルの前」の間から最低限の読み始めを引いた長さまでにする。"""
    return min(length, last_end + gaps["before_title"] - MIN_LEAD)


def card_timing(prev_tail, title_length, body_head, gaps):
    """区切りの(読み始めの時刻, 長さ)。前の場面に残った無音と、本編の最初の台詞までの時間で、間をそろえる。"""
    lead = max(MIN_LEAD, gaps["before_title"] - prev_tail)
    after = max(0.0, gaps["after_title"] - body_head)
    length = lead + title_length + after
    if length < gaps["card_min"]:
        extra = (gaps["card_min"] - length) / 2
        lead, length = lead + extra, gaps["card_min"]
    return lead, length


def ending_offset(prev_tail, first_start, gaps):
    """エンディングの台詞をずらす秒数(前の場面の無音と合わせて「エンディングの前」の間にする)。"""
    return max(MIN_LEAD, gaps["before_ending"] - prev_tail) - first_start


def frames_of(seconds):
    return max(1, round(seconds * FPS))


# ---- 構成の確認と声 ----

def scenes(plan):
    """声のある場面: (鍵, 台詞)。区切りの台詞は、組み立てのときに読み始めを決めるので開始時刻を持たない。"""
    out = [("opening", plan["opening"]["lines"])]
    for i, chapter in enumerate(plan["chapters"], 1):
        out.append((f"chapter-{i:02}", [{"start": 0.0, "text": chapter["line"]["text"]}]))
    out.append(("ending", plan["ending"]["lines"]))
    return out


def check_plan(plan):
    if plan.get("profile") not in NARRATORS:
        raise ValueError(f"帯の色などが決まっていないキャラです: {plan.get('profile')}")
    gaps = plan.get("gaps", {})
    for key in ("before_title", "after_title", "before_ending", "card_min"):
        if not isinstance(gaps.get(key), (int, float)) or gaps[key] < 0:
            raise ValueError(f"gaps.{key} を秒で書いてください")
    for key in ("opening", "ending"):
        if not (HEADINGS / plan[key]["heading"]).is_file():
            raise ValueError(f"見出しの画像がありません: {plan[key]['heading']}")
        last = -1
        for line in plan[key]["lines"]:
            if not last < line["start"] < plan[key]["duration"]:
                raise ValueError(f"{key} の台詞は時刻順に、場面の中に置いてください")
            last = line["start"]
    missing = [str(b.relative_to(ROOT)) for b in BADGES if not b.is_file()]
    if missing:
        raise ValueError(f"ストアのバッジがありません: {missing}。promo/build/fetch_assets.sh で取ってください")
    for chapter in plan["chapters"]:
        if not (HEADINGS / chapter["heading"]).is_file():
            raise ValueError(f"見出しの画像がありません: {chapter['heading']}")
        if not chapter.get("line", {}).get("text"):
            raise ValueError(f"{chapter['title']} の区切りで読むタイトル (line.text) がありません")
        for part in chapter["parts"]:
            script = json.loads((ROOT / part["script"]).read_text())
            render = ROOT / part["render"]
            prepared = json.loads((render / "prepared.json").read_text())
            if prepared["project"] != script:
                raise ValueError(f"{part['render']} は、今の台本 {part['script']} で書き出したものではありません")
            if script["profile"] != plan["profile"]:
                raise ValueError(f"{part['script']} のキャラが構成と違います")
            if not (render / "preview.mp4").is_file():
                raise ValueError(f"{part['render']}/preview.mp4 がありません")


def prepare(plan, out):
    sys.path.insert(0, str(ROOT / "promo/editor"))
    from render import synthesize, voice_timing
    if any(out.iterdir()):
        raise FileExistsError("音声の出力先は空のフォルダを指定してください")
    record = {"plan": plan, "timed": {}}
    for key, lines in scenes(plan):
        limit = plan[key]["duration"] if key in ("opening", "ending") else 60
        timed, problems = voice_timing(lines, limit, print, profile=plan["profile"])
        if problems:
            raise ValueError(" / ".join(problems))
        for i, line in enumerate(timed):
            (out / f"{key}-{i:02}.wav").write_bytes(synthesize(line["text"], plan["profile"])[0])
        record["timed"][key] = timed
    (out / "prepared.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n")
    print("オープニング・章の区切り・エンディングの声を保存しました", flush=True)


# ---- 場面を作る ----

def voice_track(out, key, timed, duration, dest):
    inputs, filters = [], []
    for i, line in enumerate(timed):
        inputs += ["-i", str(out / f"{key}-{i:02}.wav")]
        filters.append(f"[{i}:a]aresample=48000,aformat=channel_layouts=stereo,adelay={round(line['start'] * 1000)}:all=1[v{i}]")
    filters.append("".join(f"[v{i}]" for i in range(len(timed))) +
                   f"amix=inputs={len(timed)}:normalize=0,apad,atrim=duration={duration}[mix]")
    subprocess.run(["ffmpeg", "-v", "error", "-n", *inputs, "-filter_complex", ";".join(filters),
                    "-map", "[mix]", "-c:a", "pcm_s16le", str(dest)], check=True)


def talking_scene(out, key, plan, timed, frames, background, sprites, sprite_xy, subtitle, dest):
    """全身が話す場面。timed は開始時刻を決めた台詞。subtitle が None なら字幕を出さない。"""
    colors = PROFILES[plan["profile"]]
    duration = frames / FPS
    lines = [{**t, "audio": audio_data(out / f"{key}-{i:02}.wav")} for i, t in enumerate(timed)]
    if subtitle:
        box, width, size = subtitle
        caption_font, tag = font(size), name_tag(colors)
        for line in lines:
            line["caption"] = wrap(line["text"], caption_font, width)
    sound = out / f"{key}.wav"
    voice_track(out, key, timed, duration, sound)
    encode = ["ffmpeg", "-v", "error", "-n", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{SIZE[0]}x{SIZE[1]}",
              "-r", str(FPS), "-i", "pipe:0", "-i", str(sound), "-map", "0:v", "-map", "1:a", *ENCODE,
              "-frames:v", str(frames), str(dest)]
    with subprocess.Popen(encode, stdin=subprocess.PIPE) as writer:
        try:
            for n in range(frames):
                t = n / FPS
                frame = background.copy()
                current = next((l for l in lines if l["start"] <= t < l["end"]), None)
                state = "closed"
                if current and speaking(current["audio"], t - current["start"]):
                    state = "open"
                elif not current and t >= BLINK_FIRST and (t - BLINK_FIRST) % BLINK_EVERY < BLINK_LENGTH:
                    state = "blink"
                frame.alpha_composite(sprites[state], sprite_xy)
                if current and subtitle:
                    d = ImageDraw.Draw(frame)
                    d.rounded_rectangle(box, radius=22, fill=colors["box"], outline=colors["outline"], width=3)
                    frame.alpha_composite(tag, (box[0] + 24, box[1] - 22))
                    step = round(size * 1.33)
                    top = (box[1] + box[3]) // 2 - len(current["caption"]) * step // 2
                    for i, caption in enumerate(current["caption"]):
                        d.text((box[0] + 38, top + step * i), caption, font=caption_font, fill=colors["text"])
                writer.stdin.write(frame.convert("RGB").tobytes())
        finally:
            writer.stdin.close()
        if writer.wait():
            raise RuntimeError(f"{dest.name} の書き出しに失敗しました")


def pose_sprites(sheets, pose, height):
    index = POSES.index(pose)
    out = {}
    for state in ("closed", "open", "blink"):
        im = sheets[state][index]
        im = im.crop(im.getchannel("A").getbbox())
        out[state] = im.resize((round(im.width * height / im.height), height), Image.Resampling.LANCZOS)
    return out


def credit_voice(layer, plan, y=1046):
    sys.path.insert(0, str(ROOT / "promo/editor"))
    from render import VOICE_PROFILES
    ImageDraw.Draw(layer).text((22, y), f"音声：AivisSpeech {VOICE_PROFILES[plan['profile']]['speakerName']}",
                               font=font(24), fill=PROFILES[plan["profile"]]["credit"])


def opening(plan, out, sheets, timed, frames, dest):
    scene, colors = plan["opening"], PROFILES[plan["profile"]]
    # 背景はキャラの色(ショートと同じ)。左に全身を置く帯を、少し濃い色で斜めに区切る。
    bg = Image.new("RGBA", SIZE, colors["belt"])
    d = ImageDraw.Draw(bg)
    d.polygon([(0, 0), (700, 0), (575, 1080), (0, 1080)], fill=mix(colors["belt"], colors["outline"], .25))
    d.line([(700, 0), (575, 1080)], fill=colors["outline"], width=6)
    put(bg, Image.open(LOGO).convert("RGBA"), (850, 175), width=650)
    put(bg, swap_light_dark(Image.open(HEADINGS / scene["heading"]), colors["text"]), (755, 580), width=1060)
    credit_voice(bg, plan)
    sprites = pose_sprites(sheets, "normal", 870)
    talking_scene(out, "opening", plan, timed, frames, bg, sprites, (330 - sprites["closed"].width // 2, 150),
                  ((730, 820, 1820, 1000), 1000, 42), dest)


def chapter_card(plan, out, number, chapter, sheets, timed, frames, dest):
    colors = PROFILES[plan["profile"]]
    card = Image.new("RGBA", SIZE, colors["belt"])
    d = ImageDraw.Draw(card)
    d.rectangle((0, 0, 1920, 12), fill=colors["outline"])
    d.rectangle((0, 1068, 1920, 1080), fill=colors["outline"])
    put(card, Image.open(LOGO).convert("RGBA"), (80, 62), width=290)
    # タイトルの枠は濃い色のまま(見出しの白い文字が読めるように)。見出しは枠の中心に置く。
    box = (580, 328, 1820, 718)
    d.rounded_rectangle(box, radius=24, fill="#302719", outline=colors["outline"], width=4)
    d.rectangle((580, 400, 596, 645), fill=colors["outline"])
    d.text((660, 345), number, font=font(80), fill=colors["outline"])
    heading = Image.open(HEADINGS / chapter["heading"]).convert("RGBA")
    heading = fit(heading, width=min(1080, round(heading.width * 180 / heading.height)))
    card.alpha_composite(heading, ((box[0] + box[2]) // 2 - heading.width // 2 + 8,
                                   (box[1] + box[3]) // 2 - heading.height // 2 + 30))
    # 下の帯にかからない高さに置く。
    credit_voice(card, plan, y=1030)
    sprites = pose_sprites(sheets, "special", 760)
    talking_scene(out, f"chapter-{number}", plan, timed, frames, card, sprites,
                  (260 - sprites["closed"].width // 2, 244), None, dest)


def ending(plan, out, sheets, timed, frames, dest):
    scene, colors = plan["ending"], PROFILES[plan["profile"]]
    bg = Image.new("RGBA", SIZE, colors["belt"])
    d = ImageDraw.Draw(bg)
    d.rectangle((0, 0, 1920, 12), fill=colors["outline"])
    # 右半分は YouTube の終了画面の要素(動画・チャンネル登録)を置く場所なので、何も描かない。
    d.line((1060, 95, 1060, 1010), fill=colors["outline"], width=3)
    # 左: ロゴ → アプリのアイコン → 「ストアで検索」 → ストアのバッジ を縦に並べる(中心 x=775)。
    center, y = 775, 70
    for im in (fit(Image.open(LOGO).convert("RGBA"), width=420),
               rounded(Image.open(ICON).convert("RGBA").resize((180, 180), Image.Resampling.LANCZOS), 40),
               fit(swap_light_dark(Image.open(HEADINGS / scene["heading"]), colors["text"]), width=470)):
        bg.alpha_composite(im, (center - im.width // 2, y))
        y += im.height + 34
    badges = [fit(Image.open(b).convert("RGBA"), height=84) for b in BADGES]
    x = center - (sum(b.width for b in badges) + 24) // 2
    for b in badges:
        bg.alpha_composite(b, (x, y + 10))
        x += b.width + 24
    credit_voice(bg, plan)
    sprites = pose_sprites(sheets, "success", 755)
    talking_scene(out, "ending", plan, timed, frames, bg, sprites, (250 - sprites["closed"].width // 2, 278), None, dest)


# ---- 組み立て ----

def frame_count(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-count_packets",
                          "-show_entries", "stream=nb_read_packets", "-of", "csv=p=0", str(path)],
                         capture_output=True, text=True, check=True).stdout
    return int(out.strip())


def timestamp(seconds):
    s = int(seconds)
    return f"{s // 60}:{s % 60:02}"


def shifted(timed, offset):
    return [{**t, "start": t["start"] + offset, "end": t["end"] + offset} for t in timed]


def render(plan, out):
    final = out / "full.mp4"
    if final.exists():
        raise FileExistsError("完成版が既にあります。上書きしません")
    prepared = json.loads((out / "prepared.json").read_text())
    if prepared["plan"] != plan:
        raise ValueError("構成が声を作ったときと違います。別の出力先で --prepare-only からやり直してください")
    work = out / "parts"
    work.mkdir(exist_ok=True)
    if any(work.iterdir()):
        raise FileExistsError(f"{work} が空ではありません")
    gaps, timed = plan["gaps"], prepared["timed"]
    sheets = full_body(plan["profile"])
    # pieces: (ファイル, 使うコマ数, 後ろを切ったか, 最初の台詞の開始, 最後の台詞の終わり)
    pieces, starts, report = [], [("オープニング", 0)], []

    open_timed = timed["opening"]
    open_frames = frames_of(trimmed_length(plan["opening"]["duration"], open_timed[-1]["end"], gaps))
    print("オープニング", flush=True)
    opening(plan, out, sheets, open_timed, open_frames, work / "00-opening.mp4")
    pieces.append((work / "00-opening.mp4", open_frames, False, open_timed[0]["start"], open_timed[-1]["end"]))

    for i, chapter in enumerate(plan["chapters"], 1):
        number = f"{i:02}"
        prev_tail = pieces[-1][1] / FPS - pieces[-1][4]
        parts = []
        for j, part in enumerate(chapter["parts"]):
            render_dir = ROOT / part["render"]
            part_timed = json.loads((render_dir / "prepared.json").read_text())["timed"]
            movie = render_dir / "preview.mp4"
            frames = frame_count(movie)
            cut = False
            if j == len(chapter["parts"]) - 1:
                keep = frames_of(trimmed_length(frames / FPS, part_timed[-1]["end"], gaps))
                cut, frames = keep < frames, min(frames, keep)
            parts.append((movie, frames, cut, part_timed[0]["start"], part_timed[-1]["end"]))
        title = timed[f"chapter-{number}"][0]
        lead, length = card_timing(prev_tail, title["duration"], parts[0][3], gaps)
        card_frames = frames_of(length)
        print(f"章 {number}(区切り {card_frames / FPS:.2f} 秒)", flush=True)
        card = work / f"{number}-0-card.mp4"
        chapter_card(plan, out, number, chapter, sheets, shifted(timed[f"chapter-{number}"], lead), card_frames, card)
        report.append((f"{pieces[-1][0].parent.name}/{pieces[-1][0].name} → 区切り {number}", "タイトルの前", prev_tail + lead))
        report.append((f"区切り {number} → 本編", "タイトルの後", card_frames / FPS - lead - title["duration"] + parts[0][3]))
        starts.append((f"{number} {chapter['title']}", len(pieces)))
        pieces.append((card, card_frames, False, lead, lead + title["duration"]))
        pieces += parts

    prev_tail = pieces[-1][1] / FPS - pieces[-1][4]
    end_timed = shifted(timed["ending"], ending_offset(prev_tail, timed["ending"][0]["start"], gaps))
    if end_timed[-1]["end"] > plan["ending"]["duration"]:
        raise ValueError("エンディングの台詞をずらすと、エンディングに収まりません")
    report.append(("07 → エンディング", "エンディングの前", prev_tail + end_timed[0]["start"]))
    print("エンディング", flush=True)
    starts.append(("エンディング", len(pieces)))
    end_frames = frames_of(plan["ending"]["duration"])
    ending(plan, out, sheets, end_timed, end_frames, work / "99-ending.mp4")
    pieces.append((work / "99-ending.mp4", end_frames, False, end_timed[0]["start"], end_timed[-1]["end"]))

    # 場面ごとに、使うコマ数を正とし、音声をその長さにそろえてからつなぐ。後ろを切った場面は音を小さくしていく。
    offsets = [sum(p[1] for p in pieces[:i]) / FPS for i in range(len(pieces))]
    elapsed = sum(p[1] for p in pieces) / FPS
    chapters = [(timestamp(offsets[i]), name) for name, i in starts]
    inputs, labels = [], []
    for i, (piece, frames, cut, _, _) in enumerate(pieces):
        length = frames / FPS
        inputs += ["-i", str(piece)]
        fade = f",afade=t=out:st={length - FADE:.3f}:d={FADE}" if cut else ""
        labels.append(f"[{i}:v]setpts=PTS-STARTPTS,setsar=1,fps={FPS},trim=end_frame={frames},format=yuv420p[v{i}];"
                      f"[{i}:a]asetpts=PTS-STARTPTS,aresample=48000,aformat=channel_layouts=stereo,"
                      f"apad,atrim=duration={length}{fade}[a{i}]")
    graph = ";".join(labels) + ";" + "".join(f"[v{i}][a{i}]" for i in range(len(pieces))) + \
        f"concat=n={len(pieces)}:v=1:a=1[v][a]"
    print("つなぎ合わせ", flush=True)
    subprocess.run(["ffmpeg", "-v", "error", "-n", *inputs, "-filter_complex", graph, "-map", "[v]", "-map", "[a]",
                    *ENCODE, str(final)], check=True)
    actual = frame_count(final) / FPS
    if abs(actual - elapsed) > .5 / FPS:
        raise RuntimeError(f"完成版の長さ {actual:.2f} 秒が、構成の合計 {elapsed:.2f} 秒と合いません")
    text = "\n".join(f"{t} {name}" for t, name in chapters)
    (out / "chapters.txt").write_text(text + "\n")
    (out / "timing.json").write_text(json.dumps({
        "duration": actual, "chapters": chapters, "gaps": [{"where": w, "kind": k, "seconds": round(s, 3)} for w, k, s in report],
        "pieces": [{"file": str(p[0].resolve().relative_to(ROOT)), "frames": p[1], "trimmed": p[2]} for p in pieces]},
        ensure_ascii=False, indent=2) + "\n")
    print("変わり目の間:")
    for where, kind, seconds in report:
        print(f"  {where:<40} {kind}: {seconds:.2f} 秒")
    print(text)
    print(f"{final} ({actual:.1f} 秒)", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("plan", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    plan = json.loads(args.plan.read_text())
    check_plan(plan)
    args.out.mkdir(parents=True, exist_ok=True)
    if args.prepare_only:
        prepare(plan, args.out)
    else:
        render(plan, args.out)


if __name__ == "__main__":
    main()
