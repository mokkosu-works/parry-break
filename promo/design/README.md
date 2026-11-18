# promo/design

宣伝動画の企画・決めごと・確認画像。

## 現役

- `handoff.md`: 引き継ぎ資料(いまの状態・次にやること・作業の決まり・本人との進め方)
- `audio-source-check-20261117.md`: 最初の本編録画の音声混入の調査と不採用の記録、録り直しの対策
- `distribution-plan.md`: 配信の方針 (投稿先・ペース・担当キャラ・ゲスト・通常尺・作る順番) と、4 モードの仕様。**最初に読む**
- `shorts-modes.md`: **基本の型**(ミツバの通常尺 l001 とショート v014 の組、冒頭 3 秒の作り方)、ショートのモード紹介 (プロジェクトは `<名前>-modes`、以前の名前は mode01) と、1.5.0 の撮影の手順
- `longform.md`: 通常尺の作り方と本人と決めたこと。`longform-mitsuba-outline-v01.md`: ミツバの通常尺 l001 の骨組み
- `store-video-outline-v01.md`、`store-video-shots-v01.md`: ストア掲載用の動画 2 本(プレイ紹介・4 モード紹介)の構成と、使うカット。書き出しは `build/render_store_previews.py`
- `shorts-play.md`: ショートのプレイ紹介 (プロジェクトは `<名前>-play`、以前の名前は v05)。文字の画像の作り方もここ
- `character-layout-comparison-v01.png`: 画面構成案 (5 人の見た目の基準)
- `longform-layout.png`: 通常尺の画面構成案 (案 B。録画を全幅、下の帯にキャラと字幕)
- `longform-akane-outline-v01.md`: アカネのエンドレス紹介の骨組み(約3分45秒、紹介順は本人が確認済み。個々の台詞は候補)
- `akane-longform-{opening,chapter,ending}-v01.png`: 冒頭・区切り・締めの構成案(本人の確認待ち)。`checks/akane-longform-scenes-v01.jpg` は3場面の一覧
- `checks/`: 書き出しのコマやセーフエリアを確かめた画像
  - `old/akane-endless-pilot-v01.jpg`: 音声混入が疑われる旧試作の確認画像。動画と手順は `../longform/README.md`
  - `character-series-v01-final-frames.jpg`, `-v02-final-frames.jpg`: 途中の版 v01/v02 のコマ
  - `character-series-v03-mitsuba-compare.jpg`: 構成案と v03 の比べ
  - `character-series-v05-*.jpg`: プレイ紹介(v05)のコマ・セーフエリア・全員左に揃えた版・アウトロの直し
  - `character-mode01-frames.jpg`, `-bigger-game.jpg`: モード紹介のコマ、ゲーム画面を大きくした版
  - `character-sprites-v02-review.png`: v02 で切り出した 30 ポーズの確認
- `codex/<回>/`: Codex に頼んだ指示文(`ref/*.txt`、git に入る)。参考画像(`ref/*.png`)と生成の下書き(`out/`)は大きいので git に入れない。採用したものは `promo/characters/` か `promo/assets/` に写してある
  - `v03-mitsuba/`, `v05/`: プレイ紹介の文字の画像
  - `mode01/`: モード紹介の文字の画像とタグ(`prompt-play-tags*.txt` はプレイ紹介のタグ)
  - `longform-akane/`: 通常尺のアカネのバストアップ
  - `longform-bust/`: 通常尺のほかの 4 人のバストアップ(`run.sh` で 1 枚ずつ順に作る)
  - `longform-full/`: アカネの全身3ポーズと目パチの指示文(本人が採用済み)
  - `longform-scenes/`: アカネの場面構成案に使う見出し3種類の指示文。構成案は `longform/scene_proposals.py` で合成する
  - `old-layout/out/`: 以前 `build/assets/layout/` にあった作業用の写し(どこからも参照しない)

## 過去の版

- `old/character-series-v01.md`, `old/character-series-v02.md`: キャラ動画の最初の 2 版の記録 (プロジェクトは `promo/editor/projects/old/`、スクリプトは `promo/build/old/`)
- `old/character-video-plans.md`: キャラ別ショートの企画の初稿 (2026-11-17 に `promo/` 直下から移した。いまの決めごとは `shorts-modes.md`・`shorts-play.md`)
- `checks/old/`: 使わなくなった確認画像 (不採用の通常尺試作 v01、場面構成案の下書き)
