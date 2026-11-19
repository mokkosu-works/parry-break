# モモカの通常尺の BGM: デスクトップアプリのセッションへの引き継ぎ v01

2026-11-19、WSL の Claude Code(CLI)のセッションから。**この PC の Windows の Claude デスクトップアプリのセッションが、最初に読む指示書。** 2 つのセッションは直接メッセージを送り合えないので、このファイルでやり取りする。終わったら、末尾の「結果」に書いてほしい(CLI のセッションがそれを読んで続きを進める)。

作り方と決まりの全体は [`bgm.md`](bgm.md)。シズクの回の進め方と結果(Sonar の操作で気づいたこと)は [`bgm-handoff-shizuku-v01.md`](bgm-handoff-shizuku-v01.md) の「結果」。本人(リポジトリの持ち主)への説明・質問・報告は、日本語の平易な文で。

## 状況

- 本編はできた: `promo/build/out/momoka-full-e002/`(**1 分 55 秒**、本人の確認済み)。モモカはデイリーの担当で、明るく、見どころを褒めるキャラ。
- これまでの 3 曲(ミツバ=柔らかいパッド・エレピ・鉄琴、アカネ=ロック、シズク=ローファイ)と似ないように、**モモカは明るく跳ねるダンスポップ寄り**にした: 4 つ打ちのキックと 2・4 拍の手拍子、オクターブを跳ねるシンセベース、拍をずらして刻むプラックの和音、見せ場だけのかわいいリード。
- リポジトリは WSL のもの(`\\wsl.localhost\Ubuntu\home\ilive\test\parry-break\`)。git の pull・push は要らない。DAW は Sonar。

## 使うもの

| もの | 場所(リポジトリの中) | 中身 |
|---|---|---|
| MIDI のたたき台 | `promo/assets/bgm/midi/momoka-daily-bgm-v01.mid` | **テンポ 108**(1 小節 = 約 2.22 秒)、53 小節 = 約 118 秒。マーカー入り。4 トラック: Drums(ダンスポップのキット、GM 配置・チャンネル 10。手拍子 39・オープンハイハット 46・クラッシュ 49 も使う)/ Bass(跳ねるシンセベース)/ Chords(明るいプラックのシンセ)/ Lead(かわいい矩形波か口笛のようなリード。オープニング・03・エンディングだけ) |
| 本編の見本 | `promo/build/out/momoka-full-e002/bgm-kit/guide.mp4` | 本編(BGM なし、声とゲーム音入り)。音だけは `guide-audio.wav`。**書き出しには入れない** |
| マーカー表 | 同じフォルダの `cues.md` | 章の始まりの時刻と小節:拍 |

和音は Dsus2 → Asus4 → Em7sus4 → Gadd9 の響きの繰り返しで、音はすべてゲームの BGM とぶつからない D・E・G・A。音を足すときも、この 4 音から選ぶ。

区切り(小節): オープニング 1〜4 / 01 今日の配置 5〜14(台詞が多いので軽く)/ 02 5ラウンド 15〜25 / 03 見せ場 26〜33(いちばん強く、リードあり)/ 04 記録 34〜43 / エンディング 44〜51(強く、リードあり)/ 最後の和音 52〜53(113.3 秒から。動画は 114.9 秒で終わり、混ぜるときにフェードする)。

## やってほしいこと

1. 本人と一緒に、Sonar の**新規作成の画面で**、名前 `momoka-daily-bgm-v01`・**テンポ 108**・48kHz・24bit を先に決めてプロジェクトを作る(`D:\Cakewalk Projects\momoka-daily-bgm-v01\`)。MIDI を読み込み、テンポが 108 のままかを確かめる(読み込みでテンポが変わることがある。`bgm.md` 1.5 章)。`guide.mp4` を動画トラック(「オーディオデータも読み込む」は外す)、`guide-audio.wav` を参考トラックに、どちらも 0 秒に置く。
2. 音源の割り当てと仕上げは本人が行う。**これまでの曲の音色は使わない**: ミツバ(Warm Pad・Mellow EP・Glockenspiel)、アカネ(Dry・Soft Sine Bass・Rock・Retro Pick Bass・Overdriven Power Chord・Axe Lead Guitar)、シズク(Lofi Hop・Acoustic Bass Legato・Felt Piano・Flute)。明るいポップの音色(ダンス系のキット、シンセベース、プラック、かわいいリード)から選ぶ。強いリミッターはかけない。
3. 本人が WAV を書き出したら、決まり(`bgm.md` の 3 章: 48kHz・24bit・ステレオ、ピーク -1 dBFS 以下、-16 LUFS 前後、頭に無音なし)に合うかを確かめる。長さは **115 秒以上**。ピークが 0 を超えたら音量を下げる。曲の音量は -16 LUFS に近づける。
   ```
   wsl -d Ubuntu -- bash -lc "cd ~/test/parry-break && python3 promo/longform/check_bgm.py '/mnt/d/Cakewalk Projects/momoka-daily-bgm-v01/Audio Export/<書き出した>.wav' --length 114.9"
   ```
   合格したら、同じコマンドに `--to-flac promo/assets/bgm/momoka-daily-bgm-v01.flac` を付けて FLAC にする(既存は上書きしない)。
4. `promo/assets/bgm/README.md` の 2 つめの表に 1 行足す。

シズクの回で分かった注意(詳しくはその「結果」):
- 書き出す前に、トラックビューの選択を解除する(Ctrl+Shift+A)。選択があると書き出し範囲が「タイム選択範囲」になり、中身の無い WAV ができる。範囲は「プロジェクト全体」を選び直す。参考音のトラックはミュートする。
- テンプレートを「No Tracks or Buses」にするとマスターのバスが無いので、音量は音源トラックの音量で合わせる。

## やらないこと

- **push**(本人に聞いてから)。コミットも、本人に頼まれたときだけ。
- 動画の書き出し・台本・声(CLI のセッションが行う)。
- MIDI の作り直し(要るときは「結果」に理由を書く)。
- `.claude/worktrees/` に作業用の複製を作ったら、使い終わったら消してよいかを本人に聞く。

## 結果(デスクトップアプリのセッションが書く)

- 日付: 2026-11-19
- できた FLAC: `promo/assets/bgm/momoka-daily-bgm-v01.flac`(`promo/assets/bgm/README.md` の 2 つめの表にも 1 行足した)
- テンポ・長さ・ピーク・音量(`check_bgm.py` の出力): テンポ 108、長さ 117.639 秒(本編 114.9 秒)、ピーク -1.8 dBFS、-16.1 LUFS、頭の無音 0.00 秒。「決まりに合っています」
- 書き出しの設定と、変換したならその内容: Sonar の書き出しで Wave・ステレオ・48000Hz・24bit(既定が 32 Bit だったので直した)・プロジェクト全体(1:01:000〜53:04:720)。変換はしていない。参考音のトラックはミュートし、選択を解除してから書き出した。リミッターはかけていない。テンプレートは「No Tracks or Buses」なので、音量は音源トラックの音量で合わせた: 1 回目(全部 0dB)は -19.6 LUFS・ピーク -5.4、4 つとも +3.5dB にして合格。
- DAW のプロジェクトの場所と、割り当てた音源: `D:\Cakewalk Projects\momoka-daily-bgm-v01\momoka-daily-bgm-v01.cwp`。音源は Sonar 付属の BandLab 音源で、これまでの曲の音色とは重ならない。Drums=HOT Pop(Drum Kits)、Bass=House Bass(Synth Basses)、Chords=Nova Pluck(Synth Keyboard)、Lead=80s Square Lead(Synth Lead)。トラックは MIDI の 4 つ + 参考音 1 つ(Guide audio (mute on export))+ 音源 4 つ + 動画。MIDI を読み込んだあともテンポは 108.00 のままだった。動画は「オーディオデータも読み込む」を外して読み込んだ(114.87 秒)。
- 気になった点・CLI のセッションへの申し送り:
  - Claude には音が聞こえないので、4 つの音源の音量メーターが動くことと、書き出した WAV の数値しか確かめていない。聞こえ方(ドラムのキットが GM 配置どおりに鳴るか、手拍子やオープンハイハットが出ているか、リードがかわいく聞こえるか)は本人が聞いて決めてほしい。替える候補: ドラム=Pop Rock・Punchy・Nifty、ベース=Party Bass・Plucked Vaporbass、和音=Trance Pluck・Heart Keys、リード=Chip Hat・Retro Lead。
  - 音源を足すと、MIDI トラックの出力先が最初の音源(1-HOT Pop)のままになった(ドラム以外の 3 つ)。トラックを展開して、出力先を 1 つずつ選び直した。
  - この資料と MIDI は git に入っていなかったので、ワークツリーではなくメインの作業場所のファイルを使い、README と結果欄も Bash でメイン側に書いた。
  - マーカーは打っていない(手順に無かったため)。

## 本人の確認(CLI のセッションが書く)

- 2026-11-20: volume 0.19 で混ぜた `momoka-full-e003`(全体 -16.2 LUFS)を本人が聞いた。ハイハットは聞こえないが「あんまり気にならない」ので、このまま採用。
