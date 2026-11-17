# ミツバ通常尺 撮影素材の転送記録 (2026-11-17)

撮影は完了。使う区間の切り出しと時刻合わせは別のセッションで行う。そのセッションは、この記録とサーバー上の素材を起点にする。撮影の経緯は [`mitsuba-session-20261117.md`](mitsuba-session-20261117.md)、章立てと台詞の候補は [`../design/longform-mitsuba-outline-v01.md`](../design/longform-mitsuba-outline-v01.md) を参照。

## 置き場所

- サーバー: `mokkosu-works-server` (Tailscale `100.76.28.77`)。ユーザーは `shogohonda`。Tailscale SSH で入れる (`ssh shogohonda@100.76.28.77`)。
- パス: `~/parry-break-promo/mitsuba-20261117/raw/`。手元の `promo/capture/raw/` (git 管理外) と同じ構成で、79 ファイル・755MB。
- 照合: 全ファイルの SHA256 を [`mitsuba-raw-20261117.sha256`](mitsuba-raw-20261117.sha256) に残した (サーバーには `raw/SHA256SUMS` として同じものがある)。転送後にサーバー上で `sha256sum -c` を実行し、全件一致を確認した。
- 手元の `promo/capture/raw/` は消していない。

## テイク一覧

動画はすべて 2400x1080 の横画面で、ゲームの音声入り。`long-*` のフォルダには `capture.mp4` (映像)、`events-raw.jsonl` (出来事ログ)、`capture.json` (状態・端末・音声確認)、`logcat.txt`、`scrcpy.log` がある。状態が `recorded_unaligned` のテイクは、映像と出来事の時刻をまだ照合していない。

| 章 | 内容 | テイク | 長さ | 備考 |
|---|---|---|---|---|
| 01–03 | 1-1 JUST (基本操作) | `long-stage-mitsuba-s11-just-check01` | 38 秒 | 短い導入からクリアまで |
| 02 | 1-1 下手版 (空振り) | `long-stage-mitsuba-s11-sloppy-01` | 69 秒 | MISS 7 回 |
| 03 | 1-2 白ブロック・崩落 | `long-stage-mitsuba-s12-just-02` | 64 秒 | `keystone` 2 回、`collapse` 2 回 |
| 03 | 1-4 砲台弾 | `long-stage-mitsuba-s14-just-01` | 74 秒 | `BulletFired` 7 回 |
| 04–05, 07 | **2-1 FEVER・アイテムのパリィ取得・結果ランク** | `long-stage-mitsuba-s21-just-05` | 130 秒 | 本命。ログ上は FEVER 開始が 10.3 秒、ブラストのパリィ取得 (JUST, +8000) が 12.0 秒、クリアが 23.0 秒。映像では、それぞれ約 7 秒後ろにずれる見込み (録画開始からゲーム開始までの差による概算で、未照合)。末尾の十数秒に結果画面 (ランク B, 158,800) が映る |
| 04 | 2-1 予備 | `long-stage-mitsuba-s21-just-01`, `-02`, `-04` | 110 / 66 / 130 秒 | `-01`/`-02` はアイテムをパドルで取得 (`parried: false`)。`-04` はアイテム取得なし |
| 06 | モード選択画面 | `mtitle_mitsuba-01.mp4` | 15 秒 | タイトルでメニューのカーソルが上下に動く |
| 06 | EASY とはじめの防壁 | `mtitle_mitsuba-easy-01.mp4` | 25 秒 | NORMAL から EASY に切り替えて、エンドレスを始める。ROUND 1 に「はじめの3回は防壁つき」と緑の防壁が映る |
| 06 | エンドレス | `long-endless-mitsuba-mode-endless-02` | 33 秒 | NORMAL。ROUND 1 の防壁つきが映る |
| 06 | デイリー | `long-daily-mitsuba-mode-daily-02` | 33 秒 | |
| 06 | 練習 | `long-practice-mitsuba-mode-practice-02` | 33 秒 | |
| 06 | ステージ | 上の 1-1 のテイクを流用 | | |
| 07 | 今日のお題・タイトルの LV・設定 | `mitsuba-ui-01` | 39 秒 | 状態は `recorded`。結果画面は入っていない |
| 07 | パドルの色など | `mitsuba-ui-colors-01` | 40 秒 | 状態は `recorded` |

### 使わないテイク (状態は `failed`)

| テイク | 理由 |
|---|---|
| `long-stage-mitsuba-s12-just-01` | 誤ったステージを選んだ |
| `long-stage-mitsuba-s21-just-03` | デバッグモードが切れていて、2-1 がロックされていた |
| `long-{endless,daily,practice}-mitsuba-mode-*-01` | 端末が WSL から外れていて、録画が始まらなかった |

## 撮影の条件

- 撮影用アプリは `com.watsuwo.parrybreak.promo` の v1.6.0 で、広告はオフ。作り方は `build_mitsuba.py` と `apk/mitsuba-v160-build.json` (git 管理外) を参照。下手版のテイクは `sloppy` の APK で撮った。この記録の作成時に `just` の APK で撮ったことを確かめたのは、`s21-just-04`・`-05` とモードのテイク (`*-02`、`mtitle_*`)。それより前のテイクの APK は、`mitsuba-session-20261117.md` に記録がない。
- 2-1 とモードのテイクはデバッグモード ON で撮った。そのため遊んだ結果は記録されず、エンドレスのはじめの防壁がデータを消さずに映った。
- `long-*` のテイクは、録画中 1 秒ごとに音声の再生元を確かめ、ゲーム以外の音が混ざっていないことを確認済み。`mtitle_*` は録画の前後に、ほかのアプリが再生していないことを確かめた。
