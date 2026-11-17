# 通常尺の BGM

本人が Windows の DAW で作った BGM。作り方と決まりは [../../longform/bgm.md](../../longform/bgm.md)。

- 形式は FLAC(48kHz、24bit、ステレオ)。`promo/longform/check_bgm.py --to-flac` で、決まりに合うか確かめてから変換する。
- ファイル名は `<名前>-<モード>-bgm-v<版>.flac`。作り直したら版を上げる。使わなくなったものは `old/` へ移す。
- DAW のプロジェクトと書き出した WAV は Windows に残す(git に入れない)。
- `midi/` は Claude が作った MIDI のたたき台(`<名前>-<モード>-bgm-v<版>.mid`)。`promo/longform/bgm_midi.py` で作る。Sonar で開いて、音源を割り当てて仕上げる。

| MIDI | どの本編用か | テンポ | 長さ |
|---|---|---|---|
| `midi/mitsuba-basics-bgm-v01.mid` | ミツバのゲーム全体と基本操作(`design/longform-mitsuba-outline-v01.md`) | 96 | 104 小節(約 4 分 20 秒) |
| `midi/akane-endless-bgm-v01.mid` | アカネのエンドレス紹介(`design/longform-akane-outline-v01.md`) | 112 | 110 小節(約 3 分 56 秒) |

| ファイル | どの本編用か | テンポ | DAW のプロジェクトの場所 |
|---|---|---|---|
| `mitsuba-basics-bgm-v01.flac` | ミツバのゲーム全体と基本操作(完成版 `longform/projects/mitsuba-full-v01.json`) | 96 | Windows の `D:\Cakewalk Projects\mitsuba-basics-bgm-v01\`(書き出しは `Audio Export\`)。書き出しが 44.1kHz・32bit 浮動小数・ピーク +0.2dB だったので、Linux 側で -1.5dB 下げて 48kHz・24bit にした(2026-11-17) |
