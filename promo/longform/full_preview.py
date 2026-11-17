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
POSES = ("normal", "focus", "surprise", "fail", "success", "special")  # シートの並び(通常・集中・予想外・失敗・成功・固有)
SIZE = (1920, 1080)
# キャラごとの表示名と仮の台詞。台詞は口パクの確認用で、本番の台本ではない。
CHARS = {
    "akane": {
        "label": "アカネ",
        "voice": "中2",
        "lines": [
            ("normal", "オープニング(通常)", "よしっ、アカネだよ！ 今日はエンドレスを紹介するよ。"),
            ("special", "章の区切り(固有)", "ボールはひとつ。落としたら、そこでおしまい！"),
            ("success", "エンディング(成功)", "キミも挑戦してみて！ パリィブレイク。ストアで検索！"),
        ],
    },
    "mitsuba": {
        "label": "ミツバ",
        "voice": "花音",
        "lines": [
            ("normal", "オープニング(通常)", "こんにちは、ミツバだよ！ 今日は、パリィブレイクの遊び方を、最初から見ていこう！"),
            ("special", "章の区切り(固有)", "ボールはひとつ。落としたら、そこでおしまいなんだ。"),
            ("success", "エンディング(成功)", "まずは、1-1から遊んでみて！ パリィブレイク。ストアで検索！"),
        ],
    },
    "shizuku": {
        "label": "シズク",
        "voice": "zonoko",
        "lines": [
            ("normal", "オープニング(通常)", "シズクです。今日は、練習モードを紹介します。"),
            ("special", "章の区切り(固有)", "落としても、すぐに出直せる。焦らなくていい。"),
            ("success", "エンディング(成功)", "タイミングは、体で覚えて。パリィブレイク。ストアで検索。"),
        ],
    },
    "momoka": {
        "label": "モモカ",
        "voice": "るな",
        "lines": [
            ("normal", "オープニング(通常)", "モモカだよ！ 今日は、デイリーを紹介するね！"),
            ("special", "章の区切り(固有)", "毎日ちがう配置なの。みんな同じ面で遊ぶんだよ！"),
            ("success", "エンディング(成功)", "今日のお題、一緒にやろ？ パリィブレイク。ストアで検索！"),
        ],
    },
    "wakana": {
        "label": "ワカナ",
        "voice": "まい",
        "lines": [
            ("normal", "オープニング(通常)", "ワカナです。今日は、ステージを紹介するわね。"),
            ("special", "章の区切り(固有)", "一面ずつ進めて、星を集めていくのよ。"),
            ("success", "エンディング(成功)", "あなたも、最初の面から。パリィブレイク。ストアで検索。"),
        ],
    },
}


def voice_only(name, dest):
    sys.path.insert(0, str(ROOT / "promo/editor"))
    from render import synthesize, voice_timing, VOICE_PROFILES
    record = {"character": name, "profile": VOICE_PROFILES[name], "lines": []}
    for pose, label, text in CHARS[name]["lines"]:
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
    # ショートと同じ 6 ポーズのシートを、ショートと同じ「輪郭で分離」で切り出す(editor/sprites.py)。
    sys.path.insert(0, str(ROOT / "promo/editor"))
    from sprites import isolate_sheet
    folder = ROOT / "promo/characters/sheets" / name
    sheets = {s: isolate_sheet(str(folder / f"{s}.png"), (folder / f"{s}.png").stat().st_mtime_ns)
              for s in ("closed", "open", "blink")}
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
        index = POSES.index(pose)
        states = {s: sheets[s][index] for s in ("closed", "open")}
        if pose == "normal":
            states["blink"] = sheets["blink"][index]
        # 顔の拡大は、絵の上から 5 割(髪の高いキャラでも口が入る範囲)
        bb = states["closed"].getchannel("A").getbbox()
        face = (bb[0], bb[1], bb[2], bb[1] + round((bb[3] - bb[1]) * .5))
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
                draw.text((70, 38), f"{CHARS[name]['label']} 全身口パク確認  /  {scene['label']}", font=fonts[42], fill="#332b2c")
                draw.text((70, 100), "素材の動きの確認用です。動画本編の画面構成とは異なります。", font=fonts[24], fill="#665a5c")
                draw.text((165, 152), "全身（ショートと同じ絵）", font=fonts[30], fill="#665a5c")
                draw.text((1080, 152), "顔の拡大", font=fonts[30], fill="#665a5c")
                draw.rounded_rectangle((925, 215, 1800, 790), radius=24, fill="#e5ded7")
                draw.text((960, 815), "口の開閉 / オープニングのみ目パチ", font=fonts[24], fill="#665a5c")
                draw.text((70, 1000), f"音声：AivisSpeech {CHARS[name]['voice']}  ｜  試し動画・台詞は仮", font=fonts[24], fill="#665a5c")
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
                    # 話し終えたあとに目パチを1回(オープニングの通常のみ)。口パクとの同時合成は本編で扱う。
                    if scene["pose"] == "normal" and .6 + scene["duration"] + .3 <= t < .6 + scene["duration"] + .47:
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
    parser.add_argument("name", choices=sorted(CHARS))
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
