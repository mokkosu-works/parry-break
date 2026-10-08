# Play Store 掲載情報

Google Play Console に入力する内容の下書き。署名とビルドの手順は [native-app-spec.md](native-app-spec.md) の 9.4 にある。文字数の上限は Play Console の制限。iOS の掲載情報は [app-store.md](app-store.md) にあり、説明文はそれをもとに Android 向けに直した。

## 基本情報

| 項目 | 値 |
| --- | --- |
| アプリ名 | PARRY BREAK |
| パッケージ名 | `com.watsuwo.parrybreak`(一度アップロードすると変えられない) |
| デフォルトの言語 | 日本語(英語の翻訳も追加する) |
| アプリかゲームか | ゲーム |
| カテゴリ | アーケード |
| タグ | アーケード、アクション、ブロック崩し などから最大5つ |
| 価格 | 無料 |
| 連絡先のメールアドレス | (未定。ストアに公開されるので、このアプリ用のアドレスを用意する) |
| プライバシーポリシー URL | https://watsuwo.github.io/parry-break/privacy |
| ウェブサイト | https://watsuwo.github.io/parry-break/support |

App Store にあるサブタイトル・プロモーション用テキスト・キーワードは、Play Store にはない。代わりに「簡単な説明」がある。

## 日本語

**簡単な説明**(80字以内。ストアのページで最初に見える。App Store のプロモーション用テキストと同じ)

```
パリィで攻めて撃破せよ！一つのボールで挑む、シンプル操作の高難易度ブロック崩し。
```

**詳しい説明**(4000字以内)

App Store の説明文から、Game Center の行を消した。Android のランキング(Play Games サービス)を有効にしたら、「・Google Play ゲームズのランキングに対応しています」を足す。

```
PARRY BREAK は、ブロック崩しの「受けて守る」パドルを「弾いて攻める」武器に変えた、アーケード型のスコアアタックです。

■ 当たる瞬間に弾く
ボールや敵弾がパドルに当たる瞬間に画面の右半分をタップすると、パリィになります。タイミングが PERFECT なら貫通弾、JUST なら衝撃波。撃ち返した敵弾は、最大の得点源になります。

■ 攻めるほど点が伸びる
ジャストパリィや撃ち返しでヒートが上がり、倍率が跳ね上がります。最高段階で発動する OVERDRIVE では、ボールがブロックを次々と貫き、パリィのたびに分身弾が飛び出します。安全に受けるだけでは点になりません。

■ 崩落と誘爆
白い要石を壊すと、支えを失ったブロックがまとめて崩れ落ちます。オレンジの爆薬は周りを巻き込んで誘爆します。一撃で盤面をひっくり返す連鎖を狙ってください。

■ 2つのモード
・エンドレス: 60ウェーブとその先のループに挑むスコアアタック。10ウェーブごとにボス要塞が待ち受けます。
・ステージ: 1面1〜2分の短いステージを、星3つの評価で攻略します。第1章は基本を覚えるチュートリアルです。

■ ボール1個、ミスは即ゲームオーバー
コンティニューはありません。ボールを落とすか、ブロックが警告線まで下りてきたら終わりです。

■ 遊びやすさ
・左半分ドラッグで移動、右半分タップでパリィ。操作レール方式にも切り替えられます
・端末に合わせて判定タイミングを測定・補正できます
・フラッシュや画面の揺れを抑える設定があります
・広告はプレイ中には出ません。課金はありません
```

## English

**Short description** (80 characters)

App Store の Promotional text は 92 字で上限を超えるため、「and destroy」を削って 80 字にした。

```
Parry to attack! One ball, simple controls, and a seriously tough block breaker.
```

**Full description** (4000 characters)

```
PARRY BREAK turns the block-breaker paddle from a shield into a weapon. An arcade score attack where you parry instead of just catching.

- PARRY ON IMPACT
Tap the right half of the screen just as the ball or a bullet hits your paddle. PERFECT timing fires a piercing shot; JUST releases a shockwave. Every bullet you send back is a chance for big points.

- RISK PAYS
Parries and returned bullets build up your Heat and your multiplier. Max it out to trigger OVERDRIVE: your ball tears through blocks, and every parry splits off clone balls. Playing safe won't get you far.

- COLLAPSE AND CHAIN BLASTS
Break a white keystone and every block it was holding comes crashing down. Orange explosives take their neighbours with them. Find the chain that flips the whole board.

- TWO MODES
Endless: Survive 60 waves and the loop beyond, with a boss fortress every 10 waves.
Stages: Short 1-2 minute stages rated with up to three stars. Chapter 1 teaches the basics.

- ONE BALL, NO CONTINUES
Drop the ball or let the blocks reach the warning line and it's over.

- BUILT TO PLAY WELL
- Drag on the left half to move, tap the right half to parry, or switch to rail controls
- Calibrate the timing offset to your device
- Reduce flashing and screen shake in Settings
- Ads never interrupt a run. No in-app purchases
```

Play Games サービスを有効にしたら、`- Google Play Games leaderboards` を足す。

## 画像

| 種類 | サイズ | 枚数 | 用意するもの |
| --- | --- | --- | --- |
| アプリのアイコン | 512 × 512、PNG(32 ビット) | 1 | `app/branding/icons/icon-512.png`。いまは透過なしの PNG なので、受け付けられなければ透過ありで書き出し直す |
| フィーチャー グラフィック | 1024 × 500、JPEG か 24 ビット PNG(透過なし) | 1 | **未作成**。ストアのページの一番上に出る横長の画像 |
| スマートフォンのスクリーンショット | 長い辺が短い辺の2倍以内、320〜3840 px | 2〜8 | 下の手順で 1920 × 1080 を5枚撮る。ゲームは横画面で 1920 × 1080 以上を4枚以上にすると、おすすめに載りやすい |

### スクリーンショット

App Store と同じ `integration_test/store_screenshots_test.dart` を、Android のエミュレーターで動かして5枚を撮る(iPhone 用は縦横比が 2:1 を超えるので Play Store には使えない)。エミュレーターは画面 1080 × 1920(横にすると 1920 × 1080)のものを使う。

```sh
cd app
flutter emulators --launch <エミュレーター ID>
SHOT_DIR=build/store_screenshots/ja/android flutter drive -d <デバイス ID> --no-enable-impeller --dart-define=lang=ja \
  --driver=test_driver/integration_test.dart --target=integration_test/store_screenshots_test.dart
```

- `--no-enable-impeller` は外さない。標準の描画エンジン(Impeller)のままだと、しばらく動かしたところでエミュレーターごと落ちる(WSL のエミュレーターで確認)。
- `lang=en` で英語版になる。PNG のまま載せてよい。

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
