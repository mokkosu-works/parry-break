#!/usr/bin/env python3
"""通常尺の BGM のたたき台を、標準 MIDI ファイル (SMF) で作る。DAW (Sonar) で開いて、音源を割り当てて仕上げる。

python3 promo/longform/bgm_midi.py mitsuba-basics            # promo/assets/bgm/midi/mitsuba-basics-bgm-v01.mid
python3 promo/longform/bgm_midi.py mitsuba-basics --version 2

標準ライブラリだけで動く。既存ファイルは上書きしない。使い方と決まりは promo/longform/bgm.md の「MIDI のたたき台」。

- 音色の番号 (プログラムチェンジ) は入れない。TTS-1 のない Sonar を前提にし、各トラックに手元の音源を割り当てる。
  トラック名に、割り当てる音の種類を書く。ドラムは GM の配置 (キック C1=36 など、チャンネル 10)。
- ゲームの BGM は A マイナー → (コンボ段階 4) B マイナー → (FEVER TIME) D マイナーと、キーとテンポ (132〜168) が動く
  (app/lib/audio/sound_bank.dart)。3 つのキーすべてに入っている音 D・E・G・A だけで和音と飾りを作り、
  テンポは 132〜168 から離す。音名がこの 4 つから外れたら、書き出す前に止まる。
- マーカーは骨組み (promo/design/longform-<名前>-outline-v*.md) の章の始まりの目安。曲の区切りは 4 小節単位で、
  マーカーとは少しずれる。動画ができたら bgm_kit.py の cues.md に合わせて、DAW で区切りを動かす。
"""

import argparse
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "promo/assets/bgm/midi"
PPQ = 480
STEP = PPQ // 4            # 16 分音符
BAR = STEP * 16            # 4/4 の 1 小節
SAFE_PITCH_CLASSES = {2, 4, 7, 9}  # D, E, G, A

# トラック: (名前, チャンネル 0 始まり)。名前は Sonar で文字化けしないよう英数字だけにする。
TRACKS = {
    "drums": ("Drums (GM drum kit)", 9),
    "bass": ("Bass (soft synth bass)", 0),
    "pad": ("Pad (warm soft pad)", 1),
    "keys": ("Keys (pluck or electric piano)", 2),
    "bell": ("Bell (glockenspiel or music box)", 3),
}

KICK, SNARE, CLAP, HAT, OPEN_HAT, CRASH = 36, 38, 39, 42, 46, 49

# 4 小節でひと回りする和音。音はすべて D・E・G・A。
# (名前, ベースの根音, パッドの音)
MITSUBA_CHORDS = [
    ("Dsus2", 38, [62, 64, 69]),
    ("Gsus2", 43, [62, 67, 69]),
    ("Em7sus4", 40, [64, 67, 69, 74]),
    ("Asus4", 45, [64, 69, 74]),
]

# 曲の区切り: (名前, 小節数, 重ねるもの)。小節は 1 から数える。
# 強さ: light=音数を減らす (台詞の多い章)、normal、full、fever。
MITSUBA_SECTIONS = [
    ("Opening", 4, {"pad", "bell", "hat:light"}),
    ("01 Game", 12, {"pad", "bass:light", "kick:normal", "hat:light"}),
    ("02 Tap", 16, {"pad", "bass:normal", "kick:normal", "snare", "hat:normal", "keys:stab"}),
    ("03 Collapse", 12, {"pad", "bass:normal", "kick:normal", "snare", "hat:normal", "keys:stab", "build"}),
    ("04 Fever", 12, {"pad", "bass:full", "kick:fever", "snare", "hat:fever", "keys:stab", "bell", "crash"}),
    ("05 Items", 8, {"pad", "bass:normal", "kick:normal", "hat:light", "keys:arp"}),
    ("06 Modes", 16, {"pad", "bass:normal", "kick:normal", "snare", "hat:normal", "keys:stab"}),
    ("07 Daily", 12, {"pad", "bass:light", "hat:light", "keys:arp"}),
    ("Ending", 8, {"pad", "bass:full", "kick:full", "snare", "hat:normal", "keys:stab", "bell", "crash"}),
    ("Last chord", 4, {"last"}),
]

# 骨組み longform-mitsuba-outline-v01.md の章の始まり (秒)。
MITSUBA_MARKERS = [
    (0, "Opening"), (12, "01 Game"), (42, "02 Tap"), (82, "03 Collapse"), (112, "04 Fever"),
    (137, "05 Items"), (162, "06 Modes"), (200, "07 Daily"), (228, "Ending"), (248, "Video end (about)"),
]

# アカネのエンドレス紹介 (design/longform-akane-outline-v01.md)。ボールひとつの緊張感を出すため、
# ミツバより少し速く、和音の順を変え、飾りの音も別にする。
AKANE_CHORDS = [
    ("Asus4", 45, [64, 69, 74]),
    ("Em7sus4", 40, [64, 67, 69, 74]),
    ("Dsus2", 38, [62, 64, 69]),
    ("Gsus2", 43, [62, 67, 69]),
]

AKANE_SECTIONS = [
    ("Opening", 6, {"pad", "bell", "hat:light"}),
    ("01 One ball", 21, {"pad", "bass:light", "kick:normal", "hat:light", "keys:arp"}),
    ("02 Parry", 26, {"pad", "bass:normal", "kick:normal", "snare", "hat:normal", "keys:stab"}),
    ("03 Collapse", 16, {"pad", "bass:normal", "kick:normal", "snare", "hat:normal", "keys:stab", "build"}),
    ("03 Fever", 14, {"pad", "bass:full", "kick:fever", "snare", "hat:fever", "keys:stab", "bell", "crash"}),
    ("04 Record", 13, {"pad", "bass:light", "kick:normal", "hat:light", "keys:arp"}),
    ("Ending", 10, {"pad", "bass:full", "kick:full", "snare", "hat:normal", "keys:stab", "bell", "crash"}),
    ("Last chord", 4, {"last"}),
]

# 骨組みの章の始まり (秒)。
AKANE_MARKERS = [
    (0, "Opening"), (12, "01 One ball"), (58, "02 Parry"), (113, "03 Collapse"),
    (178, "04 Record"), (205, "Ending"), (225, "Video end (about)"),
]

SONGS = {
    "mitsuba-basics": {
        "bpm": 96,
        "chords": MITSUBA_CHORDS,
        "sections": MITSUBA_SECTIONS,
        "markers": MITSUBA_MARKERS,
        # 2 小節の飾り (8 分音符の位置, 音)。
        "bell": [[(0, 81), (4, 79), (8, 76)], [(0, 74), (6, 76), (8, 79)]],
    },
    "akane-endless": {
        "bpm": 112,
        "chords": AKANE_CHORDS,
        "sections": AKANE_SECTIONS,
        "markers": AKANE_MARKERS,
        "bell": [[(0, 86), (3, 81), (6, 79)], [(0, 76), (4, 79), (7, 81)]],
    },
}


def vlq(n):
    out = [n & 0x7F]
    while n > 0x7F:
        n >>= 7
        out.append((n & 0x7F) | 0x80)
    return bytes(reversed(out))


def meta(kind, data):
    return bytes([0xFF, kind]) + vlq(len(data)) + data


def track_chunk(events):
    """events: (tick, 並べる順, bytes)。同じ時刻では音を止めてから鳴らす。"""
    body, last = b"", 0
    for tick, _, data in sorted(events, key=lambda e: (e[0], e[1])):
        body += vlq(tick - last) + data
        last = tick
    body += vlq(0) + meta(0x2F, b"")
    return b"MTrk" + struct.pack(">I", len(body)) + body


def build(song):
    notes = {key: [] for key in TRACKS}  # (開始 tick, 長さ tick, 音, 強さ)

    def note(track, start, length, pitch, vel):
        notes[track].append((start, length, pitch, vel))

    chords = song["chords"]
    bar_no = 0
    for _name, bars, parts in song["sections"]:
        for i in range(bars):
            t0 = bar_no * BAR
            chord_name, root, pad = chords[bar_no % len(chords)]
            last_bar_of_section = i == bars - 1
            level = {p.split(":")[0]: (p.split(":") + [""])[1] for p in parts}

            if "last" in level:
                if i == 0:
                    first_root, first_pad = chords[0][1], chords[0][2]
                    for p in first_pad:
                        note("pad", t0, BAR * bars - STEP, p, 58)
                    note("bass", t0, BAR * 2, first_root, 70)
                    note("bell", t0, BAR * 2, 74, 48)
                    note("drums", t0, STEP, CRASH, 70)
                bar_no += 1
                continue

            if "pad" in level:
                for p in pad:
                    note("pad", t0, BAR - STEP // 2, p, 55)

            bass = level.get("bass")
            if bass == "light":
                for s in (0, 8):
                    note("bass", t0 + s * STEP, 6 * STEP, root, 72)
            elif bass in ("normal", "full"):
                pattern = [(0, 3, 0), (6, 2, 0), (8, 3, 0), (14, 2, 12)]
                if bass == "full":
                    pattern = [(0, 3, 0), (3, 1, 0), (6, 2, 0), (8, 3, 0), (11, 1, 0), (14, 2, 12)]
                for s, length, up in pattern:
                    note("bass", t0 + s * STEP, length * STEP - 10, root + up, 82 if s % 8 == 0 else 70)

            kick = level.get("kick")
            if kick:
                steps = {"normal": (0, 8), "full": (0, 6, 8), "fever": (0, 4, 8, 12)}[kick]
                if "build" in level and last_bar_of_section:
                    steps = (0,)
                for s in steps:
                    note("drums", t0 + s * STEP, STEP, KICK, 95)

            if "snare" in level:
                if "build" in level and last_bar_of_section:
                    for s in range(16):  # フィーバーへ向けて 16 分で強くなる
                        note("drums", t0 + s * STEP, STEP // 2, SNARE, 40 + s * 4)
                else:
                    for s in (4, 12):
                        note("drums", t0 + s * STEP, STEP, CLAP if level.get("kick") == "fever" else SNARE, 88)

            hat = level.get("hat")
            if hat == "light":
                for s in (2, 6, 10, 14):
                    note("drums", t0 + s * STEP, STEP // 2, HAT, 55)
            elif hat == "normal":
                for s in range(0, 16, 2):
                    note("drums", t0 + s * STEP, STEP // 2, HAT, 70 if s % 4 == 2 else 52)
            elif hat == "fever":
                for s in range(16):
                    if s % 4 == 2:
                        note("drums", t0 + s * STEP, STEP, OPEN_HAT, 72)
                    else:
                        note("drums", t0 + s * STEP, STEP // 2, HAT, 64 if s % 2 == 0 else 46)

            if "crash" in level and i == 0:
                note("drums", t0, STEP, CRASH, 90)

            keys = level.get("keys")
            top = [p + 12 for p in pad[-3:]]
            if keys == "stab":
                for s in (2, 6, 10, 14):
                    for p in top:
                        note("keys", t0 + s * STEP, STEP + STEP // 2, p, 58)
            elif keys == "arp":
                order = top + [top[1]]
                for k, s in enumerate(range(0, 16, 2)):
                    note("keys", t0 + s * STEP, STEP * 2 - 20, order[k % len(order)], 54 if k % 2 else 62)

            if "bell" in level:
                for s8, p in song["bell"][i % 2]:
                    note("bell", t0 + s8 * 2 * STEP, STEP * 3, p, 50)

            bar_no += 1

    for key, items in notes.items():
        if key == "drums":
            continue
        for _, _, pitch, _ in items:
            if pitch % 12 not in SAFE_PITCH_CLASSES:
                raise SystemExit(f"{key} に D・E・G・A 以外の音 ({pitch}) がある")
    return notes, bar_no


def write(song, path):
    notes, bars = build(song)
    bpm = song["bpm"]
    tempo_track = [
        (0, 0, meta(0x03, b"Tempo and markers")),
        (0, 0, meta(0x51, struct.pack(">I", round(60_000_000 / bpm))[1:])),
        (0, 0, meta(0x58, bytes([4, 2, 24, 8]))),
    ]
    ticks_per_second = bpm / 60 * PPQ
    for sec, name in song["markers"]:
        tempo_track.append((round(sec * ticks_per_second), 1, meta(0x06, name.encode("ascii"))))
    chunks = [track_chunk(tempo_track)]
    for key, (name, ch) in TRACKS.items():
        events = [(0, 0, meta(0x03, name.encode("ascii")))]
        for start, length, pitch, vel in notes[key]:
            events.append((start, 2, bytes([0x90 | ch, pitch, max(1, min(127, vel))])))
            events.append((start + length, 1, bytes([0x80 | ch, pitch, 0])))
        chunks.append(track_chunk(events))
    header = b"MThd" + struct.pack(">IHHH", 6, 1, len(chunks), PPQ)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(header + b"".join(chunks))
    seconds = bars * 4 * 60 / bpm
    return bars, seconds, {k: len(v) for k, v in notes.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("song", choices=sorted(SONGS))
    parser.add_argument("--version", type=int, default=1)
    parser.add_argument("--out", type=Path, help=f"既定は {OUT_DIR.relative_to(ROOT)}/<曲>-bgm-v<版>.mid")
    args = parser.parse_args()
    path = args.out or OUT_DIR / f"{args.song}-bgm-v{args.version:02}.mid"
    if path.exists():
        raise SystemExit(f"{path} はもうある。--version を上げる")
    bars, seconds, counts = write(SONGS[args.song], path)
    print(f"{path.relative_to(ROOT) if path.is_relative_to(ROOT) else path}: "
          f"{bars} 小節、約 {int(seconds // 60)} 分 {seconds % 60:.0f} 秒、テンポ {SONGS[args.song]['bpm']}")
    print("音の数: " + "、".join(f"{TRACKS[k][0].split(' ')[0]} {n}" for k, n in counts.items()))


if __name__ == "__main__":
    main()
