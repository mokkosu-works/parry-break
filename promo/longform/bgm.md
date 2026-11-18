# 通常尺の BGM を Windows の DAW で作る

通常尺の本編に重ねる BGM は、本人が Windows の DAW で作る。録画のゲーム音(ゲームの BGM と効果音)はそのまま残し、新しい BGM はその下に小さく重ねる。混ぜるのは Linux 側の `render_long.py`。

## 0. この PC での実際のやり方(2026-11-18 に整理。本人が毎回迷うため)

- BGM の作業は、**この PC の Windows の Claude デスクトップアプリ**のセッションが、Sonar と一緒に進める。デスクトップアプリでは、リポジトリに **WSL のほう**(`\\wsl.localhost\Ubuntu\home\ilive\test\parry-break`)を選ぶ。**Windows 側にリポジトリの複製はない**ので、Windows での pull・push は要らない(下の 1 章のコピーや 5 章の push は、Windows に複製があった場合の手順)。
- DAW のプロジェクトと書き出しは `D:\Cakewalk Projects\<曲名>\`。WSL からは `/mnt/d/Cakewalk Projects/` で見えるので、書き出した WAV の確認・FLAC への変換・コミットは、WSL のリポジトリで行う(ミツバの BGM もそうした)。
- WSL の Claude Code(CLI)のセッションとデスクトップアプリのセッションは、**直接メッセージを送り合えない**。CLI のセッションが **引き継ぎの指示書**(`promo/longform/bgm-handoff-<名前>-v<版>.md`)を書き、本人がデスクトップアプリに「これを読んで進めて」と伝える。デスクトップアプリのセッションは、結果を同じファイルの「結果」の節に書く。
- 本編を書き出す前に BGM を作るときは、見本パックの代わりに、絵コンテの仮映像(`python3 promo/longform/storyboard.py <名前> --guide` → `promo/build/out/<名前>-storyboard-guide-v01/` の `guide.mp4`・`game.wav`・`cues.md`)を使う。本編ができたら、下の 1 章の見本パックで合わせ直す。

以下は、もともとの手順(Windows 側に複製があった前提の書き方を含む)。動画の書き出しは Linux 側でやる。

## 1. 見本パックを受け取る(Linux → Windows)

Linux 側で作る:

```sh
python3 promo/longform/bgm_kit.py promo/build/out/akane-endless-pilot-e002 --bpm 120
```

`promo/build/out/akane-endless-pilot-e002/bgm-kit/` ができる。動画と音は git の対象外なので、フォルダごと共有フォルダか USB で Windows にコピーする。`--bpm` は曲のテンポが決まっていれば渡す(目印に小節:拍が付く)。決まっていなければ付けなくてよい。

| ファイル | 中身 | DAW での使い方 |
|---|---|---|
| `guide.mp4` | いまの本編(声とゲーム音入り) | 動画トラックに読み込む。音は消してよい |
| `voice.wav` | 声だけ | 参考トラック。台詞の間を聞くため。書き出しには入れない |
| `game.wav` | 録画のゲーム音だけ(本編と同じ音量) | 参考トラック。ゲームの BGM とぶつからないか聞くため。書き出しには入れない |
| `cues.csv`・`cues.md` | 台詞の始まりと終わり、主な出来事(ジャストパリィ、フィーバー開始、まとめて崩れる、ラウンドの区切り)の時刻 | マーカーを打つ。0 秒が `guide.mp4` の先頭 |

`voice.wav` と `game.wav` は `guide.mp4` と同じ 0 秒から始まる。3 つとも DAW の 0 秒に置く。

## 1.5 MIDI のたたき台(使うときだけ)

ゼロから作らずに、Claude が作った MIDI を Sonar で開いて仕上げてもよい。

```sh
python3 promo/longform/bgm_midi.py mitsuba-basics    # promo/assets/bgm/midi/mitsuba-basics-bgm-v01.mid
```

MIDI は git に入るので、Windows では pull するだけで受け取れる。

- **音源は自分で割り当てる。** Sonar の無料枠には TTS-1 が入っていない前提で、音色の番号は入れていない。トラック名に割り当てる音の種類を書いてある(`Bass (soft synth bass)` など)。ドラムは GM の配置(キック C1=36、スネア D1=38、クラップ 39、クローズのハイハット 42、オープン 46、クラッシュ 49)で、チャンネル 10。
- **ゲームの BGM とぶつかりにくい音だけを使っている。** ゲームの BGM は A マイナー → B マイナー → (フィーバー中) D マイナーと変わり、テンポも 132〜168 で動く。たたき台の和音と飾りは、3 つのキーのどれにも入っている D・E・G・A の 4 音だけで作り、テンポはそこから離してある。音を足すときも、この 4 音から選ぶとぶつかりにくい。
- **マーカーは骨組みの章の目安。** 曲の区切りは 4 小節単位なので、マーカーと少しずれる。本編ができたら見本パックの `cues.md` に合わせて、区切りを動かしたり、小節を足し引きしたりする。
- 曲の長さは動画より少し長めにしてある(余りは混ぜるときに切る)。
- 書き出しの決まり(下の 3)は、たたき台を使っても同じ。
- **Sonar で MIDI を読み込んでも、テンポは入らない**(プロジェクトのテンポが 120 のまま。アカネの回で起きた)。読み込んだら、MIDI のテンポ(`promo/assets/bgm/README.md` の表か、`bgm_midi.py` の `SONGS` の値)に手で直す。
- **マスター 0dB だとピークが 0 を超えやすい**(ドラムの鋭い音)。アカネの回はマスターを -4dB にして書き出し、ピーク -2.3dBFS・-20.8 LUFS になった。

## 2. 作るときの決まり

- **ゲームの BGM が鳴っている**。はっきりしたメロディやキーの強い和音は、ゲームの BGM とぶつかりやすい。リズムとパッド中心の、薄めの曲にする。`game.wav` を鳴らしながら作る。
- **台詞の間は自動で約 7dB 下がる**(声に合わせて BGM を下げる処理が混ぜるときに入る)。それでも、長い説明の台詞の間は音数を減らしておくと聞きやすい。
- 盛り上げどころの目安は、フィーバー開始とまとめて崩れるところ(`cues.md`)。
- 始まりと終わりのフェードは混ぜるときに付ける(入り 0.5 秒、終わり 2 秒)。曲の中にフェードを入れなくてよい。

## 3. 書き出しの決まり

| 項目 | 決まり |
|---|---|
| 形式 | WAV、48kHz、24bit、ステレオ |
| 長さ | 本編と同じか、それより長く(余りは混ぜるときに切る)。本編の長さは `cues.md` の先頭 |
| 始まり | 曲の頭を 0 秒に揃える。頭に無音を入れない |
| ピーク | -1 dBFS 以下 |
| 音量 | -16 LUFS 前後(-22〜-10 に収める)。混ぜるときに小さくするので、曲そのものは普通の音量で作る |
| マスター | 強いリミッターやマキシマイザーはかけない |
| 入れないもの | `voice.wav`・`game.wav`・動画の音 |

## 4. 確かめて置く(Windows の Claude Code に頼む)

最初の 1 回だけ、ffmpeg と Python 3 を入れる(PowerShell):

```powershell
winget install Gyan.FFmpeg
winget install Python.Python.3.12
```

入れたあとに PowerShell を開き直す。そのあと、リポジトリの一番上で次を実行する:

```powershell
python promo/longform/check_bgm.py <書き出した.wav> --length 45
```

長さ・サンプルレート・ピーク・音量・頭の無音を確かめ、決まりから外れていれば直すところを出す。合格したら FLAC にして置く:

```powershell
python promo/longform/check_bgm.py <書き出した.wav> --length 45 --to-flac promo/assets/bgm/akane-endless-bgm-v01.flac
```

- ファイル名は `<名前>-<モード>-bgm-v<版>.flac`。作り直したら版の番号を上げる(既存のファイルは上書きしない)。
- `promo/assets/bgm/README.md` の表に 1 行足す(どの本編用か、テンポ、DAW のプロジェクトの場所)。

## 5. コミットして push

`promo/assets/bgm/` の FLAC と README だけをコミットして push する。DAW のプロジェクトと書き出した WAV は Windows に残す(git に入れない)。

## 6. 混ぜて書き出す(Linux)

pull したあと、台本に `bgm` を足した新しい版を作り、前の出力の声を写して書き出す。声の作り直し(AivisSpeech)は要らない。

```json
"bgm": {
  "file": "promo/assets/bgm/akane-endless-bgm-v01.flac",
  "start": 0,
  "volume": 0.2,
  "fade_in": 0.5,
  "fade_out": 2.0,
  "duck": true
}
```

| 項目 | 意味 |
|---|---|
| `start` | 曲の何秒目から使うか |
| `volume` | BGM の大きさ(0〜1)。0.2 から始めて、聞いて決める |
| `fade_in`・`fade_out` | 入りと終わりのフェードの秒数 |
| `duck` | 台詞の間だけ BGM を下げるか |

```sh
python3 promo/longform/render_long.py promo/longform/projects/akane-endless-pilot-v03.json \
  --out promo/build/out/akane-endless-pilot-e003 \
  --voices-from promo/build/out/akane-endless-pilot-e002
```

`--voices-from` は、台本が `bgm` 以外で前と同じときだけ使える。違うときは止まるので、`--prepare-only` で声を作り直す。音量だけを変えて試すときも、台本と出力先の版を上げる(既存の出力は上書きしない)。
