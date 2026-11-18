# アカネの通常尺の BGM: デスクトップアプリのセッションへの引き継ぎ v01

2026-11-18、WSL の Claude Code(CLI)のセッションから。**この PC の Windows の Claude デスクトップアプリのセッションが、最初に読む指示書。** 2 つのセッションは直接メッセージを送り合えないので、このファイルでやり取りする。終わったら、末尾の「結果」に書いてほしい(CLI のセッションがそれを読んで続きを進める)。

作り方と決まりの全体は [`bgm.md`](bgm.md)。本人(リポジトリの持ち主)への説明・質問・報告は、日本語の平易な文で。

## 状況

- 作るもの: アカネの通常尺(エンドレス紹介、約 3 分 45 秒)の BGM。本編はまだ書き出していない。**先に BGM を作る**(本人の希望)。
- リポジトリは **WSL のもの**(Windows 側に複製はない)。Windows からは `\\wsl.localhost\Ubuntu\home\ilive\test\parry-break\`。git の pull・push は要らない。
- DAW は Sonar。プロジェクトは `D:\Cakewalk Projects\`(WSL からは `/mnt/d/Cakewalk Projects/`)。ミツバの BGM は `D:\Cakewalk Projects\mitsuba-basics-bgm-v01\`。

## 使うもの

| もの | 場所(リポジトリの中) | 中身 |
|---|---|---|
| MIDI のたたき台 | `promo/assets/bgm/midi/akane-endless-bgm-v01.mid` | テンポ 112、110 小節(約 3 分 56 秒)。章のマーカー入り。音色は入っていない(トラック名に音の種類)。ドラムは GM 配置・チャンネル 10 |
| 絵コンテの仮映像 | `promo/build/out/akane-storyboard-guide-v01/guide.mp4` | 絵コンテの静止画を時刻どおりに並べた 3:45 の動画。左上にコマの番号と時刻。音は下の `game.wav` と同じ |
| ゲーム音 | 同じフォルダの `game.wav` | 本編のコマのあいだだけ、録画のゲーム音(本編と同じ音量)。ゲームの BGM とぶつからないか聞く参考トラック。**書き出しには入れない** |
| マーカー表 | 同じフォルダの `cues.md`・`cues.csv` | コマごとの時刻・章・出来事(JUST・COLLAPSE・FEVER 開始)と、MIDI の章のマーカーの小節:拍 |
| 絵コンテ | `promo/design/longform-akane-storyboard-v01.md`、静止画は `promo/design/checks/akane-storyboard-v01.jpg` | 何を見せる回か |

`promo/build/out/` は git の対象外なので、`\\wsl.localhost\...` から直接開く。

MIDI の章のマーカーは、絵コンテの章の時刻とそろっている(0:12 / 0:58 / 1:53 / 2:58 / エンディング 3:25)。盛り上げどころは、まとめて崩れる 1:58 とフィーバー開始 2:25(`cues.md`)。

**時刻は絵コンテの目安。** 本編ができると少しずれる。そのときは CLI のセッションが本編から見本パック(`bgm_kit.py`)を作るので、区切りを合わせ直す。いまは章の大まかな流れに合っていればよい。

## やってほしいこと

1. 本人と一緒に、Sonar で新しいプロジェクト `D:\Cakewalk Projects\akane-endless-bgm-v01\` を作り、MIDI を読み込む。`guide.mp4` を動画トラック、`game.wav` を参考トラックに、どちらも 0 秒に置く。必要なら `cues.md` のマーカーを打つ。
2. 音源の割り当てと仕上げは本人が行う。作るときの決まりは `bgm.md` の 2 章(ゲームの BGM が鳴っているので、リズムとパッド中心の薄めの曲。和音と飾りは D・E・G・A の 4 音から)。
3. 本人が WAV を書き出したら、決まり(`bgm.md` の 3 章: 48kHz・24bit・ステレオ、ピーク -1 dBFS 以下、-16 LUFS 前後、頭に無音なし)に合うかを確かめる。長さは **225 秒以上**。
   - 確かめる道具は `promo/longform/check_bgm.py`。WSL の Python と ffmpeg を使うなら:
     ```
     wsl -d Ubuntu -- bash -lc "cd ~/test/parry-break && python3 promo/longform/check_bgm.py '/mnt/d/Cakewalk Projects/akane-endless-bgm-v01/Audio Export/<書き出した>.wav' --length 225"
     ```
   - 合格したら、同じコマンドに `--to-flac promo/assets/bgm/akane-endless-bgm-v01.flac` を付けて FLAC にする(既存は上書きしない)。
   - 合わないとき(ミツバのときは 44.1kHz・32bit 浮動小数・ピーク +0.2dB だった)は、まず Sonar の書き出しの設定を直して書き出し直す。直せないときは、本人に聞いてから変換で合わせる(ミツバは -1.5dB 下げて 48kHz・24bit にした)。何をしたかを「結果」に書く。
4. `promo/assets/bgm/README.md` の 2 つめの表に 1 行足す(ファイル・どの本編用か・テンポ・DAW のプロジェクトの場所・書き出しの設定と、変換したならその内容)。

## やらないこと

- **push**(本人に聞いてから)。コミットも、本人に頼まれたときだけ。
- 動画の書き出し・台本・声(CLI のセッションが行う)。
- MIDI の作り直し(要るときは「結果」に理由を書く)。

## 結果(デスクトップアプリのセッションが書く)

- 日付: 2026-11-18
- できた FLAC: `promo/assets/bgm/akane-endless-bgm-v01.flac`(`promo/assets/bgm/README.md` の表にも 1 行足した)
- テンポ・長さ・ピーク・音量(`check_bgm.py` の出力): テンポ 112、長さ 235.580 秒(本編 225.0 秒)、ピーク -2.3 dBFS、-20.8 LUFS、頭の無音 0.00 秒。「決まりに合っています」
- 書き出しの設定と、変換したならその内容: Sonar の書き出しで Wave・ステレオ・48000Hz・24bit・プロジェクト全体。変換はしていない。マスター 0dB ではピーク 0.0dBFS、-1.5dB でもまだ 0.0dBFS(鋭い音が頭打ち)だったので、マスターを -4dB にして書き出し直した。`game.wav` のトラックはミュートして書き出した。
- DAW のプロジェクトの場所: `D:\Cakewalk Projects\akane-endless-bgm-v01\akane-endless-bgm-v01.cwp`(書き出しは `Audio Export\`)。音源は Sonar 付属の BandLab 音源: Drums=Dry、Bass=Soft Sine Bass、Pad=Warm Pad、Keys=Mellow EP、Bell=Glockenspiel。マーカー 16 個(章 6・できごと 9・動画の終わり)を `cues.md` に合わせて打ってある。
- 気になった点・CLI のセッションへの申し送り:
  - MIDI を読み込んだだけだと、Sonar のテンポが 120 のままで MIDI のテンポ(112)が入らなかった。手で 112 に直した。次の MIDI でも要確認。
  - プロジェクト自体は 44.1kHz・16bit で作られている(書き出しで 48kHz・24bit にしている)。
  - 曲の音量は -20.8 LUFS で、目安の -16 より小さめ(許容範囲 -22〜-10 には入る)。混ぜるときの `volume` で調整してほしい。
  - ピークはマスター 0dB で 0 を超えていた。鋭い音(ドラムか)が原因と思われるが、どのトラックかは調べていない。
  - 本人は「いいと思う」と言ったが、デスクトップアプリのセッション(Claude)には音が聞こえないので、音量バランスを細かく聴いて決めたわけではない。混ぜたあとの聞こえ方で、作り直すかを決めてほしい。
  - 時刻は絵コンテの目安。本編ができたら見本パックで区切りを合わせ直す必要がある。
