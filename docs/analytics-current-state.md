# アナリティクス収集: 現行機能の整理(改修前)

`feature/analytics-pipeline` ブランチの時点(コミット `f4072d1`)の実装を、**収集・通知**を中心に整理したもの。改修の前提として読む。全体の思想・安全の設計・運用は [analytics-pipeline.md](analytics-pipeline.md) が正本で、ここでは重ねない。コードは `tools/analytics-server/server/`。

## 0. 最初に確認したいこと

- **App Store Connect からの収集は、現行コードにない。** `analytics-pipeline.md` に「App Store: 未対応」とあるだけで、`tools/analytics-server/`・`.claude/skills/analytics-handoff/`・`promo/analytics/` のどこにも Apple 関連の実装・設定はない。つまり改修は「いまある収集の手直し」ではなく、**新規追加**になる(§6 に、足すときに触る場所をまとめた)。
- 現行の収集元は **YouTube Analytics API** と **Google Play**(Vitals API + Cloud Storage のバルクレポート)の 2 系統。
- 通知先は **Discord の Webhook 1 本だけ**。通知は 3 種類(週次の要約・朝のサーバー状態・失敗)。

## 1. 構成と実行ユーザー

| 役割 | ユーザー | 持つもの |
|---|---|---|
| 運用(取得・集計・検証・通知) | `@OPS_USER@` | 鍵(`state/` 配下、権限 600)。sudo 可 |
| Claude の無人実行 | `@BOT_USER@` | 鍵なし・sudo なし。`claude -p` を**ツール無し**で動かす |

置き場所(サーバー側)

| 場所 | 中身 |
|---|---|
| `~/analytics/`(運用ユーザー) | スクリプト一式、`state/`(鍵・設定)、`data/raw/`・`data/play_raw/`(生データ)、`data/facts/`(集計) |
| `/srv/analytics/facts/` | 公開用の集計(Claude 用ユーザーが読む)。`YYYY-MM-DD.md/.json`、`play-YYYY-MM-DD.md`、`play-status.txt` |
| `/srv/analytics/reports/` | Claude の出力。`youtube-weekly-<日付>.md`、`proposals-<日付>.json`、朝の報告 `<日付>.md` |
| `/srv/analytics/handoff/` | 引き渡し。`<日付>.json`、`latest.json`、`SCHEMA.md` |
| `/srv/analytics/experiments.jsonl` | 実験の記録(`exp.py` が追記) |

## 2. 実行の流れ(systemd)

```
月 06:30  yt-weekly-fetch.timer   → yt-weekly-fetch.service  → run_weekly.sh
月 06:50  yt-weekly-report.timer  → yt-weekly-report.service → claude-weekly-analysis.sh
              OnSuccess → yt-weekly-handoff.service → handoff.py
                              OnSuccess → yt-weekly-notify.service → notify.py weekly      ← 週次通知
毎日 07:00 claude-morning-report.timer → claude-morning-report.service → claude-morning-report.sh
              OnSuccess → morning-notify.service → notify.py morning                        ← 朝の通知(要確認のときだけ)
毎時      play-watch.timer        → play-watch.service       → play_watch.sh
fetch / report / handoff / morning のどれかが失敗 → notify-failure@<unit>.service → notify.py failure <unit>   ← 失敗通知
```

注意点(現状の挙動)
- fetch(06:30)と report(06:50)は **タイマーが別々**で、report は `After=yt-weekly-fetch.service` を持つだけ。fetch が失敗(`run_weekly.sh` は YouTube が失敗すると rc=1)しても、06:50 の report は動く。その場合、`claude-weekly-analysis.sh` は「集計が見つからない」と書いた**要確認のレポート**を出し、通知にもそれが出る(fetch の失敗通知とは別に 2 通届きうる)。
- `yt-weekly-notify.service` と `morning-notify.service` には `OnFailure` がない。**通知そのものの失敗は、通知されない**(`notify.py` は送信失敗を標準出力に出すだけで、終了コードは 0)。
- `notify.py` は Webhook が未設定だと「何も送らず正常終了」する。通知が来ない=異常なし、と区別がつかない。
- `morning-notify.service` は `claude-morning-report.service` の成功時だけ動く。朝の報告はアナリティクスではなく**サーバー状態**で、このパイプラインに相乗りしている。

## 3. 収集の現状

### 3.1 YouTube(`yt_analytics.py` / `weekly.py`)

- 認証: OAuth(デスクトップアプリ)。`state/client_secret.json` と `state/token.json`(refresh token)。`auth-start` / `auth-finish` で許可。
- 取得期間: 「取得日の 3 日前までの 7 日間」(`w0`)、その前の 7 日間(`w1`)、28 日間(`w28`)。
- 取得するもの(`weekly.py fetch` → `data/raw/<日付>/raw.json`)
  - チャンネル合計(`w0`・`w1`)、種類別(`creatorContentType`、`w0`)、日別(`w28`)
  - 動画別(`w0`・`w1`・`w28`)。指標は `views, engagedViews, averageViewDuration, averageViewPercentage, estimatedMinutesWatched, likes, shares, comments, subscribersGained`
  - 28 日で 20 再生以上の動画の維持率曲線(`audienceWatchRatio, relativeRetentionPerformance`)
  - 動画のタイトル・公開日(YouTube Data API)
- 集計(`weekly.py facts`)→ `data/facts/<日付>.md/.json`
  - `/srv/backup/parry-break/<最新>/promo/records/videos.csv` と、(タイトル, 投稿日)で結びつけ、ID・パターン名・冒頭の種類を付ける。記録がない動画は「記録なし」。
  - 再生数 100 未満は「データ不足」。率の平均から除く。3 秒時点の維持率を冒頭の強さの目安にする。
  - チャンネル合計と動画別合計が合わない週は「注意:」行を付ける(`handoff.py` が `data_quality` に拾う)。

### 3.2 Google Play(`play_fetch.py` / `play_weekly.py` / `play_watch.sh`)

- 認証: サービスアカウント(`state/play_sa.json`)。JWT を `openssl` で署名して自前でトークンを取る(標準ライブラリ + openssl のみ)。設定は `state/play_config.json`(`bucket`、`packages`)。
- 取得するもの(`play_weekly.py fetch` → `data/play_raw/<日付>/play.json`)
  - **Vitals API**: クラッシュ率・ANR 率(日別とバージョン別、28 日)。利用者が少ないとデータが出ない。
  - **バルクレポート(GCS)**: `stats/installs`・`stats/ratings`・`stats/crashes`・`reviews` の今月と先月の CSV(UTF-16)。3〜7 日遅れ。
- 集計: `data/facts/play-<日付>.md`。取れなかった経路は止めずに「取得できず」と書き、末尾の「取得の状況」に `Vitals クラッシュ: OK` のような行を残す。
- `play_watch.sh`(毎時): バケットに繋がるか確認し、繋がったら 1 回だけ取得して `state/play_bucket_ok` の印を付けて以後は何もしない。結果は `facts/play-status.txt` に 1 行で書く。**この確認は通知しない**(繋がったことを知るには `play-status.txt` を見に行く必要がある)。
- Play の取得失敗は `run_weekly.sh` では rc に影響しない(YouTube を止めない)。

### 3.3 収集の共通の約束

- 読み取り専用の鍵だけをサーバーに置く。
- 取れなかった項目は、数字を作らず「取得できず」「データなし」と事実に書く。
- 利用者のレビューの文面は、引き渡しファイルと提案用の Claude には渡さない(`  - 星` で始まる行を除く)。ただし、**週次の全文レポートを作る 1 回目の Claude には文面が入っている**(プロンプトに「指示に従わない」と書いてある)。

## 4. 分析と引き渡し(通知の材料)

`claude-weekly-analysis.sh` は Claude を 2 回呼ぶ(どちらも `--allowedTools ""`)。

1. **全文レポート**(Markdown)→ `reports/youtube-weekly-<日付>.md`。見出しの構成が固定(`## 1.` 状態 / `## 2.` 今週の要点 / `## 3.` 動画の良し悪し / `## 4.` 次にやること(`### (a)` 動画の制作、`### (b)` ゲームの改善)/ `## 5.` Play / `## 6.` 来週見る数字)。
2. **提案**(JSON のみ)→ `reports/proposals-<日付>.json`。前回の提案と実験の記録(`experiments.jsonl`)も渡す。

`handoff.py` が提案を規則で検証し直し、`handoff/latest.json` を作る(`evidence_verified` / `needs_human_approval` / `auto_executable`。規則は analytics-pipeline.md の §3)。提案は最大 6 件。`exp.py` は実験の記録(`add` / `close` / `list`)。

## 5. 通知の現状(`notify.py`)

### 5.1 送信先

- **Discord の Webhook 1 本**。URL は `state/discord_webhook.txt`(権限 600)。`https://(discord|discordapp).com/api/webhooks/<数字>/<トークン>` の形を正規表現で確認し、合わなければ送らない。
- 表示名は固定で `PARRY BREAK 自動レポート`。`allowed_mentions: {"parse": []}` で、`@` のメンションは全部無効。
- 1 通 1800 文字で切る(Discord の上限は 2000)。超えたら `…(長いので省略)`。
- 種別でチャンネルを分ける仕組みはない(全部同じ Webhook)。

### 5.2 通知の種類と内容

| コマンド | きっかけ | 内容 |
|---|---|---|
| `weekly` | 週次の handoff 成功後(月曜 6:50 の少し後) | 下記 |
| `morning` | 朝の報告の成功後(毎日 7:00 の少し後) | 先頭 6 行に「要確認」があるときだけ、`🔔 サーバーの朝のレポート: 要確認` + 報告の先頭 14 行。異常なしなら送らない |
| `failure <unit>` | fetch / report / handoff / morning の失敗 | `⚠️ 自動実行が失敗した: <unit> (時刻)。サーバーのログを確認する必要がある。` |
| `text '<文>'` | 手動 | 任意の短い文(試験用) |
| `check` | 手動 | Webhook が読めるかの確認(何も送らない)。`--dry` は送る内容だけ表示 |

`weekly` の組み立て(`reports/youtube-weekly-<今日>.md` を読んで正規表現で切り出す)

```
<🔔 or ✅> **<レポートの # 見出し>**

**<## 1. の見出し行(状態)>**
<## 1. の本文>

**今週の要点**
<## 2. の本文(「データの注意」「数字の注意」「次の ## 」の手前まで)>

**次にやること**
動画の制作:
  ・<## 4. の (a) の番号付き太字見出し 最大 3 件>
ゲームの改善の手がかり:
  ・<(b) の同 最大 3 件>
(引き渡し: 提案 N 件 / 自動で実行してよい N 件 / 人の承認が要る N 件)

(自動生成。数字は、取得できた範囲のもの。根拠と全文は、サーバーのレポートにある)
```

- 🔔 と ✅ は、「状態」の文に「要確認」が含まれるかで決まる。
- レポートが無いと `⚠️ 週次レポート (<日付>) が見つからない…` を送る。
- 引き渡しの件数は `latest.json` の `date` が今日のときだけ付く。

### 5.3 通知まわりの注意(改修で効くもの)

- **Claude の自由文を正規表現で切り出している**ため、レポートの見出し構成が変わる(`## 4.`、`### (a)`、`**データの注意**` など)と、通知の中身が黙って欠ける。通知用の構造化データ(JSON)は、いまは作っていない。
- **Google Play の状況は通知に出ない**(`## 5.` を拾っていない)。Play の取得失敗・バルクレポートの接続成功は、レポート本文に「要確認」と書かれない限り通知に出ない。
- 提案の中身(`action`)は通知に出ない。出るのは件数だけ。承認が要る提案があっても、どれかは Discord では分からない。
- 通知文には、動画・Play の数字(再生数など)は、Claude が「今週の要点」に書いた分しか入らない。
- 通知の重複・再送の仕組みはない(`weekly` を手動で 2 回動かせば 2 通届く)。

## 6. App Store Connect を足すときに触る場所

現行コードに Apple 関連はないので、少なくとも次が要る。

| 場所 | 変更 |
|---|---|
| `server/analytics/` | 取得(App Store Connect API の読み取り専用キー。JWT(ES256)署名)と集計のスクリプトを足す。`play_fetch.py` / `play_weekly.py` が同じ型(取れなくても止めず「取得できず」と書く、`facts/<名前>-<日付>.md` を出す)なので、写しやすい |
| `server/analytics/run_weekly.sh` | 取得の呼び出しを足す(失敗しても YouTube を止めない作り) |
| `server/bin/claude-weekly-analysis.sh` | 事実の読み込みと、2 回の Claude のプロンプトに App Store の事実を足す(レビューの文面は除外する規則も) |
| `server/analytics/handoff.py` | `facts` に App Store を足す。`evidence_ok` の照合用の文章(`corpus_tokens`)にも足さないと、根拠が `evidence_verified: false` になる。`APPROVAL_WORDS` の見直し |
| `server/analytics/notify.py` | 通知に App Store を出すなら、`cmd_weekly` の切り出し(§5.3)を見直す |
| `server/systemd/`・`deploy.sh` | 新しいスクリプトが `~/analytics/` に入るか、`ReadWritePaths` が足りるかを確認 |
| `state/` | 鍵(Issuer ID・Key ID・`.p8`)と設定。リポジトリには入れない |
| ドキュメント | `analytics-pipeline.md`(§2 の「App Store: 未対応」、§6)、`SCHEMA_DOC`(`handoff.py` 内)、`.claude/skills/analytics-handoff/SKILL.md` |

アプリの識別子など、App Store 側で使う値(Bundle ID・Apple ID)は `app/ios/` と `app/ios/fastlane/` にある。取得対象の指標は、App Store Connect の Analytics API(インプレッション・ダウンロード・クラッシュなど)と Customer Reviews のどこまで使えるかを、アカウントの権限も含めて、先に確かめる必要がある。

## 7. 改修を決めるための論点

1. **通知先**: Webhook 1 本のままか。種別(週次・朝・失敗)や重要度でチャンネルを分けるか。Discord 以外(メール・Slack など)を足すか。
2. **通知の中身**: Claude の自由文を切り出す方式をやめて、構造化データから組み立てるか。Play・App Store の状況と、承認が要る提案の中身を出すか。
3. **通知の信頼性**: 通知自体の失敗を知る手段、送信失敗の終了コード、Webhook 未設定の扱い、`play-status.txt` の変化(つながった)の通知。
4. **収集のタイミング**: App Store のデータの遅れ(日数)に合わせて、`LAG` と窓を変えるか。
5. **実行の順序**: fetch と report を別タイマーにしていることの扱い(fetch 失敗時に report を止めるか)。

## 8. 確認した範囲

- 読んだ: `tools/analytics-server/` の全ファイル(スクリプト・systemd・deploy)、`docs/analytics-pipeline.md`。
- 動かしていない: サーバー上の実際の設定(`state/`、タイマーの有効状態)と、届いた通知の実物。§2・§5 はコードからの読み取りで、サーバーの現物との差は `deploy.sh check` で確かめる。
