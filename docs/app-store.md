# App Store 掲載情報

App Store Connect に入力する内容。名前・説明文・キーワードなどの掲載文は fastlane の metadata が正(下の節)。手順は [native-app-spec.md](native-app-spec.md) の第9章にある。文字数の上限は App Store Connect の制限。

## 基本情報

| 項目 | 値 |
| --- | --- |
| 名前 | 言語ごとに `name.txt`(日本語「PARRY BREAK - パリィ×弾幕ブロック崩し」、英語「PARRY BREAK: Brick Breaker」)。ホーム画面の名前は PARRY BREAK のまま |
| バンドル ID | `com.watsuwo.parrybreak` |
| SKU | `parrybreak` |
| プライマリ言語 | 日本語(英語のローカリゼーションも追加する) |
| カテゴリ | ゲーム(サブカテゴリ: アクション、アーケード) |
| 価格 | 無料 |
| 著作権 | 2026 watsuwo |
| プライバシーポリシー URL | https://watsuwo.github.io/parry-break/privacy |
| サポート URL | https://watsuwo.github.io/parry-break/support |
| マーケティング URL | https://watsuwo.github.io/ (AdMob はここに書いたサイトの直下の `app-ads.txt` を見て、アプリを確認する) |

## 名前・説明文・キーワードなど(fastlane の metadata が正)

言語ごとの掲載文は `app/ios/fastlane/metadata/<言語>/` のファイルが正で、`promote` を実行すると審査への提出と一緒に App Store Connect に送られる(`deliver`)。文面を変えるときはこのファイルを直す。App Store Connect で手で直しても、次の `promote` で上書きされる。

| ファイル | 内容 | 上限 |
| --- | --- | --- |
| `name.txt` | 名前 | 30字 |
| `subtitle.txt` | サブタイトル | 30字 |
| `promotional_text.txt` | プロモーション用テキスト(審査なしで差し替えられる) | 170字 |
| `description.txt` | 説明文 | 4000字 |
| `keywords.txt` | キーワード(カンマ区切りで空白を入れない。名前・サブタイトル・カテゴリにある語は入れない) | 100字 |
| `support_url.txt` / `privacy_url.txt` / `marketing_url.txt` | サポート URL / プライバシーポリシー URL / マーケティング URL | |
| `release_notes.txt` | このバージョンの新機能([release-flow.md](release-flow.md) 第5章) | 4000字 |

言語は `ja`(日本語、プライマリ)と `en-US`(英語)。著作権は `metadata/copyright.txt`。

## スクリーンショット

iPad にも対応している(`TARGETED_DEVICE_FAMILY = 1,2`)ため、iPhone と iPad の両方が要る。各サイズで1〜10枚。

| 端末 | サイズ(横画面) | シミュレータの例 |
| --- | --- | --- |
| iPhone 6.9 インチ | 2868 × 1320 | iPhone 18 Pro Max |
| iPhone 6.3 インチ | 2622 × 1206 | iPhone 18 Pro |
| iPad 13 インチ | 2752 × 2064 | iPad Pro 13-inch (M5) |

撮り方: `integration_test/store_screenshots_test.dart` が、シミュレータで実際のアプリを動かして5枚を撮る(ボス戦・崩落・プレイ中・ステージ選択・タイトル。番号は載せる順)。記録は見栄えのよい値を入れた仮のもので、端末の保存データには触らない。

```sh
cd app
open -a Simulator   # 表の3台を起動しておく
SHOT_DIR=build/store_screenshots/ja/iphone flutter drive -d <デバイス ID> --dart-define=lang=ja \
  --driver=test_driver/integration_test.dart --target=integration_test/store_screenshots_test.dart
```

`lang=en` で英語版になり、`-d` に渡す端末の ID でサイズが決まる。6.3 インチの欄は 6.9 インチの画像を受け付けない。縮めるとドット絵がにじむので、端末ごとに撮る。ボス戦はたまに被弾して「HIT!」が写るので、撮ったら目で確かめ、写っていたらその端末だけ撮り直す。PNG は透過の情報を持つので、`sips -s format jpeg` で JPEG にしてから載せる。

## デイリーのランキング(Game Center)

デイリーチャレンジ(DAILY)のボードは、作るまで `LeaderboardConfig.placeholders` に入っていて、スコアを送らない。作る手順:

1. App Store Connect → マイ App → PARRY BREAK → サービス → Game Center → リーダーボード → 「+」で **クラシック** を作る。
2. 参照名 `Daily Score`、ID `com.watsuwo.parrybreak.daily_score`、スコアの形式は整数、並べ方は「大きいほど上位」、スコアの送信の種類は「最高スコア」。一度作った ID は削除しても使い回せない。
3. ローカリゼーションで名前を足す: 日本語「デイリー: スコア」、英語「Daily: Score」。毎日の区切りは、Game Center のランキング画面の「今日」で見てもらう(繰り返しのリーダーボードは使わない)。
4. 次に出すバージョンのページの Game Center 欄で、このリーダーボードを含める。
5. `app/lib/services/leaderboard.dart` の `LeaderboardConfig.ios[Board.dailyScore]` が手順 2 の ID と同じことを確かめ、`placeholders` から `Board.dailyScore` を外す(Android も作るまでは、Android の ID が空のまま送られないよう、両方そろってから外す)。
6. TestFlight で、DAILY を遊んでスコアが「デイリー: スコア」に載ることを確かめる。

## 実績(Game Center)

実績は 21 個(合計 830 点。Game Center の上限は 100 個・1000 点)。作るまで `AchievementConfig.placeholders`(`app/lib/services/achievements.dart`)に全部入っていて、解除を送らない。作る手順:

1. App Store Connect → マイ App → PARRY BREAK → サービス → Game Center → 実績 →「+」で、下の表の 1 つにつき 1 つ作る。
2. 参照名は英語の名前、ID は `com.watsuwo.parrybreak.ach_` + 表の「ID の末尾」(例: `com.watsuwo.parrybreak.ach_firstJust`)、点数は表のとおり。隠し実績にはしない。繰り返しの実績にもしない。
3. ローカリゼーションで日本語・英語の名前と、獲得前・獲得後の説明(どちらも表の説明)を入れる。画像(1024 × 1024)も要る。
4. 次に出すバージョンのページの Game Center 欄で、実績を含める。
5. `AchievementConfig.ios` の ID が手順 2 と同じことを確かめ、できた実績を `placeholders` から外す。Android も作るまでは、Android の ID が空のまま送られないよう、両方そろってから外す。
6. TestFlight で、条件を満たしてストアの実績に出ることと、タイトルの RANKING → ACHIEVEMENTS で画面が開くことを確かめる(1 つでも外すと入口が出る)。

| 名前(日本語) | 名前(英語) | 説明(日本語) | 説明(英語) | 点数 | ID の末尾 |
| --- | --- | --- | --- | --- | --- |
| 初めての PERFECT | First PERFECT | パリィを PERFECT 以上で決める | Land a parry rated PERFECT or better. | 10 | `firstPerfect` |
| 初めての JUST | First JUST | パリィを JUST で決める | Land a JUST parry. | 10 | `firstJust` |
| 初めての撃ち返し | First Return | 敵の弾をパリィで撃ち返す | Parry an enemy bullet back. | 10 | `firstReturn` |
| 初めての FEVER TIME | First FEVER TIME | FEVER TIME に入る | Trigger FEVER TIME. | 10 | `firstFever` |
| ジャストの達人 | JUST Adept | 1 プレイで JUST を 10 回決める | Land 10 JUST parries in one run. | 30 | `just10` |
| ノーミスパリィ | Flawless Parry | パリィを 30 連続で成功させる | Land 30 parries in a row. | 40 | `parry30` |
| 大崩落 | Great Collapse | COLLAPSE を ×30 以上つなげる | Chain a COLLAPSE of 30 or more. | 40 | `collapse30` |
| 跳弾の名手 | Ricochet Master | RICOCHET ×20 を決める | Hit a RICOCHET x20. | 40 | `ricochet20` |
| 紙一重 | Close Call | 1 ラウンドでグレイズを 20 回決める | Graze 20 times in one round. | 30 | `graze20` |
| 第 1 章クリア | Chapter 1 Clear | 第 1 章の全ステージをクリアする | Clear every stage in Chapter 1. | 20 | `chapter1` |
| 第 2 章クリア | Chapter 2 Clear | 第 2 章の全ステージをクリアする | Clear every stage in Chapter 2. | 20 | `chapter2` |
| 第 3 章クリア | Chapter 3 Clear | 第 3 章の全ステージをクリアする | Clear every stage in Chapter 3. | 30 | `chapter3` |
| 第 4 章クリア | Chapter 4 Clear | 第 4 章の全ステージをクリアする | Clear every stage in Chapter 4. | 30 | `chapter4` |
| 第 5 章クリア | Chapter 5 Clear | 第 5 章の全ステージをクリアする | Clear every stage in Chapter 5. | 40 | `chapter5` |
| 第 6 章クリア | Chapter 6 Clear | 第 6 章の全ステージをクリアする | Clear every stage in Chapter 6. | 50 | `chapter6` |
| 星をすべて集める | Every Star | 全ステージの星をすべて取る | Earn every star in every stage. | 100 | `allStars` |
| R20 到達 | Reach R20 | エンドレスで R20 に到達する | Reach R20 in Endless. | 30 | `endlessR20` |
| R60 到達 | Reach R60 | エンドレスで R60(1 周)に到達する | Reach R60 (one full loop) in Endless. | 60 | `endlessR60` |
| ミリオン | Millionaire | エンドレスの 1 プレイで 1,000,000 点を取る | Score 1,000,000 in one Endless run. | 100 | `score1m` |
| ノーダメージ撃破 | Untouchable | ボスを被弾なしで倒す | Defeat a boss without taking a hit. | 60 | `bossNoHit` |
| HARD クリア | HARD Clear | HARD でステージをクリアする | Clear a stage on HARD. | 70 | `hardClear` |

1 プレイで決まるもの(手ほどき・技・エンドレス・ボス)は条件を満たした瞬間に、進行(章・星・HARD)はクリアの時点で解除する。解除済みは端末の `achievements.unlocked.v1` に、送れていない分は `achievements.pending.v1` に保存し、次のサインインで送る。実績を足す前に取った星・クリアは、サインインのたびに見直して解除する。デバッグモードと練習場では解除しない。

## App のプライバシー

開発者自身は何も集めないが、広告(Google AdMob)と同意画面(UMP)の SDK がデータを集めるため、「データの収集なし」は選べない。下の表は、ビルドに入っている両 SDK のプライバシーマニフェスト(`GoogleMobileAds.framework` と `UserMessagingPlatform.framework` の `PrivacyInfo.xcprivacy`)をまとめたもの。SDK を更新したら、マニフェストを見直して表も直す。

| データの種類 | 用途 | ユーザーに関連付け | トラッキング |
| --- | --- | --- | --- |
| 位置情報 → おおよその場所 | 他社の広告、デベロッパの広告、分析、App の機能 | はい | いいえ |
| ID → デバイス ID | 他社の広告、デベロッパの広告、分析 | はい | **はい** |
| 使用状況データ → 製品の操作 | 他社の広告、デベロッパの広告、分析、App の機能 | はい | いいえ |
| 使用状況データ → 広告データ | 他社の広告、デベロッパの広告、分析 | はい | いいえ |
| 診断 → クラッシュデータ | 分析 | いいえ | いいえ |
| 診断 → パフォーマンスデータ | 他社の広告、デベロッパの広告、分析、App の機能 | いいえ | いいえ |
| 診断 → その他の診断データ | 他社の広告、デベロッパの広告、分析 | いいえ | いいえ |

`Info.plist` に `NSUserTrackingUsageDescription` があるので、デバイス ID の「トラッキング」を「はい」にしないと提出できない。ランキングは Apple の Game Center が扱うため、申告に含めない。

## 年齢制限

内容に関する質問(暴力など)にはすべて「なし」と答える(抽象的なブロックや弾を壊すだけで、人や生き物への暴力はない)。機能の質問では「広告」を「あり」にする。ユーザー生成コンテンツ・メッセージ・課金はない。結果は 4+ になる見込み。プライバシーポリシーで13歳未満を対象にしないと書いているため、「キッズ」カテゴリは選ばない。

## 審査メモ(App Review への情報)

App Store Connect の「App Review に関する情報」のメモに、人が下の英文を貼る(`promote` では送られない)。広告の出し方(`app/lib/services/ads.dart` の `InterstitialPolicy`)や操作方法(`app/lib/services/settings.dart` の `ControlScheme`)を変えたら、この文も実装に合わせて直し、貼り直す。

```
No account or login is required. Game Center is used only for leaderboards; the game is fully playable without signing in.

The game is landscape only. By default, drag on the left half of the screen to move the paddle, and tap the right half to launch the ball and parry. In Settings > CONTROLS, the controls can be switched to a rail (horizontal or vertical) on the left that moves the paddle, with a PARRY button on the right that launches the ball and parries. Chapter 1 of Stage mode is a tutorial.

The app shows interstitial ads (Google AdMob) only when the player returns from the results screen to the title or stage select, never during play. On the first launch, shortly after the title screen is shown, the app shows the GDPR consent form (EEA/UK only) and then the App Tracking Transparency prompt. The ATT prompt appears before the ad SDK is initialized, so no tracking data is collected before the user responds. A screen recording of this flow on a physical device is attached. Ads themselves are not shown until the player has seen the results screen three times. From the fourth results screen on, an ad can be shown when returning to the title or stage select (at least 3 minutes apart, and at most 8 times a day); choosing RETRY or NEXT STAGE never shows an ad. To see an ad: finish four rounds in Endless or Stage mode (a game over is fine), and on the fourth results screen tap TITLE. If a review request appears instead (after clearing a stage with all three stars), dismiss it and finish one more round. Tracking permission can be changed in the iOS Settings app; in regions that require consent (EEA/UK), an "Ad privacy settings" item also appears in the app's Settings.

There is a hidden debug mode for development (tap "VER" at the bottom right of the title screen three times). It unlocks all stages, and scores in this mode are not saved or submitted to leaderboards. Ads are not shown and results are not counted toward the ad grace period while it is on, so turn it off before checking ads. It can be turned off in Settings.
```

## 輸出コンプライアンス

`Info.plist` の `ITSAppUsesNonExemptEncryption = false` で申告済み。アップロード時に質問されない。
