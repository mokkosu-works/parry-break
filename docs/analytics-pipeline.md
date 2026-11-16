# アナリティクス: 収集 → 蓄積 → 分析 → レポート

YouTube と Google Play の数字を、GitHub Actions が毎週取り、**日次の事実を時系列で蓄積**する。その推移から決まった規則で事実(`facts.json`)を作り、Claude が分析と提案を書き、規則で検証してから、Discord に要約と HTML のレポートを送る。動画の制作やゲームの改修を進める AI(作業セッション)は、引き渡しファイルを読んで動く。

```
cron(月 6:30 JST) ─▶ 収集 ─────────▶ 事実 ──────▶ 分析 ─────▶ 検証 ─────▶ レポート
                     YouTube・Play     facts.json    Claude       validate.py   Discord: embed + HTML 添付
                     鍵あり・AI なし    規則で集計     鍵なし・Read  規則で判定
                        │                                                        │
                        └──────▶ mokkosu-works/analytics (非公開) ◀──────────────┘
                                 store/  日次の事実 (時系列の正本)
                                 reports/ 週ごとの HTML・事実・引き渡し (latest.json)
```

- ワークフロー: [`.github/workflows/analytics.yml`](../.github/workflows/analytics.yml)
- コード: [`tools/analytics/`](../tools/analytics/README.md)(標準ライブラリだけ。テストは `cd tools/analytics && python3 -m unittest`)
- 以前の自前サーバー(systemd + `claude -p`)の方式は廃止した。

## 1. 蓄積(データ用リポジトリ `mokkosu-works/analytics`)

| パス | 中身 |
|---|---|
| `store/<source>/YYYY-MM.jsonl` | 1 行 = 1 日 1 指標。`{"source","metric","entity","date","value"}`。キー `(source, metric, entity, date)` で上書き(upsert) |
| `store/status.jsonl` | 取得の状況。source ごとに 1 日 1 行(`ok` / `ng` / `no_data` と理由) |
| `store/meta/youtube_videos.json` | 動画のタイトル・公開日(videos.csv との結びつけに使う) |
| `store/experiments.jsonl` | 実験の記録(`exp.py` が追記) |
| `reports/YYYY-MM-DD.{html,json,facts.json}`、`reports/latest.json` | 週ごとのレポート・引き渡し・事実 |

- 毎回、**直近 14 日を取り直して上書き**する(数字の確定の遅れを吸収)。同じ日の再実行で行は増えない。
- 履歴は git が持つ。過去分は `workflow_dispatch` の `backfill_since` で遡って入れられる(YouTube の日次は遡れる。Play のバルクレポートは月の CSV が残っている範囲)。
- 書き込みは、ワークフローから deploy key で push する。ファイルはキー順に並べて書くので、差分は変わった数字だけになる。

### 指標(entity)

| source | entity | 主な metric |
|---|---|---|
| youtube | `channel` / 動画 ID | `views` `engagedViews` `estimatedMinutesWatched` `likes` `shares` `comments` `subscribersGained` `averageViewDuration` `averageViewPercentage`(日次)、`retention_r001`〜`retention_r100`(取得日時点の 28 日の維持率曲線の写し) |
| play | パッケージ名 / `パッケージ名#versionCode` | `vitals_crash_rate` `vitals_anr_rate` `vitals_user_perceived_*` `vitals_distinct_users`、バルクレポートの数値列(`installs_*` `ratings_*` `crashes_*`)、`review_count` `review_star_avg` |

**レビューの文面は保存しない**(件数と星の平均だけ)。利用者の文章で、指示が混ざりうるため。

## 2. 毎週の流れ(`analytics.yml`、1 つのジョブ)

| step | やること | 持つ鍵 |
|---|---|---|
| データ用リポジトリを取る | clone。鍵は step の中だけでファイルにして消す | deploy key |
| 収集 | `collect.py run`。source ごとに失敗しても止めず、`status.jsonl` に残す | YouTube・Play の読み取り専用の鍵 |
| 事実を作る | `facts.py`。8 週の推移、動画別、パターン・冒頭ごと、Play の週ごと、要確認(`alerts`)、データの注意 | なし |
| 分析 | claude-code-action。`tools/analytics/prompt.md` の指示で `work/` を読み(Read だけ)、JSON を返す。**ログに出さない** | Claude のトークンだけ |
| 検証・レポート | `extract.py` → `validate.py` → `report.py html` | なし |
| 保存 | データ用リポジトリに commit・push(途中で失敗しても、取れた分は保存する) | deploy key |
| Discord に送る | `report.py send` | Webhook |
| 失敗の通知 | レポートを送れずに止まったときだけ、別ジョブで知らせる | Webhook |

### 要確認(`alerts`)の規則
- 再生数が前週の半分以下(前週 100 回以上のとき)
- source の取得に失敗(`ng`)
- YouTube の最新データが 1 週以上古い
- クラッシュ率・ANR 率が前週の 1.5 倍以上、かつ 0.5% 以上

`alerts` があれば状態は必ず「要確認」。Claude は「要確認」に上げられるが、下げられない。

## 3. 提案の検証(`validate.py`)

| 項目 | 規則 |
|---|---|
| `evidence_verified` | 根拠の数字が、事実(facts.json)の中にあるか。計算式は左辺の数字だけを見る |
| `needs_human_approval` | 公開・投稿・リリース・審査・削除・課金・広告・価格・返信・告知などの語を含む提案は、必ず true |
| `auto_executable` | 承認が不要 / 確からしさが中以上 / サンプルが 5 以上 / 根拠が検証済み / gather でない、の**すべて**で true |

Claude の出力が読めなくても止めない(提案なし・事実だけのレポートになる)。

## 4. レポート

- **Discord**: embed(状態、YouTube の再生数・平均視聴割合・登録者、Play のインストール・クラッシュ率、要確認、承認が要る提案、取得に失敗した source)+ **HTML を添付**。Discord の中では HTML はプレビューされないので、要点は embed に出し、詳細は添付を開く。
- **HTML**: 1 ファイルで完結(外部を読み込まない、スクリプトなし、CSP で禁止)。値はすべてエスケープ。ダークモード対応。推移は SVG の折れ線。
- `@` のメンションは無効。Webhook の URL はログに出さない。送信に失敗したら、ジョブが赤になる。

## 5. 鍵と設定(environment `analytics`)

environment `analytics` は、使えるブランチを `dev` だけにしてある。値は `gh secret set <名前> --env analytics --repo mokkosu-works/parry-break` で入れる(入力は画面に出ない。複数行の JSON は `< ファイル` で渡す)。

| 名前 | 種類 | 中身と作り方 |
|---|---|---|
| `ANALYTICS_DATA_DEPLOY_KEY` | secret | `mokkosu-works/analytics` の deploy key(書き込み可)の秘密鍵。設定済み |
| `YT_CLIENT_ID` / `YT_CLIENT_SECRET` / `YT_REFRESH_TOKEN` | secret | 下の「YouTube」 |
| `PLAY_SA_JSON` | secret | 下の「Google Play」。**リリース用の `PLAY_SERVICE_ACCOUNT_JSON` は使い回さない** |
| `PLAY_BUCKET` | secret | バルクレポートのバケット名(`pubsite_prod_…`) |
| `PLAY_PACKAGES` | variable | パッケージ名(カンマ区切り)。`com.watsuwo.parrybreak` を設定済み |
| `DISCORD_WEBHOOK_URL` | secret | 送信先のチャンネルの設定 → 連携サービス → ウェブフック → URL をコピー |
| `CLAUDE_CODE_OAUTH_TOKEN` | secret(リポジトリ) | 既存のものを使う |

### YouTube
1. Google Cloud のプロジェクトで、**YouTube Analytics API** と **YouTube Data API v3** を有効にする。
2. OAuth 同意画面(外部)を作り、公開ステータスを「**本番環境**」にする(「テスト中」だと、許可が 7 日で切れる)。
3. OAuth クライアント ID を、種類「**デスクトップ アプリ**」で作る。
4. 手元で `python3 tools/analytics/youtube_auth.py` を実行する。ID とシークレットを聞かれ、ブラウザでチャンネルのオーナーとして許可すると、3 つの secret を直接入れる(値は画面にもファイルにも残らない)。

### Google Play
1. Google Cloud でサービスアカウントを作り、JSON の鍵を発行する。同じプロジェクトで **Google Play Developer Reporting API** を有効にする。
2. Play Console の「ユーザーと権限」で、サービスアカウントのメールを招待し、「**アプリ情報の閲覧、一括レポートのダウンロード(読み取り専用)**」だけを与える(アカウント全体)。反映に時間がかかることがある(その間は「取得に失敗」と出る)。
3. Play Console の「レポートのダウンロード」→「Cloud Storage の URI をコピー」の `gs://pubsite_prod_…/` から、バケット名を取る。

鍵の権限は読み取りだけ。動画の投稿用・ストアのリリース用の鍵は使わない。

## 6. 安全の設計

| 守るもの | 方法 |
|---|---|
| 数字(このリポジトリは公開) | 数字は非公開のデータ用リポジトリと Discord にだけ置く。スクリプトのログは件数だけ。Claude のやりとりはログに出さない(`show_full_output: false`) |
| 鍵 | environment の secret。使う step の `env` にだけ渡す。deploy key は使う step の中でファイルにして消す。**Claude の step には API の鍵も deploy key も無い** |
| Claude | ツールは Read だけ。集計済みの事実だけを渡す。出力は規則で検証してから使う |
| 利用者の文章 | レビューの文面は取得の時点で捨てる |

## 7. 運用

- 手動で動かす: Actions の analytics → Run workflow(`notify` を外すと Discord に送らない。`backfill_since` で過去分)
- **公開リポジトリの schedule は、60 日リポジトリに活動がないと止まる**。月曜に Discord が来なければ、Actions の画面を確認する
- 実験の記録: [`.claude/skills/analytics-handoff/SKILL.md`](../.claude/skills/analytics-handoff/SKILL.md) の 3 章

## 8. 既知の問題と、これから

- App Store Connect の収集は未対応(次に足す。読み取り専用の API キーを用意し、取れる指標を確かめてから)。
- `promo/records/videos.csv` の投稿日と、再生のあった日が合わない動画がある。動画の結びつけは(タイトル, 投稿日)なので、食い違うと「記録なし」になる。
- チャンネル合計と、動画別の合計が一致しない週がある(削除・非公開の動画の可能性。原因は未確認)。`data_quality` に出す。
- 「視聴 vs スワイプ」は API に無い。`promo/analytics/import_studio.py`(Studio の CSV の手動取り込み)は残す。
- Play のバルクレポートの列名は、CSV の見出しを機械的に変換して指標名にしている。初回の実データで名前を確認する。
