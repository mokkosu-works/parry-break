# 通常尺の撮影用ビルドと録画

## ミツバ・1.6.0 の準備（この環境）

`python3 promo/capture/build_mitsuba.py` はタグ `v1.6.0` の `app/` を別の一時フォルダへ展開し、撮影用の `.promo`・広告オフ・出来事ログを設定して、JUST狙い版と下手版の release APK（ARM64）を作る。リポジトリの `app/` は変更しない。既存の出力は上書きしない。

- `apk/promo_v1.6.0_mitsuba_just_events_arm64.apk`
- `apk/promo_v1.6.0_mitsuba_sloppy_events_arm64.apk`
- `apk/mitsuba-v160-build.json`：元のコミット・作業フォルダ・ビルド引数・APKのSHA256。

どちらも `PROMO_AUTOPLAY=true` と `PROMO_EVENT_LOG=true`。アイテム取得は `item_taken` に種類・パリィ取得か・判定・得点を記録する。この環境のツール設定は `source ~/.config/parry-break/env.sh` で読み込める。

ログ付き撮影では、ステージを指定できる（省略時は従来どおり1-1）。1-1・1-2・1-4・1-7・1-8・2-1だけを許可し、ボスの面は選べない（1-7・1-8 は 2026-11-18 にワカナの回のために足した。2 行目のタイルで、位置は 1.5.1 の画面から計算した値なので、撮影の日に短いテイクで確かめる）。`--difficulty easy|normal|hard` で、ステージ選択の右上の難易度を選んでから始められる（設定に残るので、撮り終えたら normal に戻す）。テイク名もステージと腕前を含めて区別する。4人の通常尺の撮影は [`longform-4chars-shotlist-v01.md`](longform-4chars-shotlist-v01.md)。

```sh
bash promo/capture/capture_long.sh stage mitsuba-s11-just-01 30 --stage 1-1
bash promo/capture/capture_long.sh stage mitsuba-s12-just-01 90 --stage 1-2
bash promo/capture/capture_long.sh stage mitsuba-s14-just-01 90 --stage 1-4
bash promo/capture/capture_long.sh stage mitsuba-s21-just-01 120 --stage 2-1
```

端末上での1.6.0の座標・音声・ログ取得は、最初の短い1-1で確認する。デバッグモードの有効化は設定画面右上のVERを3回タップする。レベル・今日のお題用の撮影はデバッグモードを切る。撮影用アプリのデータは自動では消さない。

以下は以前の1.5.1試作の記録。

通常尺の出来事ログは、撮影用アプリ `com.watsuwo.parrybreak.promo` だけで使う。ストア版と別に入れる。リポジトリの `app/` には変更を当てない。

**音声の注意(2026-11-17)**: 最初の `long-endless-akane-pilot01` は別アプリの音声混入が疑われるため不採用。`playback` はゲームだけに限定した録音ではない。現在の道具は開始前・録画開始直後・録画中1秒ごとに再生元のUIDを調べ、ゲーム以外の再生を検知したら失敗として止める。画面の消灯時も止める。詳細は `../design/audio-source-check-20261117.md`。

## 今回のAPK

- 作業フォルダ：`/tmp/claude-1000/-home-shogo-honda-parry-break/fcdb5ffe-65e3-4805-8ac3-aba33324c2c6/scratchpad/app-v151/`
- 元のゲームは1.5.1。以前の撮影用に準備された `.promo` の識別子・広告オフ・このPCのFlutter版の指定を引き継いだ(`../design/shorts-modes.md` を参照)。
- `promo-build.patch` はその準備済み1.5.1の `app/lib/game/game_controller.dart` に追加した出来事ログの差分。`_dispatch` から全ての出来事をJSONで記録する。
- ログが出るのは `PROMO_AUTOPLAY=true` **かつ** `PROMO_EVENT_LOG=true` のときだけ。
- 保存したAPK：`apk/promo_just_v1.5.1_events.apk`(git外)。既存の `promo_just_v1.5.1_side.apk` は上書きしていない。
- 実機の撮影用アプリはログ付きのAPKへ更新済み。ストア版は操作していない。

準備済みの新しい1.5.1作業フォルダに、リポジトリの直下相当の位置から次を当てる。今回の作業フォルダには既に適用済みなので、二重に当てない。

```sh
patch --dry-run -p1 -i /home/shogo-honda/parry-break/promo/capture/promo-build.patch
patch -p1 -i /home/shogo-honda/parry-break/promo/capture/promo-build.patch
cd app
flutter build apk --release --no-pub \
  --dart-define=PROMO_AUTOPLAY=true --dart-define=PROMO_EVENT_LOG=true \
  --dart-define=PROMO_SIGMA=0.006 --dart-define=PROMO_SPEED=1500 \
  --dart-define=PROMO_BIAS=0 --dart-define=PROMO_LAG_COMP=true
```

## 録画

端末をUSBで1台つなぎ、ロックを解除し、USBデバッグを許可する。解像度は2400×1080の横画面。撮影用アプリがタイトル画面へ起動できる状態にする。端末でPlayプロテクトなどの確認が必要なら本人に対応してもらう。

```sh
bash promo/capture/capture_long.sh endless akane-pilot01 100
```

テイクは未使用の名前にする。`raw/long-<モード>-<テイク>/`(git外)へ次を残す。

| ファイル | 中身 |
|---|---|
| `capture.mp4` | scrcpyの映像とゲーム音 |
| `logcat.txt` | 撮影用アプリのログ。ほかのアプリのPIDは対象にしない |
| `events-raw.jsonl` | 出来事JSON。session・連番・実時刻・時計・ラウンド・スコアと、重要な出来事の詳細 |
| `capture.json` | 成否・停止理由・端末・録画の形式など。プロセス起動とタップの時刻は参考用で、映像への時刻合わせには使わない |
| `scrcpy.log` | 録画の診断ログ。失敗しても素材とログを削除しない |

出来事ログが15秒以内に来ない場合、録画かログのプロセスが終了した場合、録画に音声がない場合は失敗として止まる。アプリの識別子は撮影用だけを許可する。完了・失敗時に起動した録画とログのプロセスを終了する。

エンドレスでは、R9のクリアかR10の開始を検知すると録画を止める。R10開始での停止は通信・録画の遅れを含むため、raw映像にR10が少し入る可能性がある。編集側でもR10の前に使用範囲を制限し、最後のコマを確認する。今回の100秒テイクはR8までで、ボスには進んでいない。

`daily`・`practice`・`stage` の操作も既存の `capture_mode.sh` を土台に持つが、この1.5.1試作でログ付き録画を実機で確認したのはエンドレスのみ。当時のステージの撮影先は1-1。

映像と出来事の時刻合わせ、台本作り、書き出しは `../longform/README.md` を参照。
