#!/usr/bin/env python3
"""DAW で書き出した BGM が、promo/longform/bgm.md の決まりに合うかを確かめる。

python3 promo/longform/check_bgm.py <書き出した.wav> --length 45
python3 promo/longform/check_bgm.py <書き出した.wav> --length 45 --to-flac promo/assets/bgm/akane-endless-bgm-v01.flac

標準ライブラリと ffmpeg (ffprobe) だけで動く (Windows・Linux)。
決まりから外れたら理由を出して 1 で終わる。--to-flac は、合格したときだけ変換する (既存ファイルは上書きしない)。
"""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

RATE = 48000
PEAK_MAX = -1.0          # dBFS
LUFS_RANGE = (-22.0, -10.0)  # 目安は -16 前後
HEAD_SILENCE = 0.3       # 秒。これより長い無音で始まったら止める


def ffmpeg_stderr(*args):
    return subprocess.run(["ffmpeg", "-hide_banner", "-nostats", *args, "-f", "null", "-"],
                          capture_output=True, text=True, encoding="utf-8", errors="replace").stderr


def check(path, length):
    info = json.loads(subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
         "stream=sample_rate,channels,codec_name,bits_per_sample,bits_per_raw_sample:format=duration",
         "-of", "json", str(path)], capture_output=True, text=True, check=True).stdout)
    stream, duration = info["streams"][0], float(info["format"]["duration"])
    bits = int(stream.get("bits_per_sample") or 0) or int(stream.get("bits_per_raw_sample") or 0)
    peak = float(re.search(r"max_volume: (-?[\d.]+|-inf) dB", ffmpeg_stderr("-i", str(path), "-af", "volumedetect")).group(1))
    lufs = float(re.findall(r"I:\s+(-?[\d.]+) LUFS", ffmpeg_stderr("-i", str(path), "-af", "ebur128"))[-1])
    head = re.search(r"silence_start: (-?[\d.e-]+)[\s\S]*?silence_end: ([\d.]+)",
                     ffmpeg_stderr("-i", str(path), "-af", f"silencedetect=n=-50dB:d={HEAD_SILENCE}"))
    head_silence = float(head.group(2)) if head and float(head.group(1)) <= 0.01 else 0.0

    print(f"形式: {stream['codec_name']} {stream['sample_rate']}Hz {stream['channels']}ch {bits or '?'}bit")
    print(f"長さ: {duration:.3f} 秒 (本編 {length} 秒)")
    print(f"ピーク: {peak} dBFS / ラウドネス: {lufs} LUFS / 頭の無音: {head_silence:.2f} 秒")
    problems = []
    if int(stream["sample_rate"]) != RATE:
        problems.append(f"サンプルレートを {RATE}Hz にしてください")
    if int(stream["channels"]) != 2:
        problems.append("ステレオで書き出してください")
    if bits and bits < 24 and stream["codec_name"].startswith("pcm"):
        problems.append("24bit で書き出してください")
    if duration + 1e-3 < length:
        problems.append(f"本編 ({length} 秒) より短いです")
    if peak > PEAK_MAX:
        problems.append(f"ピークを {PEAK_MAX} dBFS 以下にしてください (マスターの音量を下げる)")
    if not LUFS_RANGE[0] <= lufs <= LUFS_RANGE[1]:
        problems.append(f"ラウドネスは -16 LUFS 前後 ({LUFS_RANGE[0]:g}〜{LUFS_RANGE[1]:g}) にしてください")
    if head_silence:
        problems.append("頭に無音があります。曲の始まりを 0 秒に揃えて書き出してください")
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("wav", type=Path)
    parser.add_argument("--length", type=float, required=True, help="本編の秒数 (cues.md の先頭に書いてある)")
    parser.add_argument("--to-flac", type=Path, help="合格したら、この名前の FLAC にする")
    args = parser.parse_args()
    problems = check(args.wav, args.length)
    if problems:
        print("\n直すところ:")
        for p in problems:
            print(f"- {p}")
        sys.exit(1)
    print("\n決まりに合っています")
    if args.to_flac:
        if args.to_flac.exists():
            sys.exit(f"{args.to_flac} は既にあります。上書きしません (版の番号を上げてください)")
        args.to_flac.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["ffmpeg", "-v", "error", "-n", "-i", str(args.wav), "-map", "0:a:0",
                        "-c:a", "flac", "-sample_fmt", "s32", "-bits_per_raw_sample", "24", str(args.to_flac)], check=True)
        print(f"FLAC にしました: {args.to_flac}")


if __name__ == "__main__":
    main()
