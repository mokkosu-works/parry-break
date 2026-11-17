# ミツバ通常尺 撮影進捗 (2026-11-17)

撮影方針: [`../design/longform-mitsuba-outline-v01.md`](../design/longform-mitsuba-outline-v01.md)。通常尺は約4分8秒。映像と出来事ログを照合してから台詞・章の時刻を決める。撮影素材は `raw/` (git管理外) にある。

## 撮影済み

| 内容 | テイク | 状態・ログ |
|---|---|---|
| 1-1 JUST の試し撮り | `long-stage-mitsuba-s11-just-check01` | `recorded_unaligned`。音声・画面形式・ログ取得を確認。短い導入とクリアまでを含む |
| 1-1 下手版 | `long-stage-mitsuba-s11-sloppy-01` | `recorded_unaligned`。MISS 7 回を記録 |
| 1-2 白ブロック・崩落 | `long-stage-mitsuba-s12-just-02` | `recorded_unaligned`。`keystone` 2 回、`collapse` 2 回 |
| 1-4 砲台弾 | `long-stage-mitsuba-s14-just-01` | `recorded_unaligned`。`BulletFired` 7 回 |
| 2-1 FEVER・アイテム | `long-stage-mitsuba-s21-just-01`, `-02` | どちらも `recorded_unaligned`。各テイクでアイテムを取得したが `parried: false`。パリィ取得映像は未撮影 |
| タイトル・今日のお題・設定画面 | `mitsuba-ui-01`, `mitsuba-ui-colors-01` | `recorded`。色画面を含む。結果ランク画面の専用テイクは未確認 |

`long-stage-mitsuba-s12-just-01` は誤ったステージ選択の失敗テイク (`failed`)。素材とログは残してあるが、編集には使わない。

## 残作業

- 2-1 でアイテムをパリィ取得するテイクを追加撮影する (計画上は「できれば」だが、まだ撮れていない)。
- 4モード選択画面と各モードの短い映像を用意する。既存 `m*_v151.mp4` を使えるか確認し、EASY とエンドレス開始時の防壁も撮影対象に含める。
- 結果ランク画面が素材に入っているか確認し、なければ撮影する。
- すべての動画・イベントログを目視で時刻合わせし、使う区間と台詞を決める。現状、撮影済みテイクは未アライン (`recorded_unaligned`)。
- 撮影以外の制作素材 (ミツバ全身口パク、章見出し、BGM) は未完了。

## 作業状態

- ブランチ: `feature/promo-video-tools`。
- 撮影用 `.promo` APK は v1.6.0 の JUST 版・下手版を作成済み。ストア版は対象外。アプリデータは消さない。
- 撮影ツール変更とテストは未コミット: `README.md`, `capture_long.py`, `build_mitsuba.py`, `test_capture_long.py`。
- 現在、録画・ビルドなどの処理は停止中。再開時は接続状態とインストール済み `.promo` の版を確認してから進める。
