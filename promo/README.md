# 宣伝動画 (promo)

実機の画面録画から、SNS 向けの縦動画 (9:16、15〜30秒) を作る道具。冒頭 3 秒だけ違う A / B / C の 3 本を、同じ映像から作る。

| 冒頭 | 内容 |
| --- | --- |
| A | 惜しい失敗 |
| B | 見栄えのする場面 |
| C | 結果の瞬間 |

冒頭以外 (本編と最後の 2 秒) は 3 本で同じ。最後の 2 秒に、アプリ名・「ストアで検索」・公式のストアバッジを出す。

## 流れ

1. **撮る**: 撮影用ビルド (自動プレイ入り) を実機に入れて録画する。
   ```sh
   cd app
   flutter build apk --release --dart-define=PROMO_AUTOPLAY=true            # 下手なプレイ (既定)
   flutter build apk --release --dart-define=PROMO_AUTOPLAY=true \
     --dart-define=PROMO_SIGMA=0.006 --dart-define=PROMO_SPEED=1500 \
     --dart-define=PROMO_BIAS=0 --dart-define=PROMO_LAG_COMP=true          # JUST を狙うプレイ
   adb install -r build/app/outputs/flutter-apk/app-release.apk
   ```
   実機でタイトルの `VER` を 3 回タップしてデバッグモードにすると、全ステージを選べる (撮影用ビルドでは、DEBUG の帯は出ない)。
   `promo/capture.sh <ステージ 例 2-7> <ラベル 例 just> <テイク 例 01>` で、ステージを選んで録画する (scrcpy と adb が要る)。ボスのステージは撮らない。
2. **作る**: `promo/spec.example.json` を写して、録画の切り出し位置と字幕を書き、実行する。
   ```sh
   promo/fetch_assets.sh                      # 初回だけ: フォントとストアの公式バッジを取る (git に入れない素材)
   python3 promo/build.py promo/spec.x.json   # promo/out/{パターン名}_{A|B|C}.mp4 と、records と posts への追記
   ```
   `--dry-run` で長さの確認だけ、`--no-record` で記録なしの試験出力、`--posts-only` で投稿文だけを作る。既存のファイルは上書きしない。
3. **投稿する**: `posts/{ID}.txt` の YouTube 用・TikTok 用の文を使う。ID は YouTube のタグ欄にも入れる。`python3 promo/make_index.py` で、`posts/一覧.md` (ID・投稿日・長さ・字幕の一覧) を作り直せる。
4. **記録する**: 再生数と視聴率 (視聴 vs スワイプ) は `records/videos.csv` に手で書く。

## 録画の前に (`capture.sh`)

`capture.sh` は画面の決まった位置をタップして進めるので、端末を次の状態にしておく。合わないときは、録画を始める前にエラーで止まる (解像度・章の数・ボスのステージ)。

- **解像度**: 2400x1080 (`adb shell wm size` が `2400x1080` か `1080x2400`)。タップの座標はこの解像度の値。ほかの解像度の端末では止まるので、同じ縦横比なら `adb shell wm size 1080x2400` で合わせる (戻すときは `adb shell wm size reset`)。
- **向き**: アプリは横画面で開く。端末を横に置いて、画面が横向きになっていることを確かめる。
- **デバッグモード**: タイトルの `VER` を 3 回タップしておく (全ステージを選べる)。オフだと、まだ開いていないステージを押しても始まらない。
- **章**: ステージ選択は「まだクリアしていない最初のステージ」の章で開くので、`capture.sh` は ← キー (`KEYCODE_DPAD_LEFT`) で第1章へ戻してから、「次の章へ」で目的の章へ進める。普段遊んでいる端末でもそのまま撮れる。
- **端末は 1 台だけ** つなぐ (`adb devices`)。
- 録画に失敗すると (scrcpy が始まらない・終わり方がおかしい・ファイルが空)、scrcpy のログの末尾を出して 0 以外で終わる。ログは `promo/raw/<録画と同じ名前>.log` に残る。

## 決めごと

- 字幕は、気取らない話し言葉で 11 文字以内。最初のフレームから出す。パターンごとに言い回しを変える。
- 音は、ゲーム内の BGM と効果音 (自作の合成音) だけを使う。外部の音源は使わない。
- 字幕とバッジは、TikTok などの表示領域 (上 約 130px、下 約 480px) を避けて置く。
- 映像は、ボットの自動プレイ。人の腕前に見える言い切り (「神業」など) は避ける。

## YouTube への自動投稿 (`upload_youtube.py`)

標準ライブラリだけで動く。準備と使い方は、ファイルの冒頭に書いてある。注意:

- 投稿できるのは、チャンネルの**オーナー**の許可だけ。「チャンネルの権限」で共有された管理者は、YouTube API を使えない。オーナーが遠い場合は `auth-start` と `auth-finish` で、リンクを開いてもらうだけで許可できる。
- 鍵 (`client_secret.json`、`token.json`) は `~/.config/parry-break/youtube/` に置く。リポジトリには入れない。
- `--yes` を付けない限り、何も送らない (予行)。公開の範囲の既定は限定公開。

## 入れていないもの (`.gitignore`)

`promo/raw/` (録画)、`promo/out/` (出力動画)、`promo/apk/` (撮影用アプリ)、`promo/fonts/` と `promo/assets/` (`fetch_assets.sh` で取る素材)。
