# App Store 掲載情報

App Store Connect に入力する内容の下書き。手順は [native-app-spec.md](native-app-spec.md) の第9章にある。文字数の上限は App Store Connect の制限。

## 基本情報

| 項目 | 値 |
| --- | --- |
| 名前 | PARRY BREAK |
| バンドル ID | `com.watsuwo.parrybreak` |
| SKU | `parrybreak` |
| プライマリ言語 | 日本語(英語のローカリゼーションも追加する) |
| カテゴリ | ゲーム(サブカテゴリ: アクション、アーケード) |
| 価格 | 無料 |
| 著作権 | 2026 watsuwo |
| プライバシーポリシー URL | https://watsuwo.github.io/parry-break/privacy |
| サポート URL | https://watsuwo.github.io/parry-break/support |
| マーケティング URL | なし(任意) |

## 日本語

**サブタイトル**(30字以内)

```
弾いて壊す、パリィ×ブロック崩し
```

**プロモーション用テキスト**(170字以内、審査なしで差し替えられる)

```
ボールも敵弾も、当たる瞬間に弾き返せ。タイミングが完璧なら貫通弾、ジャストなら衝撃波。安全策では点が伸びない、攻めるほど倍率が跳ね上がるスコアアタック。
```

**説明文**(4000字以内)

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
・Game Center のランキングに対応しています
・広告はプレイ中には出ません。課金はありません
```

**キーワード**(100字以内、カンマ区切り。名前とカテゴリの語は入れない)

```
ブロック崩し,パリィ,弾幕,スコアアタック,シューティング,高難度,反射神経,リズム,ブレイクアウト,ボス
```

## English

**Subtitle** (30 characters)

```
Parry, break, survive
```

**Promotional text** (170 characters)

```
Hit back the ball and enemy bullets the instant they land. PERFECT fires a piercing shot, JUST a shockwave. Play it safe and your score stalls. Take risks and it soars.
```

**Description** (4000 characters)

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
- Game Center leaderboards
- Ads never interrupt a run. No in-app purchases
```

**Keywords** (100 characters, comma separated)

```
breakout,brick breaker,parry,bullet hell,arcade,score attack,shooter,hardcore,reflex,boss,timing
```

## スクリーンショット

iPad にも対応している(`TARGETED_DEVICE_FAMILY = 1,2`)ため、iPhone と iPad の両方が要る。各サイズで1〜10枚。

| 端末 | サイズ(横画面) | シミュレータの例 |
| --- | --- | --- |
| iPhone 6.9 インチ | 2868 × 1320 | iPhone 18 Pro Max |
| iPad 13 インチ | 2752 × 2064 | iPad Pro 13-inch (M5) |

撮り方:

```sh
open -a Simulator              # File → Open Simulator で上の端末を選ぶ
cd app && flutter run -d <デバイス ID>
xcrun simctl io booted screenshot ~/Desktop/parrybreak-01.png   # Simulator で ⌘S でもよい
```

- デバッグモードでは左下に DEBUG の帯が出るため、通常モードで撮る
- 候補: タイトル、PERFECT の瞬間、OVERDRIVE 中、大崩落・誘爆、ボス戦、ステージ選択

## App のプライバシー

開発者自身は何も集めないが、広告(Google AdMob)の SDK がデータを集めるため、「データの収集なし」は選べない。Google が公開している開示内容([Data disclosure for Apple's App Store](https://developers.google.com/admob/ios/privacy/data-disclosure))に合わせて入力する。入力の時点で、このページの最新の内容を確かめること。目安は次のとおり。

| データの種類 | 用途 | ユーザーとの関連付け | トラッキング |
| --- | --- | --- | --- |
| 位置情報 → おおよその場所 | 他社の広告、分析 | なし | なし |
| ID → デバイス ID(IDFA) | 他社の広告、分析 | なし | **あり**(ATT で許可された場合) |
| 使用状況データ → 製品の操作、広告データ | 他社の広告、分析 | なし | なし |
| 診断 → クラッシュデータ、パフォーマンスデータ、その他の診断データ | 他社の広告、分析 | なし | なし |

ランキングは Apple の Game Center が扱うため、申告に含めない。

## 年齢制限

内容に関する質問(暴力など)にはすべて「なし」と答える(抽象的なブロックや弾を壊すだけで、人や生き物への暴力はない)。機能の質問では「広告」を「あり」にする。ユーザー生成コンテンツ・メッセージ・課金はない。結果は 4+ になる見込み。プライバシーポリシーで13歳未満を対象にしないと書いているため、「キッズ」カテゴリは選ばない。

## 審査メモ(App Review への情報)

```
No account or login is required. Game Center is used only for leaderboards; the game is fully playable without signing in.

The game is landscape only. Drag on the left half of the screen to move the paddle, and tap the right half to launch the ball and parry. Chapter 1 of Stage mode is a tutorial.

The app shows interstitial ads (Google AdMob) only when the player returns from the results screen to the title or stage select, never during play. The App Tracking Transparency prompt (and the GDPR consent form in the EEA/UK) appears on the first launch, shortly after the title screen is shown. Ads themselves are not shown during the first 24 hours after the first launch, so you may not see an ad during review. Tracking permission can be changed in the iOS Settings app; in regions that require consent (EEA/UK), an "Ad privacy settings" item also appears in the app's Settings.

There is a hidden debug mode for development (tap "VER" at the bottom right of the title screen three times). It unlocks all stages, and scores in this mode are not saved or submitted to leaderboards. It can be turned off in Settings.
```

## 輸出コンプライアンス

`Info.plist` の `ITSAppUsesNonExemptEncryption = false` で申告済み。アップロード時に質問されない。
