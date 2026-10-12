# App Store 掲載情報

App Store Connect に入力する内容。名前・説明文・キーワードなどの掲載文は fastlane の metadata が正(下の節)。手順は [native-app-spec.md](native-app-spec.md) の第9章にある。文字数の上限は App Store Connect の制限。

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
| マーケティング URL | https://watsuwo.github.io/ (AdMob はここに書いたサイトの直下の `app-ads.txt` を見て、アプリを確認する) |

## 名前・説明文・キーワードなど(fastlane の metadata が正)

言語ごとの掲載文は `app/ios/fastlane/metadata/<言語>/` のファイルが正で、`promote` を実行すると審査への提出と一緒に App Store Connect に送られる(`deliver`)。文面を変えるときはこのファイルを直す。App Store Connect で手で直しても、次の `promote` で上書きされる。

| ファイル | 内容 | 上限 |
| --- | --- | --- |
| `name.txt` | 名前 | 30字 |
| `subtitle.txt` | サブタイトル | 30字 |
| `promotional_text.txt` | プロモーション用テキスト(審査なしで差し替えられる) | 170字 |
| `description.txt` | 説明文 | 4000字 |
| `keywords.txt` | キーワード(カンマ区切り。名前とカテゴリの語は入れない) | 100字 |
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

```
No account or login is required. Game Center is used only for leaderboards; the game is fully playable without signing in.

The game is landscape only. Drag on the left half of the screen to move the paddle, and tap the right half to launch the ball and parry. Chapter 1 of Stage mode is a tutorial.

The app shows interstitial ads (Google AdMob) only when the player returns from the results screen to the title or stage select, never during play. On the first launch, shortly after the title screen is shown, the app shows the GDPR consent form (EEA/UK only) and then the App Tracking Transparency prompt. The ATT prompt appears before the ad SDK is initialized, so no tracking data is collected before the user responds. A screen recording of this flow on a physical device is attached. Ads themselves are not shown during the first 24 hours after the first launch, so you may not see an ad during review. Tracking permission can be changed in the iOS Settings app; in regions that require consent (EEA/UK), an "Ad privacy settings" item also appears in the app's Settings.

There is a hidden debug mode for development (tap "VER" at the bottom right of the title screen three times). It unlocks all stages, and scores in this mode are not saved or submitted to leaderboards. It can be turned off in Settings.
```

## 輸出コンプライアンス

`Info.plist` の `ITSAppUsesNonExemptEncryption = false` で申告済み。アップロード時に質問されない。
