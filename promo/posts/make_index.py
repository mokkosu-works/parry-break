#!/usr/bin/env python3
"""posts/一覧.md を作る (何度でも作り直せる。動画や記録は触らない)。

YouTube Studio で動画のタイトルを変えても、「長さ」と「冒頭の字幕」から、どの ID か分かるようにする。
長さは records/videos.csv の「長さ(秒)」を使う (build.py が書く)。空のときだけ promo/build/out/ の動画を測る。
  python3 promo/posts/make_index.py
"""
import csv, json, pathlib, subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
HOOK_TYPE = {"A": "惜しい失敗", "B": "見栄え", "C": "結果"}


def duration(path):
    out = subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)])
    return round(float(out))


def main():
    with (ROOT / "promo/records/videos.csv").open(encoding="utf-8-sig", newline="") as f:
        rows = list(csv.DictReader(f))
    lines = ["# 動画の一覧", "",
             "YouTube Studio でタイトルを変えても、**長さ**と**冒頭の字幕**で ID を探せる。",
             "投稿文 (`posts/{ID}.txt`) の「管理」の節にある ID を、YouTube のタグ欄に入れておくと、詳細画面からも分かる。", "",
             "| ID | 投稿日 | パターン | 冒頭 | 長さ | 冒頭の字幕 | 本編の字幕 | ファイル |",
             "| --- | --- | --- | --- | --- | --- | --- | --- |"]
    for r in rows:
        name, hook = r["パターン名"], r["冒頭の種類"]
        spec_path = ROOT / f"promo/build/specs/spec.{name}.json"
        spec = json.loads(spec_path.read_text(encoding="utf-8")) if spec_path.exists() else None
        cap = spec["hooks"][hook]["caption"] if spec else "?"
        body = spec["body"]["caption"] if spec else "?"
        video = ROOT / r["ファイルパス"]
        if (r.get("長さ(秒)") or "").strip():
            sec = f"{round(float(r['長さ(秒)']))}秒"
        else:
            sec = f"{duration(video)}秒" if video.exists() else "?"
        lines.append(f"| {r['id']} | {r['投稿日'] or '-'} | {name} | {hook} {HOOK_TYPE[hook]} | {sec} | {cap} | {body} | `{pathlib.Path(r['ファイルパス']).name}` |")
    (ROOT / "promo/posts/一覧.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"promo/posts/一覧.md を作った ({len(rows)} 行)")


main()
