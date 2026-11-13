# 宣伝動画 (promo)

ゲームの機能とは分けて、動画まわりはこの `promo/` の中だけで進める。

```
capture/    実機の画面録画 (capture.sh、raw/、apk/)
build/      動画の組み立て (build.py、specs/、fonts/、assets/、out/)
upload/     YouTube へのアップロード
analytics/  アナリティクスの CSV (exports/) と集計
posts/      動画の ID ごとの投稿文、一覧.md
records/    videos.csv、youtube_uploads.csv
```

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
   `promo/capture/capture.sh <ステージ 例 2-7> <ラベル 例 just> <テイク 例 01>` で、ステージを選んで録画する (scrcpy と adb が要る)。ボスのステージは撮らない。
2. **作る**: `promo/build/specs/spec.example.json` を写して、録画の切り出し位置と字幕を書き、実行する。
   ```sh
   promo/build/fetch_assets.sh                # 初回だけ: フォントとストアの公式バッジを取る (git に入れない素材)
   python3 promo/build/build.py promo/build/specs/spec.x.json   # promo/build/out/{パターン名}_{A|B|C}.mp4 と、promo/records と promo/posts への追記
   ```
   `--dry-run` で長さの確認だけ、`--no-record` で記録なしの試験出力、`--posts-only` で投稿文だけを作る。既存のファイルは上書きしない。
3. **投稿する**: `promo/posts/{ID}.txt` の YouTube 用・TikTok 用の文を使う。ID は YouTube のタグ欄にも入れる。`python3 promo/posts/make_index.py` で、`promo/posts/一覧.md` (ID・投稿日・長さ・字幕の一覧) を作り直せる。長さは `build.py` が `promo/records/videos.csv` の「長さ(秒)」に書いたものを使うので、`promo/build/out/` のない環境で作り直しても同じ表になる。
4. **記録する**: 再生数と視聴率 (視聴 vs スワイプ) は `promo/records/videos.csv` に手で書く (YouTube Studio の CSV は `promo/analytics/exports/` に置く。`promo/analytics/README.md`)。

## 録画の前に (`capture.sh`)

`capture.sh` は画面の決まった位置をタップして進めるので、端末を次の状態にしておく。合わないときは、録画を始める前にエラーで止まる (解像度・章の数・ボスのステージ)。

- **解像度**: 2400x1080 (`adb shell wm size` が `2400x1080` か `1080x2400`)。タップの座標はこの解像度の値。ほかの解像度の端末では止まるので、同じ縦横比なら `adb shell wm size 1080x2400` で合わせる (戻すときは `adb shell wm size reset`)。
- **向き**: アプリは横画面で開く。端末を横に置いて、画面が横向きになっていることを確かめる。
- **デバッグモード**: タイトルの `VER` を 3 回タップしておく (全ステージを選べる)。オフだと、まだ開いていないステージを押しても始まらない。
- **章**: ステージ選択は「まだクリアしていない最初のステージ」の章で開くので、`capture.sh` は ← キー (`KEYCODE_DPAD_LEFT`) で第1章へ戻してから、「次の章へ」で目的の章へ進める。普段遊んでいる端末でもそのまま撮れる。
- **端末は 1 台だけ** つなぐ (`adb devices`)。
- 録画に失敗すると (scrcpy が始まらない・終わり方がおかしい・ファイルが空)、scrcpy のログの末尾を出して 0 以外で終わる。ログは `promo/capture/raw/<録画と同じ名前>.log` に残る。

## 決めごと

- 字幕は、気取らない話し言葉で 11 文字以内。最初のフレームから出す。パターンごとに言い回しを変える。
- 音は、ゲーム内の BGM と効果音 (自作の合成音) だけを使う。外部の音源は使わない。
- キャラクター主体の試作は例外。`python3 promo/build/character_promo.py` は起動中のローカル VOICEVOX エンジンと `Pillow`、`ffmpeg` を使い、24秒の `promo/build/out/character-promo-v12.mp4` を出力する。既存動画と投稿記録は変更せず、出力は上書きしない。音声は「VOICEVOX:春歌ナナ」で、動画の締めに控えめなクレジットを表示する。プレイ中は全カットで同じ小さな縦揺れ、アウトロは静止。プレイ中にもアプリアイコン、「ストアで検索」、ストアバッジを出し、PARRY BREAKのロゴを大きく表示する。用語は「白いブロック」に統一。投稿文は `promo/posts/character-promo-v12.txt` にあり、概要欄・キャプションにも同じクレジットを含む。
- キャラクター主体の動画の配置は、ブラウザーの編集ツールでも試せる (標準ライブラリ + Pillow + ffmpeg。npm などは不要)。
  ```sh
  python3 promo/editor/server.py      # http://127.0.0.1:8765/ を開く (127.0.0.1 だけで待ち受ける)
  ```
  配置は `promo/editor/projects/*.json` に保存する (既定の `character-promo.json` は v12 と同じ配置)。「動画を書き出す」で、保存した配置から `promo/build/out/{名前}-e001.mp4` のような新しい名前の動画を作る (既存のファイルは上書きしない。VOICEVOX の起動が要る)。画面なしなら `python3 promo/editor/render.py promo/editor/projects/character-promo.json`。台詞と話し始めの時刻は、レイヤーを選んでいないときの右パネルで変えられる (JSON の `voice.lines`。ないときは v12 と同じ台詞)。声 (春歌ナナ) と 24 秒の構成は変えられない。
- 字幕とバッジは、TikTok などの表示領域 (上 約 130px、下 約 480px) を避けて置く。
- 映像は、ボットの自動プレイ。人の腕前に見える言い切り (「神業」など) は避ける。

## YouTube への自動投稿 (`upload_youtube.py`)

標準ライブラリだけで動く。準備と使い方は、ファイルの冒頭に書いてある。注意:

- 投稿できるのは、チャンネルの**オーナー**の許可だけ。「チャンネルの権限」で共有された管理者は、YouTube API を使えない。オーナーが遠い場合は `auth-start` と `auth-finish` で、リンクを開いてもらうだけで許可できる。
- 鍵 (`client_secret.json`、`token.json`) は `~/.config/parry-break/youtube/` に置く。リポジトリには入れない。
- `--yes` を付けない限り、何も送らない (予行)。公開の範囲の既定は限定公開。

## 入れていないもの (`.gitignore`)

`promo/capture/raw/` (録画)、`promo/capture/apk/` (撮影用アプリ)、`promo/build/out/` (出力動画)、`promo/build/fonts/` と `promo/build/assets/` (`fetch_assets.sh` で取る素材)。
