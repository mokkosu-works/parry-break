# 宣伝動画 (promo)

ゲームの機能とは分けて、動画まわりはこの `promo/` の中だけで進める。

**配信の方針** (投稿先・ペース・担当キャラ・ゲスト・通常尺・作る順番) は [design/distribution-plan.md](design/distribution-plan.md) にまとめてある。まずそちらを読む。

```
capture/    実機の画面録画 (capture.sh、capture_mode.sh、raw/、apk/)
characters/ キャラの絵 (sheets/、bust/)、プロフィール、反応集、声の割り当て
assets/     動画に載せるキャラ以外の画像 (文字・吹き出し・タグ・ロゴ)
longform/   通常尺の道具 (bust.py: バストアップの口パク素材を作る)
editor/     キャラ動画の編集ツール (server.py、render.py、check_layout.py)。projects/ に現役のプロジェクト、projects/old/ に過去の版
build/      動画の組み立て (create_*.py、build.py、specs/、fonts/、assets/、out/)。old/ に使わなくなったスクリプト
design/     企画・決めごと・確認画像。old/ に過去の版の記録
upload/     YouTube へのアップロード
analytics/  アナリティクスの CSV (exports/) と集計
posts/      動画の ID ごとの投稿文、一覧.md
records/    videos.csv、youtube_uploads.csv
```

## 画像の置き場所

新しい種類の画像を置くときは、この表に 1 行足す。ルール: 種類で分ける、動画の種類ごとにフォルダを分ける、使わなくなったものは同じ場所の `old/` へ(消さない)、ファイル名は変えない、動画は Codex の下書き(`out/`)を直接参照しない。

| 場所 | 中身 | git | 何が作るか |
|---|---|---|---|
| `characters/sheets/` | 全身の 6 枠シート `<名前>_sheet.png`(ショートで使う)、色の一覧 `color_roster.png`。`old/character_sheet_v2.png` は旧ミツバ | 入る | Codex(指示文は残っていない、初期の素材) |
| `characters/bust/` | 通常尺のバストアップ。元のシート `<名前>_bust_sheet{1,2,3}.png`・`<名前>_bust_blink.png` と、合成した `<名前>/<表情>_{closed,open}.png`・`normal_blink.png` | 入る | Codex(`design/codex/longform-akane/`・`longform-bust/`)→ `longform/bust.py` |
| `assets/text/shorts-play/` | プレイ紹介の見出し・吹き出し・「ストアで検索」(`<名前>_v05_*.png` など) | 入る | Codex(`design/codex/v05/`) |
| `assets/text/shorts-modes/` | モード紹介の見出し・吹き出し(`<名前>_mode01_*.png`) | 入る | Codex(`design/codex/mode01/`) |
| `assets/tags/` | モードのタグ `<名前>_tag_<stage\|endless\|daily\|practice>.png`(5 人 × 4) | 入る | Codex の 5 枚を土台に色を塗り替え |
| `assets/logo/title-logo.png` | ゲームの実物のタイトルロゴ | 入る | `build/create_title_logo.py` |
| `design/longform-layout.png`、`design/character-layout-comparison-v01.png` | 画面構成案(通常尺・ショート) | 入る | 手で作った見本 |
| `design/checks/` | 書き出しのコマなどの確認画像 | 入る | 確認のたびに |
| `design/codex/<回>/` | Codex の指示文(`ref/*.txt`)。参考画像(`ref/*.png`)と生成の下書き(`out/`) | 指示文だけ | Codex。`old-layout/out/` は以前の作業用の写し(どこからも参照しない) |
| `build/assets/badges/`、`build/fonts/` | ストアの公式バッジ、フォント | 入らない | `build/fetch_assets.sh` |
| `capture/raw/`、`build/out/` | 録画、書き出した動画 | 入らない | `capture/*.sh`、編集ツール |

キャラクター素材は [characters/README.md](characters/README.md)、性格・口調・表情の使い分けは [characters/profiles.md](characters/profiles.md) を参照する。

## 現役: キャラ動画 (ショート、縦長 24 秒)

- 採用版は 2 種類で、どちらも 5 人分ある。
  - **モード紹介** `promo/editor/projects/<名前>-modes.json`: 担当のモードを紹介する (ミツバはゲーム全体の案内)。作り方と決めごとは [design/shorts-modes.md](design/shorts-modes.md)。
  - **プレイ紹介** `promo/editor/projects/<名前>-play.json`: 打ち返し・崩れの楽しさを見せる。作り方と決めごとは [design/shorts-play.md](design/shorts-play.md)。
  - 以前の名前は、モード紹介が mode01、プレイ紹介が v05。途中の版 v01/v02 と、投稿済みのミツバの動画 (`character-promo*`、v009〜v012) は `projects/old/` にあり、編集ツールの一覧には出ない。
- 見出し・吹き出し・タグの文字は画像 (`promo/assets/`) で、文言を変えるときは Codex で作り直す。モードのタグは `<名前>_tag_<stage|endless|daily|practice>.png` (5 人 × 4 モード)。
- 編集ツール (標準ライブラリ + Pillow + ffmpeg。npm などは不要):
  ```sh
  python3 promo/editor/server.py      # http://127.0.0.1:8765/ を開く (127.0.0.1 だけで待ち受ける)
  ```
  「動画を書き出す」で、保存した配置から `promo/build/out/{名前}-e001.mp4` のような新しい名前の動画を作る (既存のファイルは上書きしない)。画面なしなら `python3 promo/editor/render.py promo/editor/projects/mitsuba-modes.json`。台詞と話し始めの時刻は、レイヤーを選んでいないときの右パネルで変えられる (JSON の `voice.lines`)。声は AivisSpeech (キャラごとに `characters/voice-licenses.md` の割り当て、起動は `~/.aivisspeech/engine/Linux-x64/run --host 127.0.0.1 --port 10101`)。24 秒の構成は変えられない。
- 文字とバッジは、ショートの表示領域 (上 約 130px、下 約 480px) を避けて置く。左右 100px と、右のボタン列 (x>930、y>1220。実機で測った値) も避ける。書き出す前に `python3 promo/editor/check_layout.py <プロジェクト名>` で確かめる (キャラと吹き出し・タイトルなどの重なりも見る)。
- 録画は、1.5.0 以降の撮影用アプリ (ストア版と並べて入れる別アプリ) で撮る。モードは `promo/capture/capture_mode.sh`、ステージは `promo/capture/capture.sh` (下の「録画の前に」)。手順は [design/shorts-modes.md](design/shorts-modes.md)。
- 映像は、ボットの自動プレイ。人の腕前に見える言い切り (「神業」など) は避ける。

## 投稿と記録

- 投稿先は **YouTube だけ** (TikTok はやめた。過去の `posts/` にある TikTok 用の文はそのまま残す)。
- 投稿文は `promo/posts/{ID}.txt` (YouTube 用)。ID は YouTube のタグ欄にも入れる。`python3 promo/posts/make_index.py` で、`promo/posts/一覧.md` (ID・投稿日・長さ・字幕の一覧) を作り直せる。
- 再生数と視聴率 (視聴 vs スワイプ) は `promo/records/videos.csv` に手で書く (YouTube Studio の CSV は `promo/analytics/exports/` に置く。`promo/analytics/README.md`)。

## YouTube への自動投稿 (`upload_youtube.py`)

標準ライブラリだけで動く。準備と使い方は、ファイルの冒頭に書いてある。注意:

- 投稿できるのは、チャンネルの**オーナー**の許可だけ。「チャンネルの権限」で共有された管理者は、YouTube API を使えない。オーナーが遠い場合は `auth-start` と `auth-finish` で、リンクを開いてもらうだけで許可できる。
- 鍵 (`client_secret.json`、`token.json`) は `~/.config/parry-break/youtube/` に置く。リポジトリには入れない。
- `--yes` を付けない限り、何も送らない (予行)。公開の範囲の既定は限定公開。

## 撮影用アプリと録画の前に (`capture.sh`)

撮影用ビルド (自動プレイ入り) を実機に入れて録画する。
```sh
cd app
flutter build apk --release --dart-define=PROMO_AUTOPLAY=true            # 下手なプレイ (既定)
flutter build apk --release --dart-define=PROMO_AUTOPLAY=true \
  --dart-define=PROMO_SIGMA=0.006 --dart-define=PROMO_SPEED=1500 \
  --dart-define=PROMO_BIAS=0 --dart-define=PROMO_LAG_COMP=true          # JUST を狙うプレイ
adb install -r build/app/outputs/flutter-apk/app-release.apk
```
ストア版と並べて入れる別アプリ (`.promo`、広告オフ) にする手順は [design/shorts-modes.md](design/shorts-modes.md)。実機で設定画面の `VER` を 3 回タップしてデバッグモードにすると、全ステージを選べる (撮影用ビルドでは、DEBUG の帯は出ない)。
`promo/capture/capture.sh <ステージ 例 2-7> <ラベル 例 just> <テイク 例 01>` で、ステージを選んで録画する (scrcpy と adb が要る。撮影用アプリは `PROMO_PKG=com.watsuwo.parrybreak.promo`)。ボスのステージは撮らない。

`capture.sh` は画面の決まった位置をタップして進めるので、端末を次の状態にしておく。合わないときは、録画を始める前にエラーで止まる (解像度・章の数・ボスのステージ)。

- **解像度**: 2400x1080 (`adb shell wm size` が `2400x1080` か `1080x2400`)。タップの座標はこの解像度の値。ほかの解像度の端末では止まるので、同じ縦横比なら `adb shell wm size 1080x2400` で合わせる (戻すときは `adb shell wm size reset`)。
- **向き**: アプリは横画面で開く。端末を横に置いて、画面が横向きになっていることを確かめる。
- **デバッグモード**: 設定画面の `VER` を 3 回タップしておく (全ステージを選べる)。オフだと、まだ開いていないステージを押しても始まらない。
- **章**: ステージ選択は「まだクリアしていない最初のステージ」の章で開くので、`capture.sh` は ← キー (`KEYCODE_DPAD_LEFT`) で第1章へ戻してから、「次の章へ」で目的の章へ進める。普段遊んでいる端末でもそのまま撮れる。
- **端末は 1 台だけ** つなぐ (`adb devices`)。
- 録画に失敗すると (scrcpy が始まらない・終わり方がおかしい・ファイルが空)、scrcpy のログの末尾を出して 0 以外で終わる。ログは `promo/capture/raw/<録画と同じ名前>.log` に残る。

## 過去の形式

### ボット動画 (v005〜v008、`build.py`)

実機の画面録画から、縦動画 (9:16、15〜30秒) を作る。冒頭 3 秒だけ違う A / B / C の 3 本を、同じ映像から作る (A=惜しい失敗、B=見栄えのする場面、C=結果の瞬間)。冒頭以外 (本編と最後の 2 秒) は 3 本で同じ。最後の 2 秒に、アプリ名・「ストアで検索」・公式のストアバッジを出す。
```sh
promo/build/fetch_assets.sh                # 初回だけ: フォントとストアの公式バッジを取る (git に入れない素材)
python3 promo/build/build.py promo/build/specs/spec.x.json   # promo/build/out/{パターン名}_{A|B|C}.mp4 と、promo/records と promo/posts への追記
```
`--dry-run` で長さの確認だけ、`--no-record` で記録なしの試験出力、`--posts-only` で投稿文だけを作る。既存のファイルは上書きしない。字幕は、気取らない話し言葉で 11 文字以内。最初のフレームから出す。音は、ゲーム内の BGM と効果音 (自作の合成音) だけ。長さは `build.py` が `promo/records/videos.csv` の「長さ(秒)」に書く。

### ミツバの動画 (v009〜v012)

`promo/build/old/character_promo.py` が v12 (VOICEVOX:春歌ナナ) を再現する記録。編集ツールの元になった。プロジェクトは `promo/editor/projects/old/character-promo*.json`、投稿文は `promo/posts/v009.txt`〜`v012.txt` と `character-promo-v12.txt`。

### キャラ動画の途中の版 (v01/v02)

記録は `promo/design/old/`、生成スクリプトは `promo/build/old/`、プロジェクトは `promo/editor/projects/old/`。

## 入れていないもの (`.gitignore`)

`promo/capture/raw/` (録画)、`promo/capture/apk/` (撮影用アプリ)、`promo/build/out/` (出力動画)、`promo/build/fonts/` と `promo/build/assets/` (`fetch_assets.sh` で取る素材)。
