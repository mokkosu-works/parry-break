#!/usr/bin/env python3
"""同じプレイ映像から、冒頭3秒だけ違う A/B/C の縦動画 (1080x1920) を作る。

使い方:  python3 promo/build.py promo/spec.json [--dry-run] [--no-record] [--posts-only]

構成: [冒頭 3 秒 (A/B/C で違う)] + [本編 (3 本とも完全に同じ)] + [最後の 2 秒: アプリ名 + ストアで検索]
- 字幕は最初のフレームから出す。音はゲーム内の BGM と効果音 (録画の音声) をそのまま使う。外部の BGM は使わない。
- 出力は promo/out/{パターン名}_{A|B|C}.mp4 。既存ファイルは上書きせず、そこで止まる。
- 1 本作るごとに records/videos.csv へ 1 行追記し、posts/{id}.txt に投稿文を書く。
  長さ (秒) も csv に書くので、出力動画のない環境でも make_index.py が同じ一覧を作れる。
"""
import csv, datetime, json, pathlib, re, shutil, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
HOOK_SEC, OUTRO_SEC = 3, 2
CSV_COLS = ["id", "作成日", "パターン名", "冒頭の種類", "タイトル", "説明文", "ファイルパス",
            "投稿日", "媒体", "再生数", "視聴率(視聴 vs スワイプ)", "長さ(秒)"]


def run(cmd):
    subprocess.run([str(c) for c in cmd], check=True)


def duration(path):
    out = subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                                   "-of", "csv=p=0", str(path)])
    return float(out)


DEFAULT_FONT = ROOT / "promo/fonts/DotGothic16-Regular.ttf"  # SIL OFL。ゲーム内の文字と同じ系統


def find_font(spec):
    if spec.get("font"):
        return spec["font"]
    if DEFAULT_FONT.exists():
        return str(DEFAULT_FONT)
    out = subprocess.run(["fc-match", "-f", "%{file}", ":lang=ja"], capture_output=True, text=True)
    if out.returncode or not out.stdout:
        sys.exit("日本語フォントが見つからない。spec.json の font にフォントファイルを指定する")
    return out.stdout


def drawtext(textfile, font, y, size, extra="", title=False):
    color, border, bcolor = ("0xffc61a", 10, "0x8a1c00") if title else ("white", 6, "black")
    return (f"drawtext=fontfile='{font}':textfile='{textfile}':fontsize={size}:fontcolor={color}:"
            f"borderw={border}:bordercolor={bcolor}:x=(w-text_w)/2:y={y}{extra}")


def fit_size(text, max_size=112, width=1000):
    """全角で 1 行に収まる大きさ (半角は狭いので余裕がある)。"""
    return min(max_size, width // max(1, len(text)))


def image_size(path):
    out = subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                   "stream=width,height", "-of", "csv=p=0", str(path)])
    w, h = out.decode().strip().split(",")
    return int(w), int(h)


def has_audio(path):
    out = subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "a", "-show_entries",
                                   "stream=index", "-of", "csv=p=0", str(path)])
    return bool(out.strip())


# 録画の中のプレイ画面 (x, y, 幅, 高さ)。2400x1080 の実機録画で、左右の黒帯を除いた範囲
CROP = (245, 0, 1800, 1080)
FG_TOP = 520  # 縦動画の中でプレイ画面を置く y。TikTok などの下の表示 (約 480px) と上の表示 (約 130px) を避ける
PIXEL_FONT = str(ROOT / "app/assets/fonts/Silkscreen-Bold.ttf")  # ゲーム内と同じドット絵フォント
ICON = ROOT / "app/branding/icons/icon-512.png"
FOOTER = {"tagline": ""}  # main() が spec から入れる

AUDIO_ENC = ["-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2"]


def footer(tmp, font, crop=None):
    """プレイ画面の下に、ロゴ文字と紹介文を出す。全区間 (冒頭・本編) で同じ。"""
    a, b = tmp / "f1.txt", tmp / "f2.txt"
    a.write_text("PARRY BREAK", encoding="utf-8")
    b.write_text(FOOTER["tagline"], encoding="utf-8")
    y1 = FG_TOP + round(1080 * CROP[3] / CROP[2] / 2) * 2 + 32  # 前景の高さは区間で違っても、下の帯の位置は全区間で固定
    logo = (f"drawtext=fontfile='{PIXEL_FONT}':textfile='{a}':fontsize=96:fontcolor=0xffc61a:"
            f"borderw=6:bordercolor=0x8a1c00:x=(w-text_w)/2:y={y1}")
    return logo + "," + drawtext(b, font, y1 + 125, 50)


def segment(src, start, length, caption, out, font, tmp, name, fade_out=0.03, crop=None,
            vfade_in=0.0, vfade_out=0.0, fade_in=0.03):
    """切り出して 1080x1920 に整え、字幕を最初のフレームから載せる。ゲーム内の BGM と効果音は残す。"""
    if not has_audio(src):
        sys.exit(f"{src} に音声がない。画面録画の音声 (内部音声) を入れて撮り直す")
    cap = tmp / f"{name}.txt"
    cap.write_text(caption, encoding="utf-8")
    # 横画面のゲームを縦 9:16 に載せる: 背景はぼかして暗くした拡大、前景はプレイ画面 (幅 1080 に合わせる)。
    # 字幕は前景の上に置く。crop は録画の中のプレイ画面の範囲 (x:y:w:h)。
    cx, cy, cw, ch = crop or CROP
    fg_h = round(1080 * ch / cw / 2) * 2
    fg_y = FG_TOP
    # つなぎ目の暗転: 冒頭の終わり (vfade_out) と、本編の頭 (vfade_in)・終わり (vfade_out) にだけ入れる。
    # 冒頭の最初のフレームは暗転しない (1 フレーム目から見せるため)
    vfx = ""
    if vfade_in:
        vfx += f",fade=t=in:st=0:d={vfade_in}"
    if vfade_out:
        vfx += f",fade=t=out:st={float(length) - vfade_out}:d={vfade_out}"
    fc = (f"[0:v]fps=30,tpad=stop_mode=clone:stop_duration={length},trim=duration={length},setpts=PTS-STARTPTS,split[a][b];"
          f"[a]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=40:6,eq=brightness=-0.3[bg];"
          f"[b]crop={cw}:{ch}:{cx}:{cy},scale=1080:{fg_h}:flags=neighbor[fg];"
          f"[bg][fg]overlay=0:{fg_y},setsar=1," + drawtext(cap, font, "h*0.12", fit_size(caption), title=True) + "," + footer(tmp, font) + vfx + "[v]")
    # 音量はこの区間の中だけで揃える。本編は 1 回だけ作って 3 本で使い回すので、3 本とも同じ音になる
    af = (f"aresample=48000,loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000,apad=whole_dur={length},atrim=duration={length},"
          f"afade=t=in:d={fade_in},afade=t=out:st={float(length) - fade_out}:d={fade_out}")
    run(["ffmpeg", "-y", "-v", "error", "-ss", start, "-t", length, "-i", src, "-filter_complex", fc, "-map", "[v]", "-map", "0:a", "-af", af,
         "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", *AUDIO_ENC, out])


BADGES = [ROOT / "promo/assets/badges/appstore.png", ROOT / "promo/assets/badges/googleplay.png"]
BADGE_H = 120


def outro(spec, out, font, tmp):
    a, b = tmp / "o1.txt", tmp / "o2.txt"
    a.write_text(spec["app_name"], encoding="utf-8")
    text = spec.get("outro_text", "ストアで検索")
    b.write_text(text, encoding="utf-8")
    name = (f"drawtext=fontfile='{PIXEL_FONT}':textfile='{a}':fontsize=100:fontcolor=0xffc61a:"
            f"borderw=6:bordercolor=0x8a1c00:x=(w-text_w)/2:y=760")
    badges = [p for p in BADGES if p.exists()] if spec.get("badges", True) else []
    # 入力: 0 背景, 1 アイコン, 2 音 (無音), 3 以降 ストアの公式バッジ
    fc = (f"[1:v]scale=380:380:flags=neighbor[ic];[0:v][ic]overlay=(W-w)/2:290[v0];"
          f"[v0]{name},{drawtext(b, font, 930, fit_size(text, 100), title=True)}[v1]")
    inputs = ["-f", "lavfi", "-i", f"color=c=0x0b0b1a:s=1080x1920:r=30:d={OUTRO_SEC}",
              "-loop", "1", "-i", ICON, "-f", "lavfi", "-i", f"anullsrc=r=48000:cl=stereo:d={OUTRO_SEC}"]
    last = "v1"
    if badges:
        # 公式の画像は絵を変えず、高さだけ揃える (Google Play の PNG は上下の余白だけ切る)
        widths = []
        for i, bp in enumerate(badges):
            inputs += ["-loop", "1", "-i", bp]
            crop = "crop=iw:ih-58:0:29," if bp.name == "googleplay.png" else ""
            fc += f";[{3 + i}:v]{crop}scale=-1:{BADGE_H}[b{i}]"
            w, h = image_size(bp)
            h -= 58 if bp.name == "googleplay.png" else 0
            widths.append(round(BADGE_H * w / h))
        gap = 40
        x = (1080 - (sum(widths) + gap * (len(widths) - 1))) // 2
        for i, w in enumerate(widths):
            fc += f";[{last}][b{i}]overlay={x}:1110[o{i}]"
            last = f"o{i}"
            x += w + gap
    fc += f";[{last}]fade=t=in:st=0:d=0.3[vf]"
    last = "vf"
    run(["ffmpeg", "-y", "-v", "error", *inputs, "-filter_complex", fc, "-map", f"[{last}]", "-map", "2:a",
         "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p", *AUDIO_ENC, "-t", f"{OUTRO_SEC}", out])


def post_text(spec, rid=None):
    """posts/{id}.txt の中身。YouTube 用 (タイトル・説明文) と TikTok 用 (短いキャプション)。
    upload_youtube.py がこの見出しを読むので、見出しの書式は変えない。"""
    tags = " ".join(spec["hashtags"])
    if "#shorts" not in tags.lower():
        tags += " #Shorts"  # YouTube 用だけ。TikTok のキャプションには足さない
    tiktok = spec.get("tiktok_caption") or (
        f"弾幕を撃ち返すブロック崩し。ストアで「{spec['app_name']}」を検索 " + " ".join(spec["hashtags"][:3]))
    return (f"=== YouTube ===\n[タイトル]\n{spec['title']}\n\n[説明文]\n{spec['description']}\n\n{tags}\n\n"
            f"=== TikTok ===\n[キャプション]\n{tiktok}\n"
            + (f"\n=== 管理 ===\n管理ID: {rid}\nYouTube のタグ欄に入れる: {rid}\n" if rid else ""))


def csv_columns(path):
    """records/videos.csv の列。ない列 (CSV_COLS にあって csv にない) があれば、末尾に足して書き直す。

    手で足した列や並べ替えた列は、そのまま残す。"""
    if not path.exists():
        return list(CSV_COLS)
    with path.open(encoding="utf-8-sig", newline="") as f:
        r = csv.DictReader(f)
        cols, rows = list(r.fieldnames or []), list(r)
    missing = [c for c in CSV_COLS if c not in cols]
    if missing:
        cols += missing
        with path.open("w", encoding="utf-8-sig", newline="") as f:
            w = csv.DictWriter(f, fieldnames=cols, restval="")
            w.writeheader()
            w.writerows(rows)
    return cols


def next_id():
    p = ROOT / "records/videos.csv"
    if not p.exists():
        return "v001"
    nums = [int(m.group(1)) for r in csv.DictReader(p.open(encoding="utf-8-sig"))
            if (m := re.match(r"v(\d+)", r["id"]))]
    n = max(nums or [0])
    return f"v{n + 1:03d}"


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dry = "--dry-run" in sys.argv
    norecord = "--no-record" in sys.argv  # 試験出力: records と posts に書かない
    if not args:
        sys.exit(__doc__)
    spec = json.loads(pathlib.Path(args[0]).read_text(encoding="utf-8"))
    name = spec["name"]
    if "--posts-only" in sys.argv:
        csv_path = ROOT / "records/videos.csv"
        ids = [r["id"] for r in csv.DictReader(csv_path.open(encoding="utf-8-sig")) if r["パターン名"] == name]
        (ROOT / "posts").mkdir(exist_ok=True)
        for rid in ids:
            post = ROOT / f"posts/{rid}.txt"
            if post.exists():
                print("既にある、スキップ:", post)
            else:
                post.write_text(post_text(spec, rid), encoding="utf-8")
                print("出力:", post)
        return
    hooks = spec["hooks"]
    assert sorted(hooks) == ["A", "B", "C"], "hooks は A/B/C の 3 つ"
    body = spec["body"]
    body_len = body["end"] - body["start"]
    total = HOOK_SEC + body_len + OUTRO_SEC
    if not 15 <= total <= 30:
        sys.exit(f"全体が {total:.1f} 秒。15〜30 秒にする (本編を {15-HOOK_SEC-OUTRO_SEC}〜{30-HOOK_SEC-OUTRO_SEC} 秒に)")

    outs = {k: ROOT / f"promo/out/{name}_{k}.mp4" for k in hooks}
    posts = {}
    for k in hooks:
        if outs[k].exists():
            sys.exit(f"既にある: {outs[k]} (上書きしない。spec の name を変える)")
    if dry:
        print(f"OK: 全体 {total:.1f} 秒、出力予定 {[str(p.relative_to(ROOT)) for p in outs.values()]}")
        return
    if not shutil.which("ffmpeg"):
        sys.exit("ffmpeg がない: sudo apt install -y ffmpeg")

    font = find_font(spec)
    FOOTER["tagline"] = spec.get("tagline", "弾幕を撃ち返す、ドット絵ブロック崩し")
    (ROOT / "promo/out").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory() as t:
        tmp = pathlib.Path(t)
        # 本編と最後は 1 回だけ作り、3 本で使い回す (= 完全に同じ)
        segment(ROOT / "promo" / body["file"], str(body["start"]), str(body_len), body["caption"],
                tmp / "body.mp4", font, tmp, "body", fade_out=0.6, vfade_in=0.15, vfade_out=0.35, fade_in=0.15)
        outro(spec, tmp / "outro.mp4", font, tmp)
        for k, h in hooks.items():
            segment(ROOT / "promo" / h["file"], str(h["start"]), str(HOOK_SEC), h["caption"],
                    tmp / f"hook{k}.mp4", font, tmp, f"hook{k}", crop=h.get("crop"),
                    fade_out=0.15, vfade_out=0.15)
            lst = tmp / f"list{k}.txt"
            lst.write_text("".join(f"file '{tmp / n}'\n" for n in (f"hook{k}.mp4", "body.mp4", "outro.mp4")))
            joined = tmp / f"joined{k}.mp4"
            run(["ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", joined])
            cmd = ["ffmpeg", "-n", "-v", "error", "-i", joined, "-c", "copy", outs[k]]
            run(cmd)
            print("出力:", outs[k])

    if norecord:
        print("--no-record: records と posts は触らない")
        return
    # 記録と投稿文 (既存の行・ファイルは触らない)
    (ROOT / "records").mkdir(exist_ok=True)
    (ROOT / "posts").mkdir(exist_ok=True)
    csv_path = ROOT / "records/videos.csv"
    vid = next_id()
    today = datetime.date.today().isoformat()
    cols = csv_columns(csv_path)
    with csv_path.open("a", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, restval="")
        if f.tell() == 0:
            w.writeheader()
        for i, k in enumerate(hooks):
            rid = f"{vid}{k.lower()}"
            w.writerow({"id": rid, "作成日": today, "パターン名": name, "冒頭の種類": k,
                        "タイトル": spec["title"], "説明文": spec["description"],
                        "ファイルパス": outs[k].relative_to(ROOT).as_posix(),
                        "長さ(秒)": round(duration(outs[k]))})
            post = ROOT / f"posts/{rid}.txt"
            if post.exists():
                print("投稿文は既にある、スキップ:", post)
                continue
            post.write_text(post_text(spec, rid), encoding="utf-8")
    print("records/videos.csv に 3 行追記、posts/ に投稿文を出力")


main()
