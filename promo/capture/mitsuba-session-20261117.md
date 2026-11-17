# ミツバ通常尺 撮影進捗 (2026-11-17)

撮影方針: [`../design/longform-mitsuba-outline-v01.md`](../design/longform-mitsuba-outline-v01.md)。通常尺は約4分8秒。映像と出来事ログを照合してから台詞・章の時刻を決める。撮影素材は `raw/` (git管理外) にある。

## 撮影済み

| 内容 | テイク | 状態・ログ |
|---|---|---|
| 1-1 JUST の試し撮り | `long-stage-mitsuba-s11-just-check01` | `recorded_unaligned`。音声・画面形式・ログ取得を確認。短い導入とクリアまでを含む |
| 1-1 下手版 | `long-stage-mitsuba-s11-sloppy-01` | `recorded_unaligned`。MISS 7 回を記録 |
| 1-2 白ブロック・崩落 | `long-stage-mitsuba-s12-just-02` | `recorded_unaligned`。`keystone` 2 回、`collapse` 2 回 |
| 1-4 砲台弾 | `long-stage-mitsuba-s14-just-01` | `recorded_unaligned`。`BulletFired` 7 回 |
| 2-1 FEVER・アイテム | `long-stage-mitsuba-s21-just-01`, `-02`, `-04`, `-05` | すべて `recorded_unaligned`。**`-05` でブラストをパリィ取得 (`parried: true`, JUST, +8000)**、FEVER 1 回。`-01`/`-02` は `parried: false`、`-04` はアイテム取得なし |
| 結果ランク画面 | `long-stage-mitsuba-s21-just-05` の末尾 | 2-1 クリアの結果画面 (ランク B, 158,800) が十数秒映る |
| 06 モード選択画面 | `mtitle_mitsuba-01.mp4` | 16 秒。タイトルでメニューのカーソルを上下 (capture_mode.sh。開始前に他アプリの再生なしを確認) |
| 06 EASY | `mtitle_mitsuba-easy-01.mp4` | 25 秒。NORMAL→EASY に切り替え、エンドレス開始。ROUND 1 に「はじめの3回は防壁つき」と緑の防壁が映る。他アプリの再生なしを確認 |
| 06 エンドレス | `long-endless-mitsuba-mode-endless-02` | `recorded_unaligned`, 30 秒。NORMAL。ROUND 1 の防壁つきが映る |
| 06 デイリー | `long-daily-mitsuba-mode-daily-02` | `recorded_unaligned`, 30 秒 |
| 06 練習 | `long-practice-mitsuba-mode-practice-02` | `recorded_unaligned`, 30 秒 |
| 06 ステージ | 1-1 のテイクを流用 | 新規撮影なし |
| タイトル・今日のお題・設定画面 | `mitsuba-ui-01`, `mitsuba-ui-colors-01` | `recorded`。色画面を含む。結果ランク画面の専用テイクは未確認 |

`long-*-mitsuba-mode-*-01` は端末が WSL から外れていた失敗テイク (`failed`)。`long-stage-mitsuba-s21-just-03` はデバッグモードが切れていて 2-1 がロックされていた失敗テイク (`failed`)。`long-stage-mitsuba-s12-just-01` は誤ったステージ選択の失敗テイク (`failed`)。素材とログは残してあるが、編集には使わない。

## 残作業

- 撮影素材はサーバーへ転送済み。切り出しは別セッションで行う。置き場所とテイクの使い道は [`mitsuba-raw-transfer-20261117.md`](mitsuba-raw-transfer-20261117.md)。

- 時刻合わせは済み (下の「時刻合わせ」)。次は、使う区間と台詞を決める。

- 撮影以外の制作素材 (ミツバ全身口パク、章見出し、BGM のたたき台) は別の環境で作成済み (`characters/sheets/mitsuba/`、`assets/text/longform/mitsuba-*-v01.png`、BGM の MIDI)。

## 時刻合わせ (2026-11-17)

ログ付きの 11 テイクを `promo/longform/align_events.py` で換算した。結果は各テイクの `events.json` (git 管理外、`raw/` の中)。`capture.json` の状態は `recorded_unaligned` のまま (道具が書き換えないため)。

- 基準: 最初の `countdown_finished` を、映像で READY が消えて TAP が出る最初のコマに合わせた。コマの判定は画素の色で行った。
- 時刻の読み方の注意: ffmpeg でコマを生データとして取り出すと、既定では一定のコマ数に詰め直されて時刻がずれる (同じ映像でも 0.3 秒以上変わった)。`-copyts -fps_mode passthrough` で元の時刻のまま読む。書き出しの道具はこの影響を受けない。
- 検証: エンドレスの R2、デイリーの 2・3 回目の開始が、予測と 1 コマ (0.01〜0.02 秒) 以内で一致した。時間が経ってもずれは広がらない。本命の `s21-just-05` は、FEVER・アイテムのパリィ取得・最後の 1 打・STAGE CLEAR の前後のコマを目で見て、ログどおりであることを確かめた。
- 転送記録にあった「映像では約 7 秒後ろ」という見込みは外れていた。実際は、ログより約 10.3 秒後ろ。

| テイク | 基準 (seq → 映像の秒) | 主な出来事の映像の秒 | 備考 |
|---|---|---|---|
| `s11-just-check01` | 2 → 9.251 | 最初のパリィ 11.45、FEVER 19.27、STAGE CLEAR 29.19 | |
| `s11-sloppy-01` | 2 → 10.183 | MISS 24.35 / 26.55 / 38.14 / 47.47 / 49.10 / 50.61 / 52.26 | seq 128 が欠けているので、127 まで (映像 52.33 秒まで) に限定。最後の FEVER とクリアは範囲外 |
| `s12-just-02` | 2 → 10.186 | 白ブロック・崩落 13.58 / 19.43、STAGE CLEAR 22.46 | |
| `s14-just-01` | 2 → 10.328 | 砲台弾 13.36〜22.47 (7 回)、STAGE CLEAR 28.56 | |
| **`s21-just-05`** | 2 → 11.306 | FEVER 20.54、ブラストのパリィ取得 (JUST, +8000) 22.32、ラウンドクリア 30.46、STAGE CLEAR 33.27 | 本命 |
| `s21-just-01` / `-02` | 2 → 11.472 / 11.607 | | 予備 |
| `s21-just-04` | 2 → 11.092 | | 予備。TAP の文字が別の位置なので、READY が消えたコマで判定 |
| `endless-02` / `daily-02` / `practice-02` | 2 → 4.151 / 2 → 4.092 / 1 → 4.301 | FEVER はエンドレス 16.52、デイリー 16.55 | |

`mtitle_*`・`mitsuba-ui-*` はログがないので、時刻合わせの対象外。

## 作業状態

- ブランチ: `feature/promo-video-tools`。
- 撮影用 `.promo` APK は v1.6.0 の JUST 版・下手版を作成済み。ストア版は対象外。アプリデータは消さない。
- ミツバ通常尺の撮影は完了 (2026-11-17)。デバッグモード中のエンドレスは記録されないため、データを消さずに防壁が映った。
- 撮影ツールの変更はコミット済み (`6b04cac`)。
- 端末が adb から見えなくなったら、Windows 側で `usbipd attach --wsl --busid 2-6` (moto g66j) で付け直す。
- 端末の `.promo` は JUST 版 (sha256 `32933a7f…`)。デバッグモードは ON、難易度は NORMAL に戻してある。レベル・今日のお題の画面を撮るときは切る (設定の VER を 3 回タップ。ON のときだけ設定に「その他」タブが出る)。
- 現在、録画・ビルドなどの処理は停止中。再開時は接続状態とインストール済み `.promo` の版を確認してから進める。
