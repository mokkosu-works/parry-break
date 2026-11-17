#!/usr/bin/env python3
"""通常尺の完成版を 1 本にまとめる: オープニング → (章の区切り → 本編) × 章の数 → エンディング。

python3 promo/longform/assemble.py <構成.json> --out <出力フォルダ> --prepare-only   # 声を作る(AivisSpeech が要る)
python3 promo/longform/assemble.py <構成.json> --out <出力フォルダ>                  # 組み立てる(音声エンジン不要)

本編は render_long.py で書き出し済みのものを使う。構成に書いた台本と、書き出したときの台本が違えば止まる。
配置はアカネの構成案(scene_proposals.py、本人確認済み)と同じで、色はキャラごと(render_long.PROFILES)。
BGM はまだ入れない(本人が DAW で作る。bgm.md)。出力は上書きしない。
"""

import argparse
import json
from pathlib import Path
import subprocess
import sys

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

from full_preview import POSES, audio_data, speaking
from render_long import PROFILES, media_duration, wrap

ROOT = Path(__file__).resolve().parents[2]
FPS = 24
SIZE = (1920, 1080)
FONT = str(ROOT / "promo/build/fonts/NotoSansCJK-Bold.ttc")
HEADINGS = ROOT / "promo/assets/text/longform"
LOGO = ROOT / "promo/assets/logo/title-logo.png"
# 体を動かさない場面のまばたき(render.py の BLINK_* と同じ間隔)。
BLINK_FIRST, BLINK_EVERY, BLINK_LENGTH = 1.2, 3.4, 0.13
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


def still(source, seconds):
    """録画の 1 コマ(RGB)。"""
    out = subprocess.run(["ffmpeg", "-v", "error", "-ss", str(seconds), "-i", str(source), "-frames:v", "1",
                          "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"], capture_output=True, check=True).stdout
    w, h = probe_size(source)
    return Image.frombytes("RGB", (w, h), out)


def probe_size(source):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height",
                          "-of", "csv=p=0", str(source)], capture_output=True, text=True, check=True).stdout
    w, h = map(int, out.strip().split(","))
    return w, h


def backdrop(im, brightness, blur):
    """縦横比をそろえて中央を切り出し、ぼかして暗くする(章の区切り・エンディングの背景)。"""
    target = im.height * SIZE[0] / SIZE[1]
    if im.width >= target:
        left = round((im.width - target) / 2)
        im = im.crop((left, 0, left + round(target), im.height))
    else:
        target_h = im.width * SIZE[1] / SIZE[0]
        top = round((im.height - target_h) / 2)
        im = im.crop((0, top, im.width, top + round(target_h)))
    im = im.resize(SIZE, Image.Resampling.LANCZOS).filter(ImageFilter.GaussianBlur(blur))
    return ImageEnhance.Brightness(im).enhance(brightness).convert("RGBA")


def name_tag(colors):
    f = font(26)
    width = round(f.getlength(colors["name"])) + 36
    tag = Image.new("RGBA", (width, 38), (0, 0, 0, 0))
    d = ImageDraw.Draw(tag)
    d.rounded_rectangle((0, 0, width - 1, 37), radius=10, fill=colors["outline"])
    d.text((width / 2, 18), colors["name"], font=f, fill=colors["box"], anchor="mm")
    return tag


def full_body(profile):
    """ショートと同じ 6 ポーズのシートから、閉じ・開き・まばたきの絵を切り出す(editor/sprites.py)。"""
    sys.path.insert(0, str(ROOT / "promo/editor"))
    from sprites import isolate_sheet
    folder = ROOT / "promo/characters/sheets" / profile
    return {s: isolate_sheet(str(folder / f"{s}.png"), (folder / f"{s}.png").stat().st_mtime_ns)
            for s in ("closed", "open", "blink")}


def scenes(plan):
    """声のある場面: (鍵, 長さ, 台詞)。章の区切りは、章のタイトルを 1 つ読む。"""
    out = [("opening", plan["opening"]["duration"], plan["opening"]["lines"])]
    for i, chapter in enumerate(plan["chapters"], 1):
        out.append((f"chapter-{i:02}", chapter["card"], [chapter["line"]]))
    out.append(("ending", plan["ending"]["duration"], plan["ending"]["lines"]))
    return out


def check_plan(plan):
    if plan.get("profile") not in PROFILES:
        raise ValueError(f"帯の色などが決まっていないキャラです: {plan.get('profile')}")
    for key in ("opening", "ending"):
        if not (HEADINGS / plan[key]["heading"]).is_file():
            raise ValueError(f"見出しの画像がありません: {plan[key]['heading']}")
    for key, duration, lines in scenes(plan):
        last = -1
        for line in lines:
            if not last < line["start"] < duration:
                raise ValueError(f"{key} の台詞は時刻順に、場面の中に置いてください")
            last = line["start"]
    for chapter in plan["chapters"]:
        if not (HEADINGS / chapter["heading"]).is_file():
            raise ValueError(f"見出しの画像がありません: {chapter['heading']}")
        if not 1 <= chapter["card"] <= 5:
            raise ValueError("章の区切りは 1〜5 秒にしてください")
        for part in chapter["parts"]:
            script = json.loads((ROOT / part["script"]).read_text())
            render = ROOT / part["render"]
            prepared = json.loads((render / "prepared.json").read_text())
            if prepared["project"] != script:
                raise ValueError(f"{part['render']} は、今の台本 {part['script']} で書き出したものではありません")
            if script["profile"] != plan["profile"]:
                raise ValueError(f"{part['script']} のキャラが構成と違います")
            if abs(media_duration(render / "preview.mp4") - script["duration"]) > 1 / FPS:
                raise ValueError(f"{part['render']}/preview.mp4 の長さが台本と違います")


def prepare(plan, out):
    sys.path.insert(0, str(ROOT / "promo/editor"))
    from render import synthesize, voice_timing
    if any(out.iterdir()):
        raise FileExistsError("音声の出力先は空のフォルダを指定してください")
    record = {"plan": plan, "timed": {}}
    for key, duration, lines in scenes(plan):
        timed, problems = voice_timing(lines, duration, print, profile=plan["profile"])
        if problems:
            raise ValueError(" / ".join(problems))
        for i, line in enumerate(timed):
            (out / f"{key}-{i:02}.wav").write_bytes(synthesize(line["text"], plan["profile"])[0])
        record["timed"][key] = timed
    (out / "prepared.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n")
    print("オープニング・章の区切り・エンディングの声を保存しました", flush=True)


def voice_track(out, key, timed, duration, dest):
    inputs, filters = [], []
    for i, line in enumerate(timed):
        inputs += ["-i", str(out / f"{key}-{i:02}.wav")]
        filters.append(f"[{i}:a]aresample=48000,aformat=channel_layouts=stereo,adelay={round(line['start'] * 1000)}:all=1[v{i}]")
    filters.append("".join(f"[v{i}]" for i in range(len(timed))) +
                   f"amix=inputs={len(timed)}:normalize=0,apad,atrim=duration={duration}[mix]")
    subprocess.run(["ffmpeg", "-v", "error", "-n", *inputs, "-filter_complex", ";".join(filters),
                    "-map", "[mix]", "-c:a", "pcm_s16le", str(dest)], check=True)


def talking_scene(out, key, plan, duration, layer, background, sprites, sprite_xy, subtitle, dest):
    """全身が話す場面。background は固定の画像か、コマを返す関数。subtitle が None なら字幕を出さない。"""
    colors = PROFILES[plan["profile"]]
    timed = json.loads((out / "prepared.json").read_text())["timed"][key]
    lines = [{**t, "audio": audio_data(out / f"{key}-{i:02}.wav")} for i, t in enumerate(timed)]
    if subtitle:
        box, width, size = subtitle
        caption_font, tag = font(size), name_tag(colors)
        for line in lines:
            line["caption"] = wrap(line["text"], caption_font, width)
    sound = out / f"{key}.wav"
    voice_track(out, key, timed, duration, sound)
    frames = round(duration * FPS)
    encode = ["ffmpeg", "-v", "error", "-n", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{SIZE[0]}x{SIZE[1]}",
              "-r", str(FPS), "-i", "pipe:0", "-i", str(sound), "-map", "0:v", "-map", "1:a", *ENCODE,
              "-t", str(duration), str(dest)]
    with subprocess.Popen(encode, stdin=subprocess.PIPE) as writer:
        try:
            for n in range(frames):
                t = n / FPS
                frame = background(n).copy() if callable(background) else background.copy()
                frame.alpha_composite(layer)
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
                        d.text((box[0] + 38, top + step * i), caption, font=caption_font, fill="white")
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


def opening(plan, out, sheets, dest):
    scene, colors = plan["opening"], PROFILES[plan["profile"]]
    bg = scene["background"]
    source = ROOT / bg["source"]
    w, h = probe_size(source)
    crop = f"crop={round(h * 16 / 9)}:{h}" if w * 9 >= h * 16 else f"crop={w}:{round(w * 9 / 16)}"
    # 後ろのゲーム映像は動かしたまま、ぼかして暗くする。
    decode = ["ffmpeg", "-v", "error", "-ss", str(bg["start"]), "-i", str(source), "-t", str(scene["duration"]),
              "-vf", f"{crop},scale=1920:1080,fps={FPS},gblur=sigma=18,colorlevels=romax=.44:gomax=.44:bomax=.44",
              "-an", "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"]
    reader = subprocess.Popen(decode, stdout=subprocess.PIPE)
    size = SIZE[0] * SIZE[1] * 3

    def background(n):
        raw = reader.stdout.read(size)
        if len(raw) != size:
            raise RuntimeError("オープニングの背景の録画が途中で終わりました")
        return Image.frombytes("RGB", SIZE, raw).convert("RGBA")

    layer = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.polygon([(0, 0), (700, 0), (575, 1080), (0, 1080)], fill=colors["belt"])
    d.line([(700, 0), (575, 1080)], fill=colors["outline"], width=6)
    put(layer, Image.open(LOGO).convert("RGBA"), (850, 175), width=650)
    put(layer, Image.open(HEADINGS / scene["heading"]).convert("RGBA"), (755, 580), width=1060)
    d.text((1820, 1040), "自動プレイ映像", font=font(24), fill="#b9a8b1", anchor="rm")
    credit_voice(layer, plan)
    sprites = pose_sprites(sheets, "normal", 870)
    try:
        talking_scene(out, "opening", plan, scene["duration"], layer, background, sprites, (330 - sprites["closed"].width // 2, 150),
                      ((730, 820, 1820, 1000), 1000, 42), dest)
    finally:
        reader.stdout.close()
        reader.wait()


def credit_voice(layer, plan):
    sys.path.insert(0, str(ROOT / "promo/editor"))
    from render import VOICE_PROFILES
    ImageDraw.Draw(layer).text((22, 1050), f"音声：AivisSpeech {VOICE_PROFILES[plan['profile']]['speakerName']}",
                               font=font(24), fill=PROFILES[plan["profile"]]["credit"])


def chapter_card(plan, out, number, chapter, sheets, dest, work):
    colors = PROFILES[plan["profile"]]
    first = ROOT / chapter["parts"][0]["render"] / "preview.mp4"
    # 背景は、その章の本編の最初のゲーム画面(下の帯を除く)。
    game = still(first, 0.5).crop((0, 0, 1920, 864))
    card = backdrop(game, .26, 24)
    d = ImageDraw.Draw(card)
    d.rectangle((0, 0, 1920, 12), fill=colors["outline"])
    d.rectangle((0, 1068, 1920, 1080), fill=colors["outline"])
    put(card, Image.open(LOGO).convert("RGBA"), (80, 62), width=290)
    d.rounded_rectangle((580, 328, 1820, 718), radius=24, fill=colors["box"], outline=colors["outline"], width=4)
    d.rectangle((580, 400, 596, 645), fill=colors["outline"])
    d.text((660, 345), number, font=font(80), fill=colors["outline"])
    heading = Image.open(HEADINGS / chapter["heading"]).convert("RGBA")
    put(card, heading, (650, 470), width=min(1080, round(heading.width * 180 / heading.height)))
    d.text((1820, 1040), "自動プレイ映像", font=font(24), fill="#b9a8b1", anchor="rm")
    credit_voice(card, plan)
    # 固有のポーズで、章のタイトルを読む(字幕は出さない。見出しが大きく出ているため)。
    sprites = pose_sprites(sheets, "special", 760)
    talking_scene(out, f"chapter-{number}", plan, chapter["card"], Image.new("RGBA", SIZE, (0, 0, 0, 0)), card,
                  sprites, (260 - sprites["closed"].width // 2, 244), None, dest)


def ending(plan, out, sheets, dest):
    scene, colors = plan["ending"], PROFILES[plan["profile"]]
    bg = scene["background"]
    background = backdrop(still(ROOT / bg["source"], bg["at"]), .20, 28)
    layer = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rectangle((0, 0, 1920, 12), fill=colors["outline"])
    # 右半分は YouTube の終了画面の要素(動画 1 枠・チャンネル 1 枠)を置く場所なので、何も描かない。
    d.line((1060, 95, 1060, 1010), fill=colors["outline"], width=3)
    put(layer, Image.open(LOGO).convert("RGBA"), (555, 175), width=440)
    put(layer, Image.open(HEADINGS / scene["heading"]).convert("RGBA"), (545, 470), width=455)
    d.text((1820, 1040), "自動プレイ映像", font=font(24), fill="#b9a8b1", anchor="rm")
    credit_voice(layer, plan)
    sprites = pose_sprites(sheets, "success", 755)
    talking_scene(out, "ending", plan, scene["duration"], layer, background, sprites, (250 - sprites["closed"].width // 2, 278),
                  ((470, 800, 1040, 930), 500, 32), dest)


def frame_count(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-count_packets",
                          "-show_entries", "stream=nb_read_packets", "-of", "csv=p=0", str(path)],
                         capture_output=True, text=True, check=True).stdout
    return int(out.strip())


def timestamp(seconds):
    s = int(seconds)
    return f"{s // 60}:{s % 60:02}"


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
    sheets = full_body(plan["profile"])
    pieces = [work / "00-opening.mp4"]
    print("オープニング", flush=True)
    opening(plan, out, sheets, pieces[0])
    starts = [("オープニング", 0)]
    for i, chapter in enumerate(plan["chapters"], 1):
        number = f"{i:02}"
        print(f"章 {number}", flush=True)
        card = work / f"{number}-0-card.mp4"
        chapter_card(plan, out, number, chapter, sheets, card, work)
        starts.append((f"{number} {chapter['title']}", len(pieces)))
        pieces.append(card)
        pieces += [ROOT / part["render"] / "preview.mp4" for part in chapter["parts"]]
    print("エンディング", flush=True)
    starts.append(("エンディング", len(pieces)))
    pieces.append(work / "99-ending.mp4")
    ending(plan, out, sheets, pieces[-1])
    # 場面ごとに、映像のコマ数を正とし、音声をその長さにそろえてからつなぐ。
    # (長さがコマの区切りに合わない本編では、映像と音声が少し違い、そのままつなぐとずれがたまる)
    frames = [frame_count(p) for p in pieces]
    offsets = [sum(frames[:i]) / FPS for i in range(len(pieces))]
    elapsed = sum(frames) / FPS
    chapters = [(timestamp(offsets[i]), name) for name, i in starts]
    inputs, labels = [], []
    for i, piece in enumerate(pieces):
        inputs += ["-i", str(piece)]
        labels.append(f"[{i}:v]setpts=PTS-STARTPTS,setsar=1,fps={FPS},trim=end_frame={frames[i]},format=yuv420p[v{i}];"
                      f"[{i}:a]asetpts=PTS-STARTPTS,aresample=48000,aformat=channel_layouts=stereo,"
                      f"apad,atrim=duration={frames[i] / FPS}[a{i}]")
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
    (out / "timing.json").write_text(json.dumps({"duration": actual, "pieces": [str(p.resolve().relative_to(ROOT)) for p in pieces],
                                                 "chapters": chapters}, ensure_ascii=False, indent=2) + "\n")
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
