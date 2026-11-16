#!/usr/bin/env python3
"""書き出し済みの本編から、Windows の DAW で BGM を合わせるための見本パックを作る。

python3 promo/longform/bgm_kit.py promo/build/out/akane-endless-pilot-e002 [--bpm 128]

<出力フォルダ>/bgm-kit/ に次を作る (既存ファイルは上書きしない)。
  guide.mp4  いまの本編 (声とゲーム音入り)。DAW に動画として読み込む
  voice.wav  声だけ (48kHz ステレオ、本編と同じ長さ)
  game.wav   録画のゲーム音だけ (本編と同じ音量 0.38)
  cues.csv   台詞と主な出来事の時刻。DAW のマーカー用
  cues.md    同じ内容を読みやすくしたもの
作り方と返すファイルの決まりは promo/longform/bgm.md。
"""

import argparse
import csv
import json
from pathlib import Path
import shutil
import subprocess

from render_long import ROOT, audio_graph

# マーカーにするゲームの出来事 (多すぎるものは除く)。
EVENT_NAMES = {
    "round_started": "ラウンド開始",
    "round_cleared": "ラウンドクリア",
    "fever_start": "フィーバー開始",
    "collapse": "まとめて崩れる",
    "parry:just": "ジャストパリィ",
}


def clock(t):
    m, s = divmod(t, 60)
    return f"{int(m):02}:{s:06.3f}"


def bar_beat(t, bpm, beats):
    beat = t * bpm / 60
    return f"{int(beat // beats) + 1}:{beat % beats + 1:.2f}"


def cues(project, timed):
    rows = [(line["start"], "台詞", f"{line['text']} (〜{line['end']:.2f}秒、{source.get('kind', '')})")
            for line, source in zip(timed, project["lines"])]
    aligned = json.loads((ROOT / project["events"]).read_text())
    start, duration = project["source_start"], project["duration"]
    for event in aligned["events"]:
        key = event["type"] + (f":{event['grade']}" if event["type"] == "parry" and "grade" in event else "")
        t = event["video_s"] - start
        if key in EVENT_NAMES and 0 <= t < duration:
            rows.append((t, "出来事", EVENT_NAMES[key]))
    rows.append((duration, "終わり", "本編の終わり (BGM はここまで鳴っていること)"))
    return sorted(rows, key=lambda r: r[0])


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("out", type=Path, help="render_long.py で書き出したフォルダ")
    parser.add_argument("--bpm", type=float, help="指定すると cues に小節:拍も書く")
    parser.add_argument("--beats", type=int, default=4, help="1 小節の拍の数 (既定 4)")
    args = parser.parse_args()
    out = args.out
    prepared = json.loads((out / "prepared.json").read_text())
    timing = json.loads((out / "timing.json").read_text())
    project, timed = prepared["project"], timing["timed"]
    kit = out / "bgm-kit"
    kit.mkdir(exist_ok=True)
    targets = [kit / name for name in ("guide.mp4", "voice.wav", "game.wav", "cues.csv", "cues.md")]
    if any(p.exists() for p in targets):
        raise SystemExit(f"{kit} に見本が既にあります。上書きしません")

    shutil.copy2(out / "preview.mp4", kit / "guide.mp4")
    starts = [line["start"] for line in timed]
    for name, parts in (("voice.wav", ("voice",)), ("game.wav", ("game",))):
        inputs, filters = audio_graph(project, out, starts, parts)
        subprocess.run(["ffmpeg", "-v", "error", "-n", *inputs, "-filter_complex", ";".join(filters),
                        "-map", "[mix]", "-c:a", "pcm_s16le", str(kit / name)], check=True)

    rows = cues(project, timed)
    header = ["秒", "分:秒", *(["小節:拍"] if args.bpm else []), "種類", "内容"]
    with open(kit / "cues.csv", "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f)
        w.writerow(header)
        for t, kind, text in rows:
            w.writerow([f"{t:.3f}", clock(t), *([bar_beat(t, args.bpm, args.beats)] if args.bpm else []), kind, text])
    md = [f"# BGM の目印 ({out.name})", "",
          f"本編 {project['duration']} 秒、48kHz。0 秒が guide.mp4 の先頭。"
          + (f" 小節:拍は {args.bpm:g} BPM・{args.beats} 拍子で数えた値。" if args.bpm else ""), "",
          "| " + " | ".join(header) + " |", "|" + "---|" * len(header)]
    for t, kind, text in rows:
        md.append("| " + " | ".join([f"{t:.3f}", clock(t), *([bar_beat(t, args.bpm, args.beats)] if args.bpm else []), kind, text]) + " |")
    (kit / "cues.md").write_text("\n".join(md) + "\n", encoding="utf-8")
    print(kit)


if __name__ == "__main__":
    main()
