# ストア動画 撮影済み素材の選定 v01

2026-11-18。`store-video-outline-v01.md` の2本に対し、Android 実機のログ付き録画から仮カットを選んだ。時刻は各 `capture.mp4` の先頭から。確認用の仮つなぎは `promo/build/out/store-play-rough-v03.mp4` と `store-modes-rough-v02.mp4`(それより前の版と、字幕付きの v04・v03 より前の版は `build/out/old/`)（文字・整音・転場なし、1280×576）。

テロップと整音を入れた確認版は `promo/build/out/store-play-captioned-v03.mp4` と `store-modes-captioned-v04.mp4`。`promo/build/render_store_previews.py` で同じカットから再生成できる。画面は1920×1080・30fpsで、実プレイを中央に置く。モード紹介では既存の色付きタグを上部に、一言の説明を下部に分ける。音は各カットのつなぎ目を短くフェードさせ、全体の音量とピークを整えた。

モード紹介 `store-modes-captioned-v04.mp4` の上部タグと下部説明の配置は本人確認済み、採用。

## プレイ紹介（約28秒）

| 完成尺 | 元映像 `promo/capture/raw/` 以下 | 元の時刻 | 選んだ出来事 |
| --- | --- | --- | --- |
| 0–3秒 | `long-stage-mitsuba-s11-sloppy-01/capture.mp4` | 11.1–14.1秒 | 通常ステージ、12.39秒に PERFECT パリィ |
| 3–9秒 | `long-stage-mitsuba-s11-sloppy-01/capture.mp4` | 14.1–20.1秒 | 冒頭と同じ通常ステージを続け、15.15秒と17.71秒にパリィ。後半のフィーバーと見せ場が重複しない |
| 9–16秒 | `long-stage-mitsuba-s12-just-02/capture.mp4` | 12.6–19.6秒 | 13.58秒と19.43秒に崩落 |
| 16–23秒 | `long-stage-mitsuba-s14-just-01/capture.mp4` | 19.1–26.1秒 | パリィの連続、22.54秒にフィーバー開始、25.52秒にラウンドクリア |
| 23–25秒 | `long-stage-mitsuba-s21-just-05/capture.mp4` | 30.1–32.1秒 | ステージクリア直前の画面 |
| 25–28秒 | `mtitle_v151.mp4` | 0.5–3.5秒 | 実物のタイトル画面 |

## モード紹介（約26秒）

| 完成尺 | 元映像 `promo/capture/raw/` 以下 | 元の時刻 | 内容 |
| --- | --- | --- | --- |
| 0–2秒 | `long-stage-mitsuba-s11-sloppy-01/capture.mp4` | 11.1–13.1秒 | パリィを冒頭に置く |
| 2–7秒 | `long-stage-mitsuba-s21-just-05/capture.mp4` | 17.5–22.5秒 | ステージ |
| 7–12秒 | `long-endless-mitsuba-mode-endless-02/capture.mp4` | 13–18秒 | エンドレス |
| 12–17秒 | `long-daily-mitsuba-mode-daily-02/capture.mp4` | 13–18秒 | デイリー |
| 17–22秒 | `long-practice-mitsuba-mode-practice-02/capture.mp4` | 15.8–20.8秒 | 練習 |
| 22–26秒 | `mtitle_v151.mp4` | 0.5–4.5秒 | 実物のタイトル画面 |

## 仮つなぎの評価と次の編集

- 初回の仮つなぎではステージの説明表示が盤面に重なったため、モード紹介の `long-stage-mitsuba-s21-just-05` の開始を12.7秒から17.5秒へ変更した。プレイ紹介の基本パートは冒頭と同じステージを続け、後半のフィーバーと重複させない。
- 仮つなぎはカットの流れを見るためのもの。テロップ、音量、ロゴの見せ方、色、切れ目の調整は未実施。
- 見せたい出来事はログで照合済み。最終カットは実際に全編を再生し、崩落とフィーバーの動きが伝わるか確認して微調整する。
- App Store 用には同じ構成を iOS 実機で撮り直す。Android のこの仮つなぎをそのまま iOS 用として提出しない。
