#!/usr/bin/env python3
"""全身口パクの確認用動画。全身と顔の拡大を並べる(本番の構成案ではない)。

python3 promo/longform/full_preview.py akane --voice-only --out promo/build/out/akane-full-preview-e001
python3 promo/longform/full_preview.py akane --out promo/build/out/akane-full-preview-e001
音声は既存 render.synthesize を使う。2 回目のコマンドは音声エンジン不要。
"""

import argparse
import array
import json
import math
from pathlib import Path
import subprocess
import sys
import wave

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FPS = 24
SIZE = (1920, 1080)
LINES = [
    ("greet", "あいさつ", "よしっ、アカネだよ！ 今日はエンドレスを紹介するよ。"),
    ("guide", "案内", "ボールはひとつ。落としたら、そこでおしまい！"),
    ("close", "締め", "キミも挑戦してみて！ パリィブレイク。ストアで検索！"),
]


def voice_only(name, dest):
    sys.path.insert(0, str(ROOT / "promo/editor"))
    from render import synthesize, voice_timing, VOICE_PROFILES
    record = {"character": name, "profile": VOICE_PROFILES[name], "lines": []}
    for pose, label, text in LINES:
        path = dest / f"{pose}.wav"
        if path.exists():
            raise SystemExit(f"音声が既にあります(上書きしません): {path}")
        data, duration = synthesize(text, profile=name)
        path.write_bytes(data)
        record["lines"].append({"pose": pose, "label": label, "text": text, "duration": duration})
        print(f"{pose}: {duration:.2f} 秒", flush=True)
    total, planned = 0, []
    for line in record["lines"]:
        planned.append({"start": total + .6, "text": line["text"]})
        total += math.ceil((line["duration"] + 1.6) * FPS) / FPS
    timed, problems = voice_timing(planned, total, profile=name)
    if problems:
        raise SystemExit(" / ".join(problems))
    record["timing"] = timed
    (dest / "voice.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n")


def audio_data(path):
    with wave.open(str(path)) as w:
        if w.getsampwidth() != 2:
            raise ValueError("音声は16ビットPCMが必要です")
        rate, channels = w.getframerate(), w.getnchannels()
        samples = array.array("h", w.readframes(w.getnframes()))
    if sys.byteorder != "little":
        samples.byteswap()
    return samples, rate, channels


def speaking(audio, seconds):
    samples, rate, channels = audio
    start = max(0, int(seconds * rate) * channels)
    end = min(len(samples), start + int(rate * .035) * channels)
    if end <= start:
        return False
    rms = math.sqrt(sum(v * v for v in samples[start:end]) / (end - start))
    # 無音は閉じ、発声中だけ約6回/秒で開閉。音素を推定するものではない。
    return rms > 220 and int(seconds * 12) % 2 == 0


def render(name, dest):
    movie = dest / "preview.mp4"
    if movie.exists():
        raise SystemExit(f"動画が既にあります(上書きしません): {movie}")
    data = json.loads((dest / "voice.json").read_text())
    if data["character"] != name:
        raise SystemExit("音声のキャラが一致しません")
    folder = ROOT / "promo/characters/full" / name
    atlas = json.loads((folder / "regions.json").read_text())
    font_path = str(ROOT / "promo/build/fonts/NotoSansCJK-Bold.ttc")
    fonts = {s: ImageFont.truetype(font_path, s) for s in (24, 30, 38, 42)}
    total, scenes = 0, []
    for line in data["lines"]:
        pose = line["pose"]
        audio = audio_data(dest / f"{pose}.wav")
        measured = len(audio[0]) / (audio[1] * audio[2])
        if abs(measured - line["duration"]) > 1 / FPS:
            raise SystemExit(f"{pose}: 音声と記録の長さが一致しません")
        duration = math.ceil((line["duration"] + 1.6) * FPS) / FPS
        states = {s: Image.open(folder / f"{pose}_{s}.png").convert("RGBA") for s in ("closed", "open")}
        if pose == "greet":
            states["blink"] = Image.open(folder / "greet_blink.png").convert("RGBA")
        face = atlas[pose]["face"]
        sprites = {}
        for state, im in states.items():
            full = im.resize((round(im.width * 760 / im.height), 760), Image.Resampling.LANCZOS)
            # 顔を高さ440pxに拡大する。
            crop = im.crop(face).resize((round((face[2] - face[0]) * 440 / (face[3] - face[1])), 440), Image.Resampling.LANCZOS)
            sprites[state] = (full, crop)
        scenes.append({**line, "start": total, "length": duration, "sprites": sprites,
                       "audio": audio})
        total += duration
    # 音声の余白も映像と同じ時刻にそろえ、台詞の切れ・重なりを防ぐ。
    sound = dest / "preview.wav"
    inputs, filters, tracks = [], [], []
    for i, scene in enumerate(scenes):
        inputs += ["-i", str(dest / f"{scene['pose']}.wav")]
        delay = round((scene["start"] + .6) * 1000)
        filters.append(f"[{i}:a]aresample=48000,aformat=channel_layouts=mono,adelay={delay}:all=1[a{i}]")
        tracks.append(f"[a{i}]")
    filters.append("".join(tracks) + f"amix=inputs={len(scenes)}:normalize=0,apad,atrim=duration={total}[a]")
    subprocess.run(["ffmpeg", "-v", "error", "-n", *inputs, "-filter_complex", ";".join(filters),
                    "-map", "[a]", "-c:a", "pcm_s16le", str(sound)], check=True)
    cmd = ["ffmpeg", "-v", "error", "-n", "-f", "rawvideo", "-pixel_format", "rgb24", "-video_size", "1920x1080",
           "-framerate", str(FPS), "-i", "pipe:0", "-i", str(sound), "-c:v", "libx264", "-preset", "veryfast",
           "-crf", "18", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart", str(movie)]
    counts = {s["pose"]: {"closed": 0, "open": 0, "blink": 0} for s in scenes}
    with subprocess.Popen(cmd, stdin=subprocess.PIPE) as proc:
        try:
            for scene in scenes:
                plate = Image.new("RGB", SIZE, "#f3f0eb")
                draw = ImageDraw.Draw(plate)
                draw.text((70, 38), f"アカネ 全身口パク確認  /  {scene['label']}", font=fonts[42], fill="#332b2c")
                draw.text((70, 100), "素材の動きの確認用です。動画本編の画面構成とは異なります。", font=fonts[24], fill="#665a5c")
                draw.text((165, 152), "全身（高さ760px）", font=fonts[30], fill="#665a5c")
                draw.text((1080, 152), "顔の拡大", font=fonts[30], fill="#665a5c")
                draw.rounded_rectangle((925, 215, 1800, 790), radius=24, fill="#e5ded7")
                draw.text((960, 815), "口の開閉 / あいさつのみ目パチ", font=fonts[24], fill="#665a5c")
                draw.text((70, 1000), "音声：AivisSpeech 中2  ｜  試し動画・台詞は仮", font=fonts[24], fill="#665a5c")
                # 字幕は長いものを2行へ。確認用のラベルと字幕はフォント描画。
                text = scene["text"]
                if len(text) > 32:
                    split = text.find("！") + 1
                    if not split or split == len(text):
                        split = text.find("。") + 1
                    text = text[:split] + "\n" + text[split:].strip()
                draw.multiline_text((700, 880), text, font=fonts[38], fill="#332b2c", spacing=12)
                for n in range(round(scene["length"] * FPS)):
                    t = n / FPS
                    state = "open" if speaking(scene["audio"], t - .6) and t >= .6 else "closed"
                    # 話し終えたあとに目パチを1回。口パクとの同時合成は本編で扱う。
                    if scene["pose"] == "greet" and .6 + scene["duration"] + .3 <= t < .6 + scene["duration"] + .47:
                        state = "blink"
                    counts[scene["pose"]][state] += 1
                    frame = plate.copy()
                    full, face = scene["sprites"][state]
                    frame.paste(full, (150, 205), full)
                    frame.paste(face, (1360 - face.width // 2, 285), face)
                    proc.stdin.write(frame.tobytes())
                    if n == 24:
                        frame.save(dest / f"{scene['pose']}-still.jpg", quality=92)
                print(f"{scene['pose']}: {scene['length']:.2f} 秒を書き出しました", flush=True)
        finally:
            proc.stdin.close()
        if proc.wait():
            raise SystemExit("ffmpeg の書き出しが失敗しました")
    report = {"duration": total, "fps": FPS, "size": SIZE, "frames_by_state": counts,
              "lines": [{k: s[k] for k in ("pose", "text", "start", "duration", "length")} for s in scenes]}
    (dest / "timing.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(movie)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("name", choices=["akane"])
    parser.add_argument("--voice-only", action="store_true")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    if args.voice_only:
        voice_only(args.name, args.out)
    else:
        render(args.name, args.out)


if __name__ == "__main__":
    main()
