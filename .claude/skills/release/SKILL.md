---
name: release
description: ストアに出すリリースを準備する。前回のタグからの変更を集めてバージョン名を決め、pubspec.yaml とストアの「新機能」の文面を更新し、リリース PR を作る。「リリースして」「リリースの準備」「/release」で使う。引数に patch / minor / major を渡すと、その桁を上げる。
---

# リリース準備

運用の全体は `docs/release-flow.md`。この手順は第3章の 4〜7 にあたる。`dev` から `release/vX.Y.Z` を切り、`main` に向けたリリース PR を作る。人がそれをマージすると `.github/workflows/release.yml` が両 OS をテスト配信する。**ストアへの提出やマージは自分でしない。**

## 1. 状況を確かめる

```sh
git fetch origin dev main --tags
last=$(git tag --list 'v*' --sort=-v:refname | head -n1)   # 前回のリリース。なければ初回
git log --no-merges --format='%h %s%n%b' "${last:+$last..}origin/dev"
git diff --stat "${last:+$last..}origin/dev" -- app/
git show origin/dev:app/pubspec.yaml | grep '^version:'
gh pr list --base main --state open   # 開いているリリース PR・ホットフィックス
gh pr list --base dev --state open    # まだ dev に入っていない PR
```

- 前回のタグから `app/` に変更がない、または出す価値のある変更(ユーザーに見える変化・不具合の修正)がなければ、**何もせず**そう報告して終わる。定期実行のときもこれで止まる。
- `release/v*` のブランチの PR がすでに開いていれば、新しく作らずにそれを更新する(`origin/dev` を取り込んでから直す)。
- `dev` 向けの PR が `needs-fix` / `hold` で止まっていれば、報告に入れる(今回のリリースに入らない)。
- 前回のタグの GitHub Release を `gh release view` か GitHub のツールで見て、公開済みかを報告に入れる(わからなければ人に確かめてもらう項目にする)。

## 2. バージョン名を決める

`docs/release-flow.md` 第1章の表に従う。引数(patch / minor / major)があればそれに従う。`app/pubspec.yaml` の `version: X.Y.Z+N` の `X.Y.Z` だけを変える(`+N` は CI が上書きするので、手元のビルド用に 1 つ上げておく)。

## 3. 「新機能」の文面を書く

次の4つのファイルを **上書き** する(前回の文面は残さない)。

| ファイル | 言語 | 上限 |
| --- | --- | --- |
| `app/ios/fastlane/metadata/ja/release_notes.txt` | 日本語 | 4000字 |
| `app/ios/fastlane/metadata/en-US/release_notes.txt` | 英語 | 4000字 |
| `app/android/fastlane/metadata/android/ja-JP/changelogs/default.txt` | 日本語 | **500字** |
| `app/android/fastlane/metadata/android/en-US/changelogs/default.txt` | 英語 | **500字** |

書き方:
- プレイヤー向けに書く。コードやファイル名、内部の用語(Riverpod、リファクタリングなど)は出さない。ゲーム内の用語は `app/lib/l10n/app_ja.arb` / `app_en.arb` の表記に合わせる。
- 新しい遊び(ステージ・モード) → 遊びやすさの改善 → 不具合の修正 の順に、`・` の箇条書きで3〜6行。
- 目立つ変更がなければ「細かな不具合を修正し、動作を改善しました。」/ "Bug fixes and performance improvements." でよい。
- iOS と Android は同じ内容にする。ただし片方の OS だけの変更(「Android で〜」など)は、その OS の文面にだけ書く。iOS の文面に「Android」と書かない(審査の前の確認で、ほかのプラットフォームへの言及として止められることがある)。Android は 500字に収める(`wc -m` で数える)。

## 4. ほかに直すものを調べる

変更の中身を見て、要るものだけ直す。直さないが人の作業が要るものは、PR のチェックリストに挙げる。

| 変更 | 直すもの / 人の作業 |
| --- | --- |
| 章・ステージ・モードを足した | App Store の説明文 `app/ios/fastlane/metadata/{ja,en-US}/description.txt`(`promote` で送られる)。Google Play の説明文 `docs/play-store.md` と、そのストアへの入力は人の作業 |
| 画面の見た目が変わった | スクリーンショットの撮り直し(人の作業、`docs/app-store.md` の手順) |
| リーダーボードを足した | App Store Connect と Play Console で作る(人の作業、`docs/native-app-spec.md` 9.2 / 9.4) |
| 広告・トラッキング・保存データ・外部の通信 | App のプライバシー / データ セーフティの申告の見直し(人の作業) |
| 権限・Info.plist・AndroidManifest | 審査で聞かれそうな点を PR に書く |
| 仕様が変わった | `design.md` / `docs/native-app-spec.md` の該当箇所と「実装の状況」 |

## 5. 確かめる

Flutter が使える環境なら `cd app && flutter analyze && flutter test` を実行する。使えなければ、CI に任せると PR に書く。

## 6. リリース PR を作る

- ブランチ: `git switch -c release/vX.Y.Z origin/dev`(手順 2〜4 の変更はこのブランチで行う)。コミットのメッセージは日本語で「vX.Y.Z をリリースする」。
- PR の向き先は **`main`**(`gh pr create --base main`)。`dev` には、マージ後に `sync-dev.yml` が自動で戻す。
- PR のタイトル: `vX.Y.Z をリリースする`
- PR の本文:

```markdown
## バージョン
X.Y.Z(前回 vA.B.C から <パッチ/マイナー/メジャー>。理由: …)

## 含まれる変更
- #PR番号 タイトル
…

## 新機能の文面(日本語)
<release_notes.txt の中身>

## マージ前に人が確かめること
- [ ] 文面とバージョン名
- [ ] (あれば)ストア側の作業: …
- [ ] マージは **Create a merge commit** で行う(squash にしない。dev と履歴をそろえるため)

## マージした後
1. release ワークフローが TestFlight と Play の内部テストに上げる
2. 実機で docs/release-flow.md 第8章を確認する
3. Actions → promote を実行する
```

最後に、PR の URL・バージョン名・人がやることを短く報告する。
