# ゲームモード紹介(character-<名前>-mode01、2026-11-16)

1.5.0 のモード(ステージ、エンドレス、デイリー、練習)を 5 人に割り振った。台詞と吹き出しは、v05 とも他のキャラとも言い回しが重ならないように書いた。

| キャラ | モード | 見出し(冒頭/2/3) | 吹き出し(冒頭/2/3/最後) | 録画 |
| --- | --- | --- | --- | --- |
| ミツバ | 入口(4つ) | 遊び方、4つ!/一面ずつのステージ/毎日変わるデイリー | どれにしよっかな?/星も集めたい!/今日のはどんなの?/好きなのからどうぞ! | mtitle_01, mstage_01, mdaily_01 |
| ワカナ | ステージ | ステージで遊ぼう/目標を見てから/星を3つ集める | まずは1-1から。/全部壊せば終わり。/星3つ、そろったね。/次の面も待ってるよ。 | mstage_01 |
| アカネ | エンドレス | 終わりなし!/ラウンドが続く!/スコアを伸ばせ! | どこまでいける?/まだ止まらない!/もっと上、いけるはず!/記録、見せてよ! | mendless_01 |
| シズク | 練習 | 練習モード/ずれが数字で出る/落としても大丈夫 | ブロックはない。/遅い、早い、が分かる。/何度でも、もう一回。/JUST、狙ってみて。 | mpractice_01 |
| モモカ | デイリー | 今日のデイリー!/みんな同じ配置/ミスしたら終わり | 今日だけの配置だよ!/どこで差がつくかな?/ドキドキするね!/明日も一緒にね! | mdaily_01 |

- ポーズは場面ごとに変えた(`create_mode_videos.py` の `VIDEOS`)。最後の画面は v05 の配置(本人が調整したミツバの型)のまま。
- 録画は 1.5.0 の撮影用アプリで撮った。メニューや結果の画面は画面全体、プレイ中は盤面(x=360〜2160)を切り出す。
- 文字の素材の指示文は `codex/mode01/ref/`(元の生成画像は `codex/mode01/out/`、git 外)。Codex は推論 low で 1 人ずつ頼んだ。シズクとモモカの吹き出しは中のしみを塗り直した(手順は `character-series-v05.md` の「文字の画像の作り方」)。
- 作り方: `python3 promo/build/create_mode_videos.py` → 編集ツールで `character-<名前>-mode01` を開く。確認画像は `checks/character-mode01-frames.jpg`、`checks/character-mode01-bigger-game.jpg`。

## 撮影(1.5.0)

スマホにはストア版(Google Play の 1.5.0 以前)が入っていて、手元の鍵で署名した APK は上書きできない(消すとセーブデータが消える)。そこで dev の作業フォルダで次の 3 点だけ変えてビルドし、別アプリ `com.watsuwo.parrybreak.promo` として並べて入れた(リポジトリには入れていない)。

1. `android/app/build.gradle.kts` に `applicationIdSuffix = ".promo"`
2. `lib/services/ads.dart` の `enabled` を、撮影用ビルドでは false(正式な広告枠にリクエストしないため)
3. `pubspec.yaml` の Flutter の版の指定を `">=3.47.6 <3.48.0"`(この PC は 3.47.9)

ビルドの引数は JUST 狙い版(promo/README.md)。APK は `promo/capture/apk/promo_just_v1.5.0_side.apk`(git 外)。撮影は `promo/capture/capture_mode.sh <title|endless|daily|practice|stage> <テイク>`。エンドレスは 120 秒で R6 前後まで進み、ボスの R10 には届かない。
