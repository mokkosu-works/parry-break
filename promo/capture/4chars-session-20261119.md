# 4人の通常尺の撮影メモ(2026-11-18〜19、この PC の WSL)

撮るものは [`longform-4chars-shotlist-v01.md`](longform-4chars-shotlist-v01.md)。端末は moto g66j 5G(Android 16)、usbipd-win で WSL につないだ。撮影用アプリは、この PC で `build_mitsuba.py` と `build_streak.py` で作った 1.6.0。素材の SHA256 は `4chars-raw-20261119.sha256`(35 件、約 567MB)。2026-11-19 にサーバー `mokkosu-works-server`(192.168.1.149)の `~/parry-break-promo/4chars-20261119/raw/` へ送り、サーバー上で `sha256sum -c SHA256SUMS` が全件一致した。手元の `raw/` は消していない。時刻合わせ(`align_events.py`)はまだ。

| テイク | 撮影リスト | アプリ | 中身・確かめたこと |
|---|---|---|---|
| `long-stage-wakana-s17-just-check01` | A1 | `.promo` JUST、デバッグモード | 1-7 が選ばれる確認(20 秒)。ログはすべて `stage:1-7`、目標 120,000 |
| `long-stage-wakana-s17-just-01` | A2 | 同上 | 1-7 スコアラッシュ、クリアまで(90 秒) |
| `long-stage-wakana-s18-just-01` | A3 | 同上 | 1-8 防衛線を死守せよ、クリアまで(90 秒) |
| `long-stage-wakana-s14-hard-01` | A4 | 同上、HARD | 選択画面で HARD を確かめた。20 秒でクリア。弾は 3 回撃たれたが、自動プレイは弾を打ち返さない(「まとめて打ち返す」場面はない) |
| `long-practice-shizuku-practice-sloppy-01` | B1 | `.promo` 下手版 | 練習場 60 秒。PERFECT 2・GOOD 10・JUST 3、miss 4 |
| `shizuku-practice-menu-01/capture.mp4` | C1・C2 | `.promo` JUST | ログなし。adb のタップで操作(時刻は `taps.log`)。一時停止 → SPEED LV3 → FEVER → 再開(判定の欄が LAST 1/20 から数え直し)→ 一時停止 → MODE BULLETS → 再開。**弾の練習では、自動プレイは弾を返せず MISS・HIT が続く**。音は録画中 4 回、再生元が撮影用アプリ(uid 10555)だけであることを確かめた(`audio-check.txt`) |
| `long-daily-momoka-daily-20261119-01` | D1 | `.promostreak`、デバッグモードなし | デイリー 5 ラウンド(R22〜26)を乗り切り DAILY CLEAR。結果に TODAY BEST と「今日の記録として残しました・5日連続プレイ中」 |
| `mtitle_momoka-streak-01.mp4` | D2 | `.promostreak` | タイトルの DAILY の横に `STREAK 5`。ログなし(`capture_mode.sh`)。D1 の直後に撮った(D1 の録画中は再生元を 265 回確かめた) |

- **連続日数は演出**: `.promostreak` は最初の起動で「昨日まで 4 日続けた」記録を入れるアプリ。5 日は実際に遊び続けた日数ではない(本人が了承、2026-11-19)。
- 撮影中に直したこと: この端末はステージ選択のタイルと「次の章」の矢印が、前の値より 114px 右(画面の左に余白)。`capture_long.py` を実測の値に直した。難易度のボタンは前の値で合っていた。
- scrcpy をシェルの裏で動かすと SIGINT が届かず、録画のファイルが閉じない。止めるときは SIGTERM(`capture_mode.sh` は `timeout` で止めるので問題ない)。
- 撮り終えたあと、撮影用アプリ(`.promo`)は JUST 版・NORMAL・デバッグモードなしに戻した。
