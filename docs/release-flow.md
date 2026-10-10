# ブランチとリリースの運用(CI/CD・Claude による自動化)

iOS / Android のストアへ、小さな更新を続けて出すための運用を定める。人が判断する場面を **4つ**(`dev` 向けの PR の Approve、リリース PR のマージ、実機での確認、本番への昇格)に絞り、実装・テスト・レビューは CI と Claude に任せる。

```
Issue を書く ─▶ @claude とコメント ─▶ 🤖 実装・テスト・エミュレーターで確認 ─▶ 🤖 PR ─▶ ⚙️🤖 チェック・e2e・レビュー ─▶ 🧑 Approve ─▶ dev
```

## 1. ブランチ

```
claude/issue-* ─┐
feature/*      ─┼─PR (CI・エミュレーター・Claude のレビューが通り、人が Approve したらマージ)─▶ dev
fix/*          ─┘
dev ──▶ release/vX.Y.Z ─PR (人がマージ)─▶ main ──▶ ストアへテスト配信
                                           │
                                           └─(自動)─▶ dev に戻す
hotfix/* ─PR (人がマージ)─▶ main
```

| ブランチ | 役割 | 入れ方 |
| --- | --- | --- |
| `main` | ストアに出したもの。**ここに入る = リリース** | `release/*`・`hotfix/*` の PR を人がマージする。直接 push しない |
| `dev` | 次のリリースに入れる変更をためる。GitHub の既定のブランチ | `claude/issue-*`・`feature/*`・`fix/*` の PR を、人が Approve するとマージされる。直接 push しない |
| `claude/issue-<番号>` | Issue から Claude が実装したもの | `implement.yml` が `dev` から切り、Claude が `dev` に PR を出す |
| `feature/*` / `fix/*` | 機能の追加 / 不具合の修正(人が手元で作る) | `dev` から切り、`dev` に PR を出す |
| `release/vX.Y.Z` | バージョン名とストアの文面を更新する | `/release` が `dev` から切り、`main` に PR を出す |
| `hotfix/X.Y.Z` | 出ているバージョンの緊急の修正 | `main` から切り、`main` に PR を出す(第7章) |

| 項目 | 決定 |
| --- | --- |
| `dev` へのマージ | squash(PR 1つ = コミット 1つ)。マージ後にブランチを消す |
| `main` へのマージ | **Create a merge commit**。squash にすると `dev` と履歴がずれる |
| `main` から `dev` へ | `main` に入ったら `sync-dev.yml` が自動で `dev` にマージする。衝突したら手で直す |
| ブランチの保護 | 非公開リポジトリの無料プランでは使えない。`main` / `dev` に直接 push しないことは約束で守る。`dev` へのマージは、Approve を確かめてワークフロー(`pr.yml`・`merge.yml`)が行う |
| 未完成の機能 | `dev` に入れてよいが、ユーザーに見せない(ステージは JSON から外す、機能は設定値で無効にする)。リリースを止めないため |
| タグ | `vX.Y.Z`。テスト配信に成功したときに CI が付ける |
| ビルド番号 | CI が `release.yml の実行番号 + 100` を付ける。iOS と Android で同じ番号。`pubspec.yaml` の `+` の後ろは手元のビルド用で、ストアには使わない |
| ストアの公開 | iOS は段階的リリース(7日かけて全員へ。問題があれば止められる)。Android は最初から全員に公開する(止められないので、問題があれば修正版を出す) |

### `dev` へのマージ

`dev` 向けの PR は、次がすべてそろうと squash でマージされる(条件は `.github/scripts/merge-if-approved.sh`)。Approve とチェックのどちらが先に終わってもよい。

- `pr.yml` の `check`(analyze・単体テスト)・`e2e`(Android エミュレーターでのスモークテスト)・`review`(Claude のレビュー)が成功している
- **人(OWNER / MEMBER / COLLABORATOR)が、いまの先頭のコミットを Approve している**。Approve のあとに push されたら(Claude が指摘を直したときなど)、Approve し直す
- 下書き(draft)ではなく、`hold` / `needs-fix` のラベルが付いていない

Approve するときに見るもの: Claude のレビューの所見(最後のコメント)、PR の本文の「完了条件」「エミュレーターで確かめたこと」「確かめられなかったこと」、撮った画面(本文のリンク先の Artifacts)。コードを細かく読む必要はない。

| 場面 | どうなるか |
| --- | --- |
| `needs-fix` が付いた | Claude のレビューが直すべき問題を見つけた。`pr.yml` の `fix` で Claude が指摘を 1 つずつ確かめ、妥当なものを直して push する。再レビューで問題がなければ外れるので、そのあと Approve する。妥当でないと判断した指摘には、スレッドに理由が返る(`needs-fix` は付いたまま)。読んで納得すればラベルを外して Approve、直すなら `@claude 指摘を直して` とコメントする |
| 自動修正が止まった | 続けての自動修正は 2 回まで(人が push すると数え直す)。それでも `[要修正]` が残れば止まってコメントする。`@claude` で頼むか手で直す |
| ラベルを外した | 自動では再実行されない。Approve し直す(すでに Approve していても、もう一度 Approve すればよい) |
| 自分で作った PR | GitHub の決まりで、作者は自分の PR を Approve できない。チェックがすべて通ったのを見て、PR の画面で **Squash and merge** を押す |
| Issue から作った PR が下書き | Claude がエミュレーターでの確認や完了条件を満たせなかった、または PR を作らずに終わった(ワークフローが代わりに作る)。本文の先頭に理由がある。直してほしいことを `@claude` でコメントするか、閉じる |

### バージョン名の上げ方

| 変更 | 上げる桁 | 例 |
| --- | --- | --- |
| 不具合の修正、調整、文言の修正 | パッチ | 1.2.0 → 1.2.1 |
| ステージ・章・モード・設定の追加など、遊べる内容が増える | マイナー | 1.2.0 → 1.3.0 |
| 保存データの互換がなくなる、ゲームの根本が変わる | メジャー | 1.2.0 → 2.0.0 |

Claude が `/release` のときに前回のタグからのコミットを読んで決め、PR に理由を書く。人は PR で直せる。

## 2. ワークフロー

| ワークフロー | きっかけ | 内容 |
| --- | --- | --- |
| `check.yml` | 下の2つから呼ぶ | `flutter analyze`、`flutter test` |
| `implement.yml` | Issue のコメントの `@claude` | Android エミュレーターを起動し、Claude が Issue を実装・テストし、エミュレーターで確かめて `dev` 向けの PR を作る(`.claude/skills/implement-issue/SKILL.md`)。撮った画面は実行の Artifacts に残る |
| `pr.yml` | PR の作成・更新 | チェック、エミュレーターでのスモークテスト(`e2e`、`integration_test/smoke_test.dart`)、Claude のレビュー。`dev` 向けで `needs-fix` が付けば、Claude が指摘を確かめて妥当なものを直す(`fix`)。`dev` 向けで、すべて通って人が Approve 済みなら squash でマージする |
| `merge.yml` | `dev` 向けの PR の Approve | `pr.yml` のジョブがすべて通っていれば squash でマージする |
| `claude.yml` | PR のコメントの `@claude` | Claude が依頼に応える(レビューの指摘の修正など) |
| `release.yml` | `main` への push(手動実行も可) | バージョン名のタグがまだなければ、チェックのあと両 OS をビルドしてテスト配信し、タグと GitHub Release を作る |
| `sync-dev.yml` | `main` への push | `main` を `dev` にマージする |
| `promote.yml` | 手動実行 | テスト配信中のビルドを本番に出す(iOS は審査に提出、Android は全員に公開) |

`release.yml` は、リポジトリの変数 `IOS_RELEASE` / `ANDROID_RELEASE` が `true` の OS だけを動かす。準備ができていない OS は `true` にしない(第8章)。

## 3. リリースサイクルごとにやること

**担当**: 🤖 Claude / ⚙️ CI / 🧑 人

| # | いつ | 担当 | やること |
| --- | --- | --- | --- |
| 1 | 開発中(随時) | 🧑 | Issue をテンプレートで書き、`@claude` とコメントする |
| 1' | 〃 | 🤖 | `implement.yml`: Claude が実装・テストし、Android エミュレーターで確かめて `dev` に PR を出す(人が手元で `feature/*` を作って PR を出してもよい) |
| 2 | 〃 | ⚙️🤖 | `pr.yml`: チェック、エミュレーターでのスモークテスト、Claude のレビュー |
| 2' | 〃 | 🧑 | レビューの所見と PR の本文を見て Approve する(**人の判断**: 変更ごと)。`dev` にマージされる |
| 3 | 出したい変更がたまったら(目安: 2週間に1回、または不具合の修正後すぐ) | 🧑 | Claude Code で `/release` を実行する(定期実行にもできる、第6章) |
| 4 | 〃 | 🤖 | 前回のタグからの変更を集め、バージョン名を決める。`dev` から `release/vX.Y.Z` を切り、`app/pubspec.yaml` の `version` を上げる |
| 5 | 〃 | 🤖 | ストアの「このバージョンの新機能」を日本語・英語で書く(第5章のファイル) |
| 6 | 〃 | 🤖 | 掲載文(App Store は `app/ios/fastlane/metadata/`、Google Play は [play-store.md](play-store.md))・スクリーンショット・ドキュメントの更新が要るか調べ、要るものは直す。ストア側で人がやる作業があれば、PR のチェックリストに挙げる |
| 7 | 〃 | 🤖 | `main` に向けたリリース PR を作る。Claude のレビューも付く |
| 8 | リリース PR | 🧑 | 新機能の文面とバージョン名を確認して、**Create a merge commit** でマージする(**人の判断 1**) |
| 9 | マージ直後 | ⚙️ | `release.yml`: Android を Play の内部テストに、iOS を TestFlight に上げ、`vX.Y.Z` のタグと GitHub Release を作る。`sync-dev.yml`: `main` を `dev` に戻す |
| 10 | 配信後(30分ほど) | 🧑 | 実機で第8章の確認をする(**人の判断 2**)。だめなら `fix/*` で直し、手順 3 からパッチでやり直す |
| 11 | 確認後 | 🧑 | Actions → `promote` を実行する(**人の判断 3**) |
| 12 | 〃 | ⚙️ | iOS: 新機能の文面を入れて審査に提出する(承認されたら自動で段階的リリース)。Android: 本番トラックに昇格し、全員に公開する |
| 13 | 審査で却下されたら | 🤖🧑 | App Store Connect の却下理由を Claude に貼る。Claude が原因を調べ、修正の PR か返信の下書きを作る |

人の作業は、変更ごとに **Issue を書く・Approve**、リリース1回あたり **PR のマージ・実機確認・ボタン1回**。

## 4. ストアの公開状況とタグ

`main` に入ってもストアに出たとは限らない。どこまで進んだかは次で見る。

| 段階 | 見る場所 |
| --- | --- |
| テスト配信した | GitHub の Releases(`vX.Y.Z`。本文にビルド番号と配信先) |
| 審査中・公開中 | App Store Connect / Play Console |

`main` に、バージョン名を上げずにドキュメントだけの変更が入っても、`release.yml` はタグがあるので何もしない。

## 5. ストアの文面の置き場所

| ファイル | 内容 | 上限 |
| --- | --- | --- |
| `app/ios/fastlane/metadata/ja/release_notes.txt` | App Store「このバージョンの新機能」(日本語) | 4000字 |
| `app/ios/fastlane/metadata/en-US/release_notes.txt` | 同(英語) | 4000字 |
| `app/android/fastlane/metadata/android/ja-JP/changelogs/default.txt` | Google Play「リリースノート」(日本語) | 500字 |
| `app/android/fastlane/metadata/android/en-US/changelogs/default.txt` | 同(英語) | 500字 |

App Store の名前・説明文・キーワード・URL などの掲載文は `app/ios/fastlane/metadata/<言語>/` が正で、`promote` で新機能の文面と一緒に送る([app-store.md](app-store.md))。Google Play の掲載文は、いまは [play-store.md](play-store.md) を正として手で入力する。

## 6. Claude による自動化

| 場面 | 仕組み | 内容 |
| --- | --- | --- |
| Issue の実装 | `implement.yml`(Issue に `@claude` とコメント)+ `.claude/skills/implement-issue/SKILL.md` | 実装・単体テスト・Android エミュレーターでの確認(スモークテストと、完了条件を確かめる `integration_test/<確かめる内容>_test.dart`、撮った画面を Claude が見る)をして、`dev` 向けの PR を作る。「先に聞いてほしい」項目が残っていれば、実装せずに Issue で質問する。手元でも `/implement-issue <番号>` で同じことができる |
| PR のレビュー | `pr.yml`(`anthropics/claude-code-action`)+ `.claude/skills/pr-review/SKILL.md` | 不具合・テストの漏れ・設計書との食い違い・完了条件を満たしているかを見る。直すべき問題があれば `needs-fix` を付けて、マージを止める。観点と重さの基準はスキルに書く。手元でも `/pr-review <番号>` で同じレビューができる |
| 指摘の自動修正 | `pr.yml` の `fix` + `.claude/skills/pr-fix/SKILL.md` | `needs-fix` が付いたら、`[要修正]` の指摘を 1 つずつ確かめる(コードを追う・落ちるテストを書く)。妥当なものだけ直してコミットし、ワークフローが `flutter analyze` / `flutter test` を通してから Claude の GitHub アプリのトークンで push する(再レビューが動く)。妥当でない・人の判断が要る指摘は、スレッドに理由を返して人に回す。続けて 2 回まで。`main` 向けの PR では動かない。手元でも `/pr-fix <番号>` で同じことができる |
| PR での依頼 | `claude.yml`(PR に `@claude` を付けてコメント) | 指摘の修正 |
| リリース準備 | `.claude/skills/release/SKILL.md`(`/release`) | 第3章の手順 4〜7。Claude Code(ターミナル・Web・アプリ)で実行する |
| リリース準備の定期実行 | Claude Code のルーティン(claude.ai/code の Routines) | 例: 隔週の月曜に `/release` を実行する。前回のタグから出す価値のある変更がなければ何もしない |
| 審査の却下・CI の失敗 | Claude Code で依頼 | 却下理由やログを渡すと、原因を調べて修正の PR を作る |

リリース準備を GitHub Actions ではなく Claude Code で動かすのは、Actions の `GITHUB_TOKEN` で作った PR では CI が動かないため。Claude Code ならユーザーとして PR を作るので、CI と Claude のレビューがそのまま動く。`implement.yml` は Actions の中で動くが、PR を `GITHUB_TOKEN` ではなく Claude の GitHub アプリのトークンで作る(作者は `claude[bot]`)ので、CI が動く。作者が自分でないので、Approve もできる。

## 7. ホットフィックス

`dev` に、まだ出せない変更が入っているときに使う。`dev` がそのまま出せるなら、`fix/*` → `dev` → `/release`(パッチ)の通常の流れでよい。

1. `git switch -c hotfix/1.2.1 origin/main`
2. 修正し、`app/pubspec.yaml` のバージョン名をパッチで上げ、ストアの文面(第5章)を書く。`main` に PR を出す。
3. 人がマージする。その後は通常と同じ(`release.yml` → 実機確認 → `promote`)。
4. `sync-dev.yml` が修正を `dev` に戻す。衝突したら、手で `main` を `dev` にマージする。

## 8. 実機での確認(テスト配信のあと)

TestFlight / Play の内部テストから入れて、次を確かめる(10分ほど)。

- 起動する。前のバージョンの記録・設定が残っている(上書きインストール)
- エンドレスを1ウェーブ遊ぶ。パリィ・音・振動
- ステージモードで、今回変えたステージ・機能を遊ぶ
- 結果画面からタイトルに戻る(広告の処理で落ちない)
- ランキングを開く(iOS: Game Center)

## 9. 最初にやる設定(1回だけ)

### 9.1 GitHub

1. `main` から `dev` を作り、Settings → General → Default branch を `dev` にする。PR の向き先と、`@claude` の作業の起点が `dev` になる。
2. Settings → General → Pull Requests で「Allow merge commits」と「Allow squash merging」を有効にしておく(既定のまま)。
3. ラベル `hold` と `needs-fix` を作る。
4. Claude の GitHub アプリ(https://github.com/apps/claude)をこのリポジトリに入れる。手元の Claude Code で `/install-github-app` を実行してもよい。
5. いまストアに出している(審査中を含む)バージョンのコミットに、タグを手で打つ: `git tag v1.0.0 <コミット> && git push origin v1.0.0`。コミットがわからなければ `main` の先頭でよい(次のリリースで変更を集める起点になるだけ)。これがないと、`release.yml` が 1.0.0 をもう一度出そうとする。
6. Settings → Secrets and variables → Actions に、次のシークレットを登録する。

| シークレット | 中身 | 作り方 |
| --- | --- | --- |
| `CLAUDE_CODE_OAUTH_TOKEN` | Claude のトークン | 手元で `claude setup-token`。API キーを使う場合は `ANTHROPIC_API_KEY` にして、ワークフローの引数を `anthropic_api_key` に変える |
| `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_P8_BASE64` | App Store Connect API キー | App Store Connect → ユーザとアクセス → 統合 → App Store Connect API で「App Manager」のキーを作る。`.p8` は `base64 -i AuthKey_XXXX.p8` |
| `MATCH_GIT_URL` / `MATCH_PASSWORD` / `MATCH_GIT_BASIC_AUTHORIZATION` | iOS の証明書の保管先(fastlane match) | 9.2 |
| `ANDROID_KEYSTORE_BASE64` / `ANDROID_KEYSTORE_PASSWORD` / `ANDROID_KEY_ALIAS` / `ANDROID_KEY_PASSWORD` | Android のアップロード鍵 | 9.3 |
| `PLAY_SERVICE_ACCOUNT_JSON` | Google Play Developer API のサービスアカウント | 9.3 |

7. 同じ画面の Variables に、準備ができた OS から `IOS_RELEASE` / `ANDROID_RELEASE` を `true` で登録する。登録するまで `release.yml` はその OS をビルドしない。

### 9.2 iOS の署名(fastlane match)

CI のマシンには Xcode のアカウントがないので、配布用の証明書とプロファイルを暗号化して別の非公開リポジトリに置き、CI はそこから読む。

1. 非公開のリポジトリ `watsuwo/certificates` を作る(空でよい)。
2. Mac のリポジトリ直下で `bundle install && cd app/ios && bundle exec fastlane match appstore` を実行する(fastlane の `Gemfile` はリポジトリ直下にある)。リポジトリの URL と、暗号化のパスワード(= `MATCH_PASSWORD`)を聞かれる。Ruby は Homebrew などで 3.3 を入れる(macOS 標準の 2.6 では fastlane が動かない)。
3. `MATCH_GIT_BASIC_AUTHORIZATION` は、`certificates` を読める fine-grained トークンを使って `echo -n "watsuwo:<トークン>" | base64` で作る。
4. 手元で Xcode からアーカイブする場合は、これまでどおり自動署名のままでよい(CI だけビルド時に手動署名に切り替える)。

### 9.3 Android

1. アップロード鍵は [native-app-spec.md](native-app-spec.md) 9.4 で作ったものを使う。`base64 -i upload-keystore.jks` を `ANDROID_KEYSTORE_BASE64` に、`key.properties` の値を残りの3つに入れる(エイリアスは `upload`)。
2. **最初の1回は手で上げる**: 手元で `flutter build appbundle` した AAB を、Play Console の内部テストに手でアップロードして公開する(API ではアプリの最初のリリースを作れない。下書きのままのアプリには、API から下書きのリリースしか作れない)。
3. Google Cloud でサービスアカウントを作って JSON の鍵を作り、Play Console → ユーザーと権限 で招待して、このアプリのリリースの権限を与える。JSON をそのまま `PLAY_SERVICE_ACCOUNT_JSON` に入れる。
4. ここまで済んだら、変数 `ANDROID_RELEASE` を `true` にする。
5. **個人のデベロッパー アカウントの場合**、本番に出す前に「クローズド テストを12人以上で14日以上」続ける必要がある。そのあいだ `promote.yml` は `platform = ios` で実行する。条件を満たして本番へのアクセスが認められたら、`both` で使える。
6. Play Games のリーダーボード([native-app-spec.md](native-app-spec.md) 9.4)は、Android を本番に出す前に済ませる。

### 9.4 費用の目安

非公開リポジトリでは、GitHub Actions の macOS のマシンは Linux の10倍の時間として数える(無料枠は月2000分)。iOS のビルドは1回15〜20分なので、無料枠でテスト配信できるのは月10回ほど。iOS のビルドは `main` に入れたとき(リリース)だけで、PR では動かさない。PR のチェックと Claude のレビューは Linux で動く。

エミュレーターも Linux で動かす(iOS シミュレータは macOS が要るので使わない)。目安は、PR 1つの `e2e` が17分ほど、Issue 1つの `implement.yml` が30〜60分(Claude の作業の長さによる)。非公開リポジトリの Linux のマシンは 2 コア・8GB なので、`e2e` の大半は準備にかかる(実測、キャッシュなし: Gradle のビルド 8 分、SDK のイメージと NDK の用意 4 分、ディスクの片付け 1 分、エミュレーターの起動 1 分、スモークテスト 2 分)。Gradle と SDK のキャッシュは、成功した実行のあとにできる。PR のキャッシュはその PR の中でしか使えず、PR をまたいで使えるのは `dev` で作ったもの(`implement.yml` の実行)だけ。Issue から PR まで1件あたり Linux で1時間前後なので、他の CI と合わせて月20〜30件ほどが無料枠に収まる。足りなくなったら、`e2e` を `claude/issue-*` 以外の PR では動かさない、などで減らす。

## 10. 後回しにしたこと

| 項目 | 内容 |
| --- | --- |
| `dart format` のチェック | いまのコードは大半が `dart format` の結果と違う(79ファイル中68)。一度まとめて整形する PR を入れてから、`check.yml` に `dart format --output=none --set-exit-if-changed lib test integration_test` を足す |
| Google Play の掲載文の自動送信 | 説明文などを `app/android/fastlane/metadata/android/<言語>/` に移し、`promote` で送る。いまは更新が少ないので手で入力する(App Store は送っている) |
| スクリーンショットの自動化 | `integration_test/store_screenshots_test.dart` を CI のシミュレータで動かし、fastlane の `screenshots/` に置いて送る。macOS の時間がかかるので、画面が変わったときだけ手動で実行するワークフローにする |
| Android の段階的公開 | いまは最初から全員に出す。利用者が増えたら、`promote` で一部(例: 20%)に出し、クラッシュ率を見て割合を上げる形に戻す。クラッシュの収集(Crashlytics など)を入れてから |
| ブランチの保護 | GitHub Pro にするか公開リポジトリにすれば、`main` / `dev` を「PR 必須・Approve 必須・`check` / `e2e` / `review` 必須」にできる。そのときは `merge-if-approved.sh` を GitHub の auto-merge に置き換えられる |
| iOS シミュレータでの確認 | Issue の実装の確認は Android エミュレーターだけ。iOS だけの処理(ATT・Game Center)は実機確認(第8章)で見る。macOS のマシンの時間に余裕ができたら、`implement.yml` に iOS シミュレータを足す |
