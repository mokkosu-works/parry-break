# Play Store 掲載情報

Google Play Console に入力する内容の下書き。署名とビルドの手順は [native-app-spec.md](native-app-spec.md) の 9.4 にある。文字数の上限は Play Console の制限。iOS の掲載情報は [app-store.md](app-store.md) にあり、説明文はそれをもとに Android 向けに直した。

## 基本情報

| 項目 | 値 |
| --- | --- |
| アプリ名 | 日本語「PARRY BREAK - パリィ×弾幕ブロック崩し」、英語「PARRY BREAK: Brick Breaker」(30字以内。App Store の名前と同じ) |
| パッケージ名 | `com.watsuwo.parrybreak`(一度アップロードすると変えられない) |
| デフォルトの言語 | 日本語(英語の翻訳も追加する) |
| アプリかゲームか | ゲーム |
| カテゴリ | アーケード |
| タグ | アーケード、アクション、ブロック崩し などから最大5つ |
| 価格 | 無料 |
| 連絡先のメールアドレス | shogowataru@gmail.com(ストアに公開される) |
| プライバシーポリシー URL | https://watsuwo.github.io/parry-break/privacy |
| ウェブサイト | https://watsuwo.github.io/parry-break/support |

App Store にあるサブタイトル・プロモーション用テキスト・キーワードは、Play Store にはない。代わりに「簡単な説明」がある。Play はタイトル・簡単な説明・詳しい説明の文章が検索に使われるので、遊びを表す語(ブロック崩し・弾幕・ドット絵・シューティングなど)を自然な文の中に入れる。語を並べるだけの書き方は、ポリシー違反になる。

## 日本語

**簡単な説明**(80字以内。ストアのページで最初に見え、検索にも使われる)

```
弾幕を撃ち返して崩す、高難度ブロック崩し。パリィで連鎖を狙うドット絵アーケード。
```

**詳しい説明**(4000字以内)

App Store の説明文から、Game Center の行を消した。Android のランキング(Play Games サービス)を有効にしたら、「・Google Play ゲームズのランキングに対応しています」を足す。

```
PARRY BREAK は、ブロック崩しの「受けて守る」パドルを「弾いて攻める」武器に変えた、アーケード型のスコアアタックです。

■ 当たる瞬間に弾く
ボールや敵弾がパドルに当たる瞬間に画面の右半分をタップすると、パリィになります。タイミングが PERFECT なら貫通弾、JUST なら衝撃波。撃ち返した敵弾は、最大の得点源になります。

■ 攻めるほど点が伸びる
ジャストパリィや撃ち返しでコンボが上がり、倍率が跳ね上がります。最高段階で発動する FEVER TIME では、ボールがブロックを次々と貫き、パリィのたびに分身弾が飛び出します。安全に受けるだけでは点になりません。

■ 崩落と誘爆
白い要石を壊すと、支えを失ったブロックがまとめて崩れ落ちます。オレンジの爆薬は周りを巻き込んで誘爆します。一撃で盤面をひっくり返す連鎖を狙ってください。

■ 2つのモード
・エンドレス: 60ラウンドとその先のループに挑むスコアアタック。10ラウンドごとにボス要塞が待ち受けます。
・ステージ: 全6章60ステージ。1面1〜2分の短いステージを、星3つの評価で攻略します。難易度は EASY / NORMAL / HARD から選べ、HARD は弾幕が激しくなります。第1章は基本を覚えるチュートリアルです。

■ ボール1個、ミスは即ゲームオーバー
コンティニューはありません。ボールを落とすか、ブロックがデッドラインまで下りてきたら終わりです。

■ 遊びやすさ
・左半分ドラッグで移動、右半分タップでパリィ。操作レール方式にも切り替えられます
・端末に合わせて判定タイミングを測定・補正できます
・フラッシュや画面の揺れを抑える設定があります
・広告はプレイ中には出ません。課金はありません

■ こんな人におすすめ
・昔ながらのブロック崩し(ブロックくずし、ブレイクアウト)に、ひとひねり加えた遊びを探している人
・弾幕を避けるだけでなく、撃ち返して攻めるシューティングが好きな人
・反射神経とタイミングで高いスコアを狙う、スコアアタックが好きな人
・ドット絵のレトロなアーケードを、片手でちょっと遊びたい人
```

## English

**Short description** (80 characters)

検索にも使われる。72 字。

```
Parry bullets back and break blocks. A tough pixel arcade brick breaker.
```

**Full description** (4000 characters)

```
PARRY BREAK turns the block-breaker paddle from a shield into a weapon. An arcade score attack where you parry instead of just catching.

- PARRY ON IMPACT
Tap the right half of the screen just as the ball or a bullet hits your paddle. PERFECT timing fires a piercing shot; JUST releases a burst. Every bullet you send back is a chance for big points.

- RISK PAYS
Parries and returned bullets build up your Combo and your multiplier. Max it out to trigger FEVER TIME: your ball tears through blocks, and every parry splits off clone balls. Playing safe won't get you far.

- COLLAPSE AND CHAIN BLASTS
Break a white keystone and every block it was holding comes crashing down. Orange explosives take their neighbours with them. Find the chain that flips the whole board.

- TWO MODES
Endless: Survive 60 rounds and the loop beyond, with a boss fortress every 10 rounds.
Stages: 60 short 1-2 minute stages across 6 chapters, rated with up to three stars. Pick EASY, NORMAL or HARD; HARD turns up the bullet hell. Chapter 1 teaches the basics.

- ONE BALL, NO CONTINUES
Drop the ball or let the blocks reach the dead line and it's over.

- BUILT TO PLAY WELL
- Drag on the left half to move, tap the right half to parry, or switch to rail controls
- Calibrate the timing offset to your device
- Reduce flashing and screen shake in Settings
- Ads never interrupt a run. No in-app purchases

WHO IT'S FOR
- Fans of classic brick breaker and breakout games who want a new twist
- Players who like bullet hell shooters and prefer hitting back to just dodging
- Anyone chasing a high score with sharp reflexes and tight timing
- Pixel-art retro arcade fans who want a quick one-handed session
```

Play Games サービスを有効にしたら、`- Google Play Games leaderboards` を足す。

## 画像

| 種類 | サイズ | 枚数 | 用意するもの |
| --- | --- | --- | --- |
| アプリのアイコン | 512 × 512、PNG(32 ビット) | 1 | `app/branding/icons/icon-512.png`。いまは透過なしの PNG なので、受け付けられなければ透過ありで書き出し直す |
| フィーチャー グラフィック | 1024 × 500、JPEG か 24 ビット PNG(透過なし) | 1 | ストアのページの一番上に出る横長の画像。タイトル画面のスクリーンショットから、ロゴが入るように 1024 × 500 を切り出したもの(下の「スクリーンショットの撮り方」の 5) |
| スマートフォンのスクリーンショット | 長い辺が短い辺の2倍以内、320〜3840 px | 2〜8 | 下の「スクリーンショットの撮り方」で撮った5枚。ゲームは横画面で 1920 × 1080 以上を4枚以上にすると、おすすめに載りやすい |

App Store 用の iPhone のスクリーンショット(2868 × 1320 など)は縦横比が 2:1 を超えるため、そのままでは使えない。Android は実機で同じテストを動かして撮り、2:1 に収める。

### スクリーンショットの撮り方

`integration_test/store_screenshots_test.dart` を実機で動かす。記録は見栄えのよい値を入れた仮のもので、端末の保存データには触らない。WSL には `/dev/kvm` がなく、エミュレーターは高速化が効かないので、実機を使った。

1. 端末と PC を同じ Wi-Fi につなぎ、端末の「開発者向けオプション → ワイヤレス デバッグ」をオンにする(Android 11 以上)。端末は横向きで、画面を点けたままにする。
2. 「ペア設定コードによるデバイスのペア設定」に出る IP とポート、6桁のコードで `adb pair <IP:ポート> <コード>` を実行する。続けて、ワイヤレス デバッグの**メイン画面**に出る、ペア設定用とは別のポートで `adb connect <IP:ポート>` を実行する。`adb devices` で `device` と出ればよい。ポートはワイヤレス デバッグを切るたびに変わる。
3. 撮影する。`<デバイス ID>` は `adb devices` の左の列(`192.168.1.86:37357` など)。

   ```sh
   cd app
   SHOT_DIR=build/store_screenshots/ja/android_raw flutter drive -d <デバイス ID> --dart-define=lang=ja \
     --driver=test_driver/integration_test.dart --target=integration_test/store_screenshots_test.dart
   ```

   初回はビルドに数分かかる。撮ったら目で確かめる。ボス戦はたまに被弾して「HIT!」が写るので、写っていたら撮り直す。
4. 縦横比を 2:1 以内にする。20:9 の端末だと、横にして 2400 × 1080(2.2:1)になり、そのままでは受け付けられない。
   - プレイ画面(ボス戦・崩落・プレイ中)は、盤面の中心に合わせて左右を切り、2160 × 1080 にする。盤面は画面の中央に寄っていて、左右は黒い余白なので、切っても何も欠けない。
   - タイトルとステージ選択は、画面いっぱいに文字があるので切らず、上下に背景色(`#07060A`)を 60 px ずつ足して 2400 × 1200 にする。
   - どれも透過なしの PNG で書き出す。
5. フィーチャー グラフィックは、タイトルの画像から、ロゴが上下の中央に来るように 1024 × 500 を拡大縮小せずに切り出す。

載せる順は、App Store に合わせて、ファイル名の番号の順(`01_boss` ボス戦 → `02_collapse` 崩落 → `03_play` プレイ中 → `04_stages` ステージ選択 → `05_title` タイトル)にする。最初の 1 枚は検索結果に出るので、プレイ画面から並べる。タイトル(`05_title`)は最後に載せるが、フィーチャー グラフィック(上の 5)の切り出し元にもなる。

Play Console に載っている順は、この文書で確かめていない。順が違っていたら、Play Console の「メインのストアの掲載情報 → スマートフォンのスクリーンショット」で、ドラッグして上の順に並べ直す(人の作業)。

## データ セーフティ

開発者自身は何も集めないが、広告(Google Mobile Ads SDK)がデータを集めて Google に送る。下の表は、Google の [Play のデータ開示に関するページ](https://developers.google.com/admob/android/privacy/play-data-disclosure) をまとめたもの。SDK を更新したら、このページを見直して表も直す。同意画面(UMP SDK)は広告の SDK と一緒に使うもので、別に申告する項目はない。

| データの種類 | 収集 | 共有 | 目的 |
| --- | --- | --- | --- |
| 位置情報 → おおよその位置情報(IP アドレスから推定) | はい | はい | 広告やマーケティング、分析、不正防止・セキュリティ・コンプライアンス |
| アプリのアクティビティ → アプリの操作 | はい | はい | 同上 |
| アプリの情報とパフォーマンス → クラッシュ ログ、診断 | はい | はい | 同上 |
| デバイスまたはその他の ID | はい | はい | 同上 |

そのほかの質問への答え

| 質問 | 答え |
| --- | --- |
| データは転送時に暗号化されるか | はい(TLS) |
| 収集は必須か、ユーザーが選べるか | 必須(広告はオフにできない。広告 ID は Android の設定でリセット・削除できる) |
| データの削除をリクエストする方法 | なし(アカウントがなく、開発者はデータを持たない) |

Play Games サービスを有効にしたら、そちらが集めるデータを足す。

## アプリのコンテンツ

Play Console の「アプリのコンテンツ」で答える内容。

| 項目 | 答え |
| --- | --- |
| アプリのアクセス権 | すべての機能を、特別なアクセス権なしで使える(ログインはない) |
| 広告 | 広告あり |
| 広告 ID | 使う。目的は広告、分析、不正防止。`com.google.android.gms.permission.AD_ID` の権限は、広告の SDK がビルド時に自動で足す |
| ターゲット ユーザー | 13歳以上(13〜15歳、16〜17歳、18歳以上)。プライバシーポリシーで13歳未満を対象にしないと書いているため。13歳未満を含めると、ファミリー ポリシーの対象になる |
| 子ども向けに見えるか | いいえ |
| ニュースアプリ、健康、金融機能、政府 | いずれも該当しない |

## コンテンツのレーティング

IARC のアンケートに答える。カテゴリは「ゲーム」。App Store の年齢制限と同じく、暴力などの内容に関する質問にはすべて「いいえ」と答える(抽象的なブロックや弾を壊すだけで、人や生き物への暴力はない)。ユーザー同士のやり取り・位置情報の共有・デジタル商品の購入・ギャンブルもない。結果は IARC 3+(日本では全年齢)になる見込み。
