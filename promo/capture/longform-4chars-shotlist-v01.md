# 4人の通常尺の撮影リスト v01(アカネ・シズク・モモカ・ワカナ)

2026-11-18 に、端末なしで準備した(撮影はまだしていない)。何を撮るかの元は、4人の絵コンテ `../design/longform-<名前>-storyboard-v01.md` の「撮るもの」と、コマの表の「撮影のメモ」。撮ったら、絵コンテのコマの指定 `../longform/storyboards/<名前>-v01.json` の [仮の映像] を差し替える。

端末の準備(解像度 2400×1080・横向き・ロック解除・USB デバッグ・ほかのアプリの音を止める)と道具の使い方は [`README.md`](README.md)。

## まず確かめること

- **どの PC で撮るか。** 撮影用アプリ(1.6.0 の JUST 版・下手版)は、前回ミツバの回を撮った PC にある(`apk/promo_v1.6.0_mitsuba_{just,sloppy}_events_arm64.apk`)。この PC には APK がない。別の PC で撮るなら、このブランチ(`feature/promo-video-tools`)を pull してから撮る(1-7・1-8 と `--difficulty` は 2026-11-18 に足した)。
- 撮った素材は、前回と同じく SHA256 を残してサーバーへ送る(`mitsuba-raw-transfer-20261117.md` と同じやり方)。

## 撮らなくてよくなったもの(撮影済みの素材で足りた)

| 回 | コマ | 使う素材 |
|---|---|---|
| アカネ | #17 EASY の切り替え・はじめの防壁 | `mtitle_mitsuba-easy-01.mp4`(1.6.0。4〜6 秒に EASY、8 秒に「はじめの3回は防壁つき」) |
| モモカ | #3 タイトルの DAILY の NEW | `mtitle_mitsuba-easy-01.mp4` の最初 |
| シズク | #9 パドルの上の EARLY / LATE | `long-stage-mitsuba-s11-sloppy-01`(12.5 秒 LATE 26MS、29.0 秒 EARLY 23MS)。練習場ではないので、下の B で撮れたら差し替える |

アカネの回は、新しく撮るものがない。

## 撮影の日より前から: モモカの連続日数(STREAK)

タイトルの DAILY の横の `STREAK n` は、デイリーを**続けた日に遊ばないと**出ない(1 日空くと 1 に戻る)。撮影の日の 2〜3 日前から、撮影用アプリで毎日 1 回デイリーを遊ぶ。

- **デバッグモードを切って**遊ぶ(デバッグモードのプレイは記録に残らない。`design.md` 9.8)。デイリーは鍵がないので、デバッグモードは要らない。
- 日付は UTC で数えるので、日本では毎朝 9 時に次の日になる。9 時をまたいでから遊ぶ。
- せっかく遊ぶので、毎回ログ付きで録画する(下の D の 1 本目と同じコマンド。テイク名の日付を変える)。

## 撮影の日の順番

付け替えを減らすため、アプリと設定ごとにまとめる。テイク名はまだ使っていない名前にする(道具は既存のテイクを上書きせずに止まる)。

### A. JUST 版、デバッグモード**あり**(ワカナ)

1-7・1-8 は鍵がかかっているので、設定画面右上の VER を 3 回タップしてデバッグモードに入る。

| # | 回・コマ | コマンド | 映ればよいもの |
|---|---|---|---|
| A1 | (確認用) | `bash promo/capture/capture_long.sh stage wakana-s17-just-check01 20 --stage 1-7` | **最初に短く撮って、1-7 が選ばれることを確かめる。** 1-7 と 1-8 は 2 行目のタイルで、位置は 1.5.1 の画面から計算した値。違うステージが始まったら止めて、座標を直す |
| A2 | ワカナ #7 | `bash promo/capture/capture_long.sh stage wakana-s17-just-01 90 --stage 1-7` | 1-7「スコアラッシュ」(目標が点数)。スコアが伸びてクリアするまで |
| A3 | ワカナ #7(予備) | `bash promo/capture/capture_long.sh stage wakana-s18-just-01 90 --stage 1-8` | 1-8「防衛線を死守せよ」(40 秒耐える)。耐えてクリアするまで |
| A4 | ワカナ #15 | `bash promo/capture/capture_long.sh stage wakana-s14-hard-01 90 --stage 1-4 --difficulty hard` | HARD の 1-4。砲台の弾が 3 方向に出て、まとめて打ち返す場面。**難易度の切り替えの位置(右上)も 1.5.1 の画面から測った値**なので、始まった画面の右上が HARD になっているかを見る |
| A5 | (戻す) | `bash promo/capture/capture_long.sh stage wakana-s11-normal-reset 20 --difficulty normal` | 難易度は設定に残るので、NORMAL に戻す(手で戻してもよい) |

撮り終えたら、デバッグモードを切る(VER を 3 回)。

### B. 下手版(シズク)

アプリを下手版に入れ替える(`adb install -r apk/promo_v1.6.0_mitsuba_sloppy_events_arm64.apk`)。

| # | 回・コマ | コマンド | 映ればよいもの |
|---|---|---|---|
| B1 | シズク #4・#9 | `bash promo/capture/capture_long.sh practice shizuku-practice-sloppy-01 60` | 練習場で、ボールを落として 1 秒後にパドルの上から出直す場面(#4)と、PERFECT・GOOD のときにパドルの上に EARLY / LATE が出る場面(#9)。左の欄の MISS の数も増える |

撮り終えたら、JUST 版に戻す。

### C. 本人が手で操作する画面(シズク)

道具はタップを自動でしないので、scrcpy で録画しながら、本人が端末で操作する。前回の `mitsuba-ui-01` と同じやり方。ほかのアプリの音が入っていないことは、撮る前に `adb shell dumpsys audio` で確かめる(`capture_long.py` の `check_audio_owner` と同じ考え方)。

```sh
scrcpy --no-playback --no-control --audio-source=playback --video-bit-rate=16M --max-fps=60 \
  --record=promo/capture/raw/shizuku-practice-menu-01.mp4 --record-format=mp4
```

| # | 回・コマ | 操作 | 映ればよいもの |
|---|---|---|---|
| C1 | シズク #13・#14 | 練習場 → 一時停止 → 速さを LV1 → LV3 → FEVER に切り替える → 再開して FEVER の速さで少し遊ぶ | ポーズの画面の速さの切り替えと、切り替えると左の欄の判定が消えるところ |
| C2 | シズク #16 | 練習場 → 一時停止 → 敵弾の打ち返しの練習に切り替える → 再開 | ボールが出ず、1.4 秒ごとに敵弾が落ちてきて打ち返すところ。自動プレイが弾を返すかは撮って確かめる |

### D. デバッグモード**なし**(モモカ)

デイリーは記録に残る遊び方で撮る(結果画面の TODAY BEST・連続日数が出るように)。上の「撮影の日より前から」の続き。

| # | 回・コマ | コマンド | 映ればよいもの |
|---|---|---|---|
| D1 | モモカ #9・#15 | `bash promo/capture/capture_long.sh daily momoka-daily-<日付>-01 300` | 5 ラウンドを乗り切って **DAILY CLEAR** の画面と、続く結果画面(今回のスコア・TODAY BEST・連続日数)。途中でミスしたら、その日の分としてもう 1 回撮る |
| D2 | モモカ #16 | `bash promo/capture/capture_mode.sh title momoka-streak-01` | タイトルの DAILY の横に `STREAK n`(n が 2 以上)。STREAK を何日か積んでから撮る |

## 撮ったあと

1. `sha256sum` を残して、サーバーへ送る。
2. ログ付きのテイクは、`../longform/align_events.py` で映像と出来事の時刻を合わせる(`../design/longform.md` 6章)。
3. 絵コンテのコマの指定の [仮の映像] を差し替え、`python3 promo/longform/storyboard.py <名前> --version v02` で一覧を作り直す(v01 は残す)。
