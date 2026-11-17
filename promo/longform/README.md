# 通常尺の試作

作り方と決めごと(場面の構成・間・色・台詞の決まり)は [../design/longform.md](../design/longform.md)。このファイルは道具の使い方。

全身素材と3場面の構成案を作り、アカネのエンドレスで本編45秒を試した。全身素材と紹介順、録り直した `../build/out/akane-endless-pilot-e002/preview.mp4` は本人の確認済み。本人は後から別撮りのBGMも追加する予定。**最初の本編e001は別アプリの音声混入の疑いがあるため不採用。** 詳細は `../design/audio-source-check-20261117.md`。

- 骨組み：`../design/longform-akane-outline-v01.md`(完成版は約3分45秒の予定)
- 試作の配置案：`projects/akane-endless-pilot-v02-plan.json`
- 出来事から反応を割り当てた台本：`projects/akane-endless-pilot-v02.json`
- 動画：`../build/out/akane-endless-pilot-e002/preview.mp4`(1920×1080、24fps、45秒)
- 確認画像：`../design/checks/old/akane-endless-pilot-v01.jpg`(不採用の旧版)

この45秒は道具・声・反応の間の確認用。完成版の冒頭45秒ではなく、オープニング・章の区切り・エンディングはまだつないでいない。

## 撮影と時刻合わせ

撮影用の変更・APK・録画は `../capture/README.md`。ゲーム本体の `app/` は変更しない。

ログには `InputClock.now` の時刻 `clock_s`、実時刻 `wall_us`、ゲーム内の時刻 `sim_s` を別に残す。スロー演出・ヒットストップ・画面切り替えがあるため、**ゲーム内の時刻やscrcpyの起動時刻を、そのまま映像の秒にしない**。

映像内で途中のラウンドが始まるコマを確認し、対応する出来事の `seq` と映像の秒を指定する。

```sh
python3 promo/longform/align_events.py promo/capture/raw/long-endless-akane-pilot05-clean \
  --anchor-seq 95 --video-time 20.75 \
  --note 'R2の新しい盤面の出現を0.2秒刻みで目視確認。'
```

採用した試作のR2開始は録画の約20.75秒。初回のタイトルからの画面切り替えは演出の遅れがあるので基準にしなかった。変換した `events.json` は未調整のログと別に保存する。既存ファイルは上書きしない。

採用したテイクのログ930件には欠落がない。不採用の初回テイクは末尾に1件欠落があり、`--through-seq` で連続した範囲に制限した。欠落・重複・時計の逆行は、調整時に止まる。欠落をまたいで台本を作らない。

ボスのあるラウンド開始を記録した場合は、その0.2秒前を使用可能な終わりにする。台本の区間が使用可能な範囲を越えると、台本作り・書き出しで止まる。余白は自動的な保証ではなく、使う最後のコマも確認する。

## 台本と声を付ける

解説・雑談は配置案へ手で書き、反応は指定した時間帯の実際の出来事から選ぶ。対象がなければ止まり、出来事や反応を作り足さない。反応の根拠になる `event_seq` を台本に残す。反応の台詞は `make_script.py` の `REACTIONS` にキャラごとにある(アカネ: ジャスト・フィーバー開始・崩れ。ミツバ: それに加えて空振り・パリィでのアイテム取得・ラウンドクリア)。帯の色・右上のタグ・声のクレジットは `render_long.py` の `PROFILES`(台本の `"tag"` でタグを替えられる。ミツバは既定でタグなし)。

ミツバの通常尺は、章ごとに 1 つの台本にしている(`projects/mitsuba-ch04-v01.json` など。区切りの数秒は含まない)。02 は 1-1 の下手版(02a)と 1-4 の敵弾(02b)の 2 つに分けた。06・07 は、短い録画をつなぐ `"clips"` の台本(`source`・`start`・`duration` と、任意の `events`・`tag`・`autoplay`・`logo`)。ログのない録画(タイトル・設定の画面)は、ほかのアプリの音が入っていないことの確かめ方を `audio_note` に書いたものだけ使える。タイトル・設定の画面は `"logo": false` で左上のロゴを重ねず、`"autoplay": false` で「自動プレイ映像」を出さない。clips の台本は反応を使わないので、`make_script.py` を通さずに直接書く。確認動画は `../build/out/mitsuba-ch{01,02a,02b,03,04,05}-e003/`(02a は e004、06 は e003、07 は e002)(字幕の枠の左上に、話している人の名札を出す。名前と色は `PROFILES`)。

```sh
python3 promo/longform/make_script.py \
  promo/longform/projects/akane-endless-pilot-v02-plan.json \
  --out promo/longform/projects/akane-endless-pilot-v02.json

# AivisSpeech(10101)が必要。採用済みのrender.synthesizeとvoice_timingを使う。
python3 promo/longform/render_long.py promo/longform/projects/akane-endless-pilot-v02.json \
  --out promo/build/out/akane-endless-pilot-e002 --prepare-only

# 音声作成後はこちら。音声エンジン不要。
python3 promo/longform/render_long.py promo/longform/projects/akane-endless-pilot-v02.json \
  --out promo/build/out/akane-endless-pilot-e002
```

上のファイルは作成済みなので、そのまま再実行すると上書きを防ぐため止まる。改訂時は台本と出力先に新しい版を付ける。音声を作った後で台本が変わった場合も止まる。

## BGM

BGM は本人が Windows の DAW で作る。手順・書き出しの決まり・Windows でのやり方は [bgm.md](bgm.md)。

```sh
# DAW で合わせるための見本 (guide.mp4、voice.wav、game.wav、cues.csv/md)。出力は <フォルダ>/bgm-kit/
python3 promo/longform/bgm_kit.py promo/build/out/akane-endless-pilot-e002 --bpm 120

# 届いた BGM を確かめる (Windows でも動く)
python3 promo/longform/check_bgm.py <書き出した.wav> --length 45

# 台本に "bgm" を足した版を、前の声を写して書き出す (音声エンジン不要)
python3 promo/longform/render_long.py promo/longform/projects/akane-endless-pilot-v03.json \\
  --out promo/build/out/akane-endless-pilot-e003 --voices-from promo/build/out/akane-endless-pilot-e002
```

`v03` の台本は、BGM が届いてから v02 に `bgm` を足して作る。台詞の間は BGM が約 7dB 下がる (`render_long.py` の `DUCK`)。

案Bどおり、ゲーム映像は1920×864、その下に216pxの帯、左にバストアップ、右に字幕。ロゴとタグは既存素材。「自動プレイ映像」と音声クレジットを表示する。口パクは発声中の簡易開閉で、音素によるリップシンクではない。目パチは発話のない時に通常の顔で入れる。

ゲームの音量は元の0.38倍。声とゲーム音を混ぜて上限を抑える。聞こえ方の判断は本人に依頼する。`prepared.json` に台詞の開始・終了、`timing.json` に出力の長さなどを残す。`validation.json` は今回の確認結果。

## 確認済み

- 撮影用APKのリリースビルド、実機への更新、実際の映像と音と出来事の同時記録。
- 45秒の動画は1080コマ、映像と音声とも45秒。ffmpegで最後まで読める。
- 台詞8つの重なり・尺のはみ出しなし。反応3つは出来事の約0.18秒後に配置。
- 時計の基準、ログ欠落、ボスの範囲、重複、存在しない反応の検証5件。

```sh
python3 -m unittest discover -s promo/longform -p test_pipeline.py
```

本編の試作を本人が確認してから、解説と映像の合わせ方や声の間を詰め、約3分45秒の全編を組み立てる。

## 完成版を 1 本にまとめる

`assemble.py` は、オープニング → (章の区切り → 本編) × 章の数 → エンディング をつなぐ。配置はアカネの構成案(`scene_proposals.py`、本人確認済み)を土台にし、色は `render_long.PROFILES`(背景はショートと同じキャラの色。ミツバはクリーム `#FDF3D3` に焦げ茶の文字)。全身はショートと同じ 6 ポーズのシート(オープニング=通常、区切り=固有で章のタイトルを読む、エンディング=成功。どれも口パク・目パチ)。

```sh
python3 promo/longform/assemble.py promo/longform/projects/mitsuba-full-v01.json --out promo/build/out/mitsuba-full-e008 --prepare-only  # 声(AivisSpeech)
python3 promo/longform/assemble.py promo/longform/projects/mitsuba-full-v01.json --out promo/build/out/mitsuba-full-e008
```

- **変わり目の間**(構成の `gaps`。2026-11-17 に本人の指摘でそろえた): 前の場面の最後の台詞 → 区切りのタイトルまで 1.5 秒、タイトル → 本編の最初の台詞まで 1.0 秒、07 → エンディングの最初の台詞まで 1.5 秒。
  - 最後の台詞のあとの無音が長い場面(オープニング・各章の本編)は、後ろの映像を切る(音は 0.3 秒で小さくする)。
  - 区切りの長さはタイトルに合わせて決める(最低 2.5 秒。短いタイトルは前後の間が少し長くなる)。
  - エンディングの台詞は、間に合わせて後ろにずらす。各変わり目の間は `timing.json` の `gaps` に残り、最後に表で出る。
- 構成に書いた本編の台本と、本編を書き出したときの台本が違えば止まる。場面ごとに使うコマ数を正とし、音声をその長さにそろえてからつなぐ(ずれがたまらないように)。
- オープニング・エンディングの見出しの画像は、明るい背景で読めるように、白と焦げ茶を入れ替えた版を組み立てのときに作って使う(元の画像は変えない)。区切りのタイトルは濃い枠の中なので白いまま。
- エンディングは字幕を出さず、ロゴ・アプリのアイコン・「ストアで検索」・ストアのバッジ(Google Play・App Store。`promo/build/fetch_assets.sh` で取る)を並べる。右半分は YouTube の終了画面(最新の動画・チャンネル登録)を置く場所なので何も描かない。チャンネルが YouTube パートナープログラムに入っていないので、動画の中にストアのリンクは置けない。ストアのリンクは説明欄と固定コメントに貼る。
- 出力: `full.mp4`、YouTube のチャプター `chapters.txt`、`timing.json`。構成に `"bgm"`(`file`・`start`・`volume`(既定 0.2)・`fade_in`・`fade_out`)があれば、BGM なしの `full-nobgm.mp4` を作ってから BGM を混ぜる。声の間だけ BGM を下げる(鍵は声だけを並べた音なので、ゲーム音には反応しない)。BGM だけを変えたときは、声を作り直さなくてよい(前の出力の `prepared.json` と声を写す)。
- 本編の `"guest"`(clips の項目): その区間で、メンバーのバストアップと「メンバー」の名札をゲーム映像の右に出す(06 章で、担当のメンバーを紹介するとき)。グループ名(モコズ)は商標の確認が済むまで言わない。
- ミツバの完成版の試し: `../build/out/mitsuba-full-e008/full.mp4`(4 分 8 秒)。本編は `../build/out/mitsuba-ch*-e005/`(06 は e007)。
