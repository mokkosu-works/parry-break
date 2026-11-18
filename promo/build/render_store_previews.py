"""Render captioned Android review cuts for the two store videos."""

from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "capture" / "raw"
OUT = ROOT / "build" / "out"
FONT = ROOT / "build" / "fonts" / "NotoSansCJK-Bold.ttc"
TAGS = ROOT / "assets" / "tags"
MODE_TAGS = {
    1: "wakana_tag_stage.png",
    2: "akane_tag_endless.png",
    3: "momoka_tag_daily.png",
    4: "shizuku_tag_practice.png",
}

PLANS = {
    "play": [
        ("long-stage-mitsuba-s11-sloppy-01/capture.mp4", 11.1, 3, "パリィで、撃ち返せ。"),
        ("long-stage-mitsuba-s11-sloppy-01/capture.mp4", 14.1, 6, "ブロック崩し × パリィ"),
        ("long-stage-mitsuba-s12-just-02/capture.mp4", 12.6, 7, "一手で、盤面が崩れる。"),
        ("long-stage-mitsuba-s14-just-01/capture.mp4", 19.1, 7, "つなげて、フィーバー。"),
        ("long-stage-mitsuba-s21-just-05/capture.mp4", 30.1, 2, "60ステージ"),
        ("mtitle_v151.mp4", 0.5, 3, ""),
    ],
    "modes": [
        ("long-stage-mitsuba-s11-sloppy-01/capture.mp4", 11.1, 2, "4つのモード"),
        ("long-stage-mitsuba-s21-just-05/capture.mp4", 17.5, 5, "1面ずつクリア"),
        ("long-endless-mitsuba-mode-endless-02/capture.mp4", 13, 5, "どこまで進める？"),
        ("long-daily-mitsuba-mode-daily-02/capture.mp4", 13, 5, "今日の5ラウンド"),
        ("long-practice-mitsuba-mode-practice-02/capture.mp4", 15.8, 5, "パリィのタイミングを磨く"),
        ("mtitle_v151.mp4", 0.5, 4, ""),
    ],
}


def render(name: str) -> None:
    clips = PLANS[name]
    OUT.mkdir(parents=True, exist_ok=True)
    if not FONT.exists():
        raise FileNotFoundError(FONT)
    args = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y"]
    filters = []
    for i, (file, start, duration, caption) in enumerate(clips):
        args.extend(["-ss", str(start), "-t", str(duration), "-i", str(RAW / file)])
    if name == "modes":
        for i in MODE_TAGS:
            args.extend(["-loop", "1", "-i", str(TAGS / MODE_TAGS[i])])
    for i, (file, start, duration, caption) in enumerate(clips):
        video = (
            f"[{i}:v]fps=30,scale=1920:864,"
            "pad=1920:1080:0:108:color=0x07060A,setsar=1,format=yuv420p"
        )
        if caption:
            text_file = OUT / f".store-{name}-{i}.txt"
            text_file.write_text(caption, encoding="utf-8")
            video += (
                f",drawtext=fontfile={FONT}:textfile={text_file}:"
                "fontsize=56:fontcolor=white:borderw=3:bordercolor=0x16111F:"
                "x=(w-text_w)/2:y=974"
            )
        if name == "modes" and i in MODE_TAGS:
            filters.append(video + f"[base{i}]")
            filters.append(f"[{len(clips) + i - 1}:v]scale=370:-1[tag{i}]")
            filters.append(f"[base{i}][tag{i}]overlay=x=60:y=3:shortest=1[v{i}]")
        else:
            filters.append(video + f"[v{i}]")
        filters.append(
            f"[{i}:a]aresample=48000,atrim=duration={duration},asetpts=PTS-STARTPTS,"
            f"afade=t=in:st=0:d=0.12,afade=t=out:st={duration - 0.15}:d=0.15[a{i}]"
        )
    chain = "".join(f"[v{i}][a{i}]" for i in range(len(clips)))
    filters.append(f"{chain}concat=n={len(clips)}:v=1:a=1[v][joined]")
    filters.append("[joined]loudnorm=I=-18:TP=-3:LRA=9,alimiter=limit=0.75:level=false[a]")
    version = "v04" if name == "modes" else "v03"
    target = OUT / f"store-{name}-captioned-{version}.mp4"
    args.extend(
        [
            "-filter_complex", ";".join(filters),
            "-map", "[v]", "-map", "[a]",
            "-c:v", "libx264", "-preset", "medium", "-crf", "19",
            "-pix_fmt", "yuv420p", "-r", "30",
            "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2",
            "-movflags", "+faststart", str(target),
        ]
    )
    subprocess.run(args, check=True)
    print(target)


if __name__ == "__main__":
    names = sys.argv[1:] or ["play", "modes"]
    for item in names:
        if item not in PLANS:
            raise SystemExit(f"Unknown plan: {item}")
        render(item)
