---
name: implement-issue
description: Issue を読んで実装し、Android エミュレーター(手元ではシミュレータでもよい)でアプリを動かして完了条件を確かめてから、dev 向けの PR を作る。implement.yml(Issue に @claude とコメント)が使う。手元でも「Issue #12 を実装して」「/implement-issue 12」で使える。引数は Issue の番号。
---

# Issue の実装

運用の全体は `docs/release-flow.md`。この手順で作った PR は、`pr.yml` のチェック・エミュレーターでのスモークテスト・Claude のレビュー(`.claude/skills/pr-review/SKILL.md`)を通り、**人が Approve するとマージされる**。人は PR の本文と画面を見て Approve するかを決めるので、**何を確かめて、何を確かめられなかったか** を正直に、具体的に書く。

**自分でしないこと**: `dev` / `main` への push、PR のマージ、Approve、ラベルの `hold` を外すこと、`.github/` の変更(Issue で頼まれていない限り)。

## 1. Issue を読む

```sh
gh issue view <番号> --comments
gh pr list --head claude/issue-<番号> --state open   # 前回の続きか
```

- テンプレート(`.github/ISSUE_TEMPLATE/`)の「本来どうなるべきか」/「こうなってほしい」と「完了条件」を、作るものの仕様とする。コメントで決まったことがあれば、それが優先。
- 次のどれかなら、**実装せずに** Issue にコメントで質問して終わる(PR は作らない)。答えが書かれたあと、もう一度 `@claude` と書かれたら続きをする。
  - 「決めていないこと」に「先に聞いてほしい」が付いた項目があり、コメントで答えが出ていない
  - 完了条件がない、または確かめられる形になっておらず、どう作るかで結果が大きく変わる
  - 頼まれた内容が、保存データの互換をなくす・広告の出し方を変える・ストアの設定を変えるなど、`pr-review` スキルで `[要修正]` になる種類の変更を避けられない
- 「任せる」の項目は自分で決め、PR の本文の「決めたこと」に理由と一緒に書く。
- 前回の PR が開いていれば、そのブランチ(チェックアウト済み)で続きをする。前回の PR の本文・コメント・レビューの指摘も読む。

## 2. 実装する

- 手を入れる前に、関係する仕様(`design.md`、`docs/native-app-spec.md`)とコードを読む。レビューは `.claude/skills/pr-review/SKILL.md` の観点で行われるので、先に読んで、当てはまる節(コアの決定性、保存データ、ステージの JSON、広告、文言の `.arb` など)を守る。
- 変更は Issue の範囲に絞る。ついでの整理・整形はしない。
- テストは `pr-review` スキルの 2.7 の表に従って足す。不具合の修正なら、直す前に落ちるテストを先に書く。

```sh
cd app
flutter analyze
flutter test
```

両方が通るまで直す。

## 3. エミュレーターで確かめる

CI ではエミュレーター `emulator-5554` が起動済みで、デバッグビルドも済んでいる。手元では `flutter devices` で出た ID を使う(iOS シミュレータでもよい。その場合は PR に「iOS シミュレータで確かめた」と書く)。

撮った画面は、環境変数 `SHOT_DIR` のフォルダに PNG で残る(CI では設定済み。手元で省くと `app/build/store_screenshots`)。

### 3.1 スモークテスト

起動からタイトル・ステージ選択・エンドレス・一時停止・タイトルへの戻りまでを通す。`pr.yml` の `e2e` と同じもの。

```sh
cd app
flutter drive -d emulator-5554 --driver=test_driver/integration_test.dart --target=integration_test/smoke_test.dart
```

### 3.2 完了条件を確かめるテスト

完了条件のうち画面で確かめられるものを、`app/integration_test/issue_<番号>_test.dart` に書いて動かす。

- 書き方は `integration_test/smoke_test.dart`(起動・画面遷移・ボールを出して遊ぶ・撮影)と `integration_test/store_screenshots_test.dart`(記録の差し替え・`World` を直接動かしてボス戦や特定のウェーブを作る・パリィを決める)を真似る。
- 入力は実機と同じ経路を使う: タップは `t.tap(find.text(...))`、パリィは `t.sendKeyEvent(LogicalKeyboardKey.space)`、パドルは `world.input.targetX`。
- ステージを解禁した状態は、`SharedPreferences.setMockInitialValues` に記録を入れるか、設定の `debugMode: true` で作る。
- ゲームは毎フレーム動き続けるので `pumpAndSettle` は使わない。`t.pump(Duration(...))` で進める。
- 完了条件の項目ごとに `expect` を書き、画面を `binding.takeScreenshot('issue<番号>_01_...')` で撮る(Android は最初の撮影の前に `binding.convertFlutterSurfaceToImage()` が要る。`smoke_test.dart` の `shot` を参照)。

```sh
cd app
flutter drive -d emulator-5554 --driver=test_driver/integration_test.dart --target=integration_test/issue_<番号>_test.dart
```

### 3.3 画面とログを見る

- 撮った PNG を **Read で開いて自分の目で見る**。テストが通っても、表示が崩れている・文字がはみ出している・意図した演出が見えない、なら直す。何が写っていたかを PR の本文に書く。
- 落ちていないかをログで見る: `adb logcat -d -s flutter AndroidRuntime:E`(`FATAL EXCEPTION`、Flutter の例外がないか)。

### 3.4 確かめられないもの

次はエミュレーターでは確かめられないので、PR の本文の「確かめられなかったこと」に挙げ、人に確かめてほしい手順を書く。

- 音・振動・タッチの手触り(遅延)・実機の性能(フレーム落ち)
- 本番の広告、Game Center / Play Games のランキング
- iOS だけで起きること(CI は Android だけ)、リリースビルドだけで起きること(R8 など)

### 3.5 テストを残すか

`issue_<番号>_test.dart` は PR に入れる(何を確かめたかをレビューと人が読めるように)。ただし、1 分を超える、撮影だけで `expect` がない、など繰り返し使う価値がないものは消して、確かめた内容を PR の本文に書く。

## 4. コミットして PR を作る

コミットのメッセージは、このリポジトリの書き方に合わせる(日本語。1 行目は「〜を直す」「〜を足す」の形。2 行目を空けて、なぜそうしたかを書く)。

```sh
git add -A
git commit -m "<1 行目>" -m "<理由>"
git push -u origin claude/issue-<番号>
```

PR の本文を `app/build/pr_body.md` に書き、次で作る。前回の PR が開いていれば、作らずに `gh pr edit <PR> --body-file app/build/pr_body.md` で本文を更新し、`gh pr comment` で今回やったことを書く。

```sh
gh pr create --base dev --head claude/issue-<番号> --title "<コミットの 1 行目と同じ>" --body-file app/build/pr_body.md
```

**下書き(`--draft`)で作るとき**: エミュレーターでの確認が通らなかった、完了条件のどれかを満たせなかった、確かめるべきことを確かめられなかった。下書きは `pr.yml` のレビューとマージの対象にならないので、人が見て判断する。理由を本文の先頭に書く。

本文は次の形にする。

```markdown
Closes #<番号>

## 変えたこと
- (ユーザーから見た変化を先に。そのあとコードの変更を、ファイル単位で短く)

## 完了条件
- [x] <Issue の完了条件 1> — <どう確かめたか: 単体テスト名 / issue_<番号>_test.dart の expect / 画面 issue<番号>_02 で ○○ が見えた>
- [ ] <満たせなかった条件> — <なぜか>

## エミュレーターで確かめたこと
- 端末: Android エミュレーター (API 34, Pixel 6)
- スモークテスト: 成功
- issue_<番号>_test.dart: 成功(<何を確かめたか>)
- 画面: <撮った画面ごとに、何が写っていたか>
- ログ: 例外・クラッシュなし
- 撮った画面とログ: <RUN URL> の Artifacts の emulator-screenshots

## 確かめられなかったこと
- <3.4 に当たるもの。人が実機で確かめる手順を添える。なければ「なし」>

## 決めたこと
- <「任せる」の項目と、Issue に書かれていなかったことで自分が決めたこと。理由を添える。なければ「なし」>
```

## 5. Issue に書く

`gh issue comment <番号>` で、PR へのリンクと、完了条件をすべて満たしたか(下書きならその理由)と、人に確かめてほしいことを 3〜5 行で書く。

## 手元(Claude Code)で使うとき

- ブランチは `git switch -c claude/issue-<番号> origin/dev` で切る(すでにあれば、それに切り替える)。
- 端末は `flutter devices` で選ぶ。Android のエミュレーターがなければ iOS シミュレータでよい。
- PR を作る前に、ユーザーに確かめる。手元で作った PR はユーザーが作者になるので、ユーザー自身は Approve できない(GitHub の制限)。マージは PR の画面で手でする。
