# アナリティクス: 収集 → 蓄積 → 分析 → レポート

YouTube・Google Play・App Store の数字を、GitHub Actions が毎日取り、**日次の事実を時系列で蓄積**する。レポートは毎日、取得日の 2 日前(対象日)の数字と、対象日までの直近 7 日の推移を出す。その推移から決まった規則で事実(`facts.json`)を作り、Claude が分析と提案を書き、規則で検証してから、Discord に要約と HTML のレポートを送る。動画の制作やゲームの改修を進める AI(作業セッション)は、引き渡しファイルを読んで動く。

```
cron(毎日 9:30 JST) ▶ 収集 ─────────▶ 事実 ──────▶ 分析 ─────▶ 検証 ─────▶ レポート
                     YouTube・Play・   facts.json    Claude       validate.py   Discord: embed + HTML 添付
                     App Store         規則で集計     鍵なし・Read  規則で判定
                     鍵あり・AI なし
                        │                                                        │
                        └──────▶ mokkosu-works/analytics (非公開) ◀──────────────┘
                                 store/  日次の事実 (時系列の正本)
                                 reports/ 日ごとの HTML・事実・引き渡し (latest.json)
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
| `reports/YYYY-MM-DD.{html,json,facts.json}`、`reports/latest.json` | 日ごとのレポート・引き渡し・事実 |

- 毎回、**直近 14 日を取り直して上書き**する(数字の確定の遅れを吸収)。同じ日の再実行で行は増えない。
- 履歴は git が持つ。過去分は `workflow_dispatch` の `backfill_since` で遡って入れられる(YouTube の日次は遡れる。Play のバルクレポートは月の CSV が残っている範囲。App Store は過去分の依頼 `ONE_TIME_SNAPSHOT` が出した範囲)。
- 書き込みは、ワークフローから deploy key で push する。ファイルはキー順に並べて書くので、差分は変わった数字だけになる。

### 指標(entity)

| source | entity | 主な metric |
|---|---|---|
| youtube | `channel` / 動画 ID | `views` `engagedViews` `estimatedMinutesWatched` `likes` `shares` `comments` `subscribersGained` `averageViewDuration` `averageViewPercentage`(日次)、`retention_r001`〜`retention_r100`(取得日時点の 28 日の維持率曲線の写し) |
| play | パッケージ名 / `パッケージ名#versionCode` | `vitals_crash_rate` `vitals_anr_rate` `vitals_user_perceived_*` `vitals_distinct_users`、バルクレポートの数値列(`installs_*` `ratings_*` `crashes_*`)、`review_count` `review_star_avg` |
| appstore | アプリの Apple ID | `engagement_impression` `engagement_page_view` `engagement_tap`(インプレッション・製品ページの表示・タップ)、`downloads_total` `downloads_<種類>`(初回・再ダウンロードなど)、`install_install` `install_delete`、`sessions`、`crashes`。どれも日ごとの件数の合計(`_total` は種類の合計) |

**レビューの文面は保存しない**(件数と星の平均だけ)。利用者の文章で、指示が混ざりうるため。

## 2. 毎日の流れ(`analytics.yml`、1 つのジョブ)

- **対象日は、取得日(日本の日付)の 2 日前**。数字の確定が遅れるため(ジョブの `TZ` は `Asia/Tokyo`)。
- 対象日の数字は速報値。毎回直近 14 日を取り直すので、あとの実行で確定した数字に上書きされる。
- 各サービスの 1 日の区切りは日本時間ではない(YouTube・Play は米国太平洋時間)。9:30 JST の時点で、対象日の数字がまだ出ていないことがある。そのときはレポートに「まだ出ていない」と出る。

| step | やること | 持つ鍵 |
|---|---|---|
| データ用リポジトリを取る | clone。鍵は step の中だけでファイルにして消す | deploy key |
| 収集 | `collect.py run`。source ごとに失敗しても止めず、`status.jsonl` に残す | YouTube・Play・App Store の読み取り用の鍵 |
| 事実を作る | `facts.py`。対象日の数字(前日・前週の同じ曜日・その前の 7 日の平均と比べる)、7 日ごとの推移(8 区間)、動画の伸び(公開日からの日数をそろえた累計)と投稿内容、区分ごとの比較、Play・App Store の週ごと、要確認(`alerts`)、データの注意 | なし |
| 分析 | claude-code-action。`tools/analytics/prompt.md` の指示で `work/` を読み(Read だけ)、JSON を返す。**ログに出さない** | Claude のトークンだけ |
| 検証・レポート | `extract.py` → `validate.py` → `report.py html` | なし |
| 保存 | データ用リポジトリに commit・push(途中で失敗しても、取れた分は保存する) | deploy key |
| Discord に送る | `report.py send` | Webhook |
| 失敗の通知 | レポートを送れずに止まったときだけ、別ジョブで知らせる | Webhook |

### 動画の伸びと投稿内容
- **伸び**: 公開日を 1 日目にして、1・3・7・14・28 日目までの累計の再生数を出す。公開日が違う動画を、同じ日数で比べるため。3 日目・7 日目は、全動画の中央値に対する倍率も出す。ストアに公開日からのデータが無い動画は、比較から外す(`backfill` で埋まる)。
- **状態**(規則): 公開 7 日以内は「公開直後」、直近 7 日の再生が累計の 30% 以上なら「伸び続けている」、10% 未満(公開 15 日以降)なら「落ち着いた」、ほかは「ゆるやか」。
- **投稿内容**(`content.py` が `promo/` から集める): 種類(プレイ動画 / キャラクター動画)、パターン、冒頭の種類(A 惜しい失敗 / B 見栄えのする場面 / C 結果の瞬間)と冒頭の字幕、本編の字幕、長さ、公開の曜日・時刻、ハッシュタグ。字幕は `promo/build/specs/spec.<パターン>.json`、公開予約は `promo/records/youtube_uploads.csv`。動画の結びつけは、`youtube_uploads.csv` の動画 ID を優先し、無ければ(タイトル, 投稿日)。
- **区分ごと**: 種類・冒頭の種類・パターン・曜日ごとの 3 日目・7 日目の中央値。5 本未満は参考値。
- **Claude の分析**: 伸びた動画と伸びなかった動画で、投稿内容の何が違うかを、`content_findings`(気づき・仮説・根拠・確かめ方)と `video_insights`(動画ごとの見立て)に書く。根拠の数字は、提案と同じ規則で検証する。
- **レポート**: 「動画の伸び」の折れ線(上位 5 本に色、ほかは灰色)と表、区分ごとの表、「投稿内容の分析」。Discord には、3 日目で中央値を上回った上位 3 本と、気づきを 3 件まで。

### 要確認(`alerts`)の規則
- 直近 7 日の再生数が、その前の 7 日の半分以下(その前の 7 日が 100 回以上のとき)
- source の取得に失敗(`ng`)
- YouTube の最新データが、対象日より 3 日以上古い
- クラッシュ率・ANR 率(7 日)が、その前の 7 日の 1.5 倍以上、かつ 0.5% 以上

`alerts` があれば状態は必ず「要確認」。Claude は「要確認」に上げられるが、下げられない。

## 3. 提案の検証(`validate.py`)

| 項目 | 規則 |
|---|---|
| `evidence_verified` | 根拠の数字が、事実(facts.json)の中にあるか。計算式は左辺の数字だけを見る |
| `needs_human_approval` | 公開・投稿・リリース・審査・削除・課金・広告・価格・返信・告知などの語を含む提案は、必ず true |
| `auto_executable` | 承認が不要 / 確からしさが中以上 / サンプルが 5 以上 / 根拠が検証済み / gather でない、の**すべて**で true |

Claude の出力が読めなくても止めない(提案なし・事実だけのレポートになる)。

## 4. レポート

- **Discord**: embed(状態、対象日の YouTube の再生数(前日比・前週の同じ曜日比)・平均視聴割合・登録者・よく再生された動画、直近 7 日の再生数、Play のインストール・クラッシュ率(7 日)、App Store のダウンロード・インプレッション・製品ページの表示(7 日)、要確認、承認が要る提案、取得に失敗した source)+ **HTML を添付**。
- **HTML の構成**: 対象日の数字(YouTube・Play・App Store を前日と比べる)→ YouTube の直近 7 日と 7 日ごとの推移 → 動画の伸びと投稿内容 → 動画別 → Play・App Store の直近 7 日 → 提案 → データの状態。Discord の中では HTML はプレビューされないので、要点は embed に出し、詳細は添付を開く。
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
| `ASC_ANALYTICS_ISSUER_ID` / `ASC_ANALYTICS_KEY_ID` / `ASC_ANALYTICS_KEY_P8` | secret | 下の「App Store」。**リリース用の `ASC_*` は使い回さない** |
| `ASC_BUNDLE_ID` | variable(任意) | 無ければ `com.watsuwo.parrybreak`。アプリの Apple ID は、これから API で引く |
| `CLAUDE_CODE_OAUTH_TOKEN` | secret(リポジトリ) | 既存のものを使う |

### YouTube
1. Google Cloud のプロジェクトで、**YouTube Analytics API** と **YouTube Data API v3** を有効にする。
2. OAuth 同意画面(外部)を作り、公開ステータスを「**本番環境**」にする(「テスト中」だと、許可が 7 日で切れる)。
3. OAuth クライアントを、種類「**ウェブ アプリケーション**」で作る。承認済みのリダイレクト URI に `https://developers.google.com/oauthplayground` を足す。
4. [OAuth 2.0 Playground](https://developers.google.com/oauthplayground) で refresh token を取る。
   - 右上の歯車で「Use your own OAuth credentials」に 3 の ID とシークレットを入れ、Access type を Offline にする。
   - 「Input your own scopes」に `https://www.googleapis.com/auth/yt-analytics.readonly https://www.googleapis.com/auth/youtube.readonly` を入れて「Authorize APIs」を押す。
   - チャンネルのオーナーのアカウントで、2 つの権限を許可する。
   - 「Exchange authorization code for tokens」を押すと、Refresh token が出る。
5. GitHub の Settings → Environments → `analytics` で、`YT_CLIENT_ID`・`YT_CLIENT_SECRET`・`YT_REFRESH_TOKEN` を入れる。値はチャットやファイルに残さない。

### Google Play
1. Google Cloud でサービスアカウントを作り、JSON の鍵を発行する。同じプロジェクトで **Google Play Developer Reporting API** を有効にする。
2. Play Console の「ユーザーと権限」で、サービスアカウントのメールを招待し、「**アプリ情報の閲覧、一括レポートのダウンロード(読み取り専用)**」だけを与える(アカウント全体)。反映に時間がかかることがある(その間は「取得に失敗」と出る)。
3. Play Console の「レポートのダウンロード」→「Cloud Storage の URI をコピー」の `gs://pubsite_prod_…/` から、バケット名を取る。

### App Store
App Store の数字は、App Store Connect API の **Analytics Reports** で取る。「レポートの依頼」を 1 回作ると、Apple が毎日レポートを作る(最初は 1〜2 日後)。**依頼を作れるのは Admin の鍵だけ**で、作ったあとは Sales の鍵で読める。そこで、最初の 1 回だけ Admin の鍵で動かし、そのあと Sales の鍵に入れ替える。

1. App Store Connect → ユーザとアクセス → 統合 → App Store Connect API →「チーム キー」で、**Admin** のキーを作る。`.p8` をダウンロードする(1 回しかダウンロードできない)。Issuer ID とキー ID を控える。
2. environment `analytics` に `ASC_ANALYTICS_ISSUER_ID`・`ASC_ANALYTICS_KEY_ID`・`ASC_ANALYTICS_KEY_P8`(`.p8` の中身すべて)を入れる。
3. analytics を手動で 1 回動かす(`notify` なし)。`collect.py` が、継続の依頼(`ONGOING`)と過去分の依頼(`ONE_TIME_SNAPSHOT`)を作る。`store/status.jsonl` の appstore の行に「依頼を作った」と出る(この時点では、まだ数字はない)。
4. 同じ画面で **Sales** のキーを作り、`ASC_ANALYTICS_KEY_ID` と `ASC_ANALYTICS_KEY_P8` を入れ替える。**Admin のキーは取り消す**。
5. 1〜2 日後に、もう一度動かす(過去分を入れるなら `backfill_since` を付ける)。appstore が `ok` になれば完了。

- 継続の依頼は、長く読まれないと Apple が止める。止まったら(「依頼がなく、作れなかった」と出る)、1〜4 をやり直す。
- 使うのは、利用者を特定しにくい Standard のレポートだけ。

鍵の権限は読み取りだけ(App Store は Sales。最初の 1 回の Admin は、すぐ取り消す)。動画の投稿用・ストアのリリース用の鍵は使わない。

## 6. 安全の設計

| 守るもの | 方法 |
|---|---|
| 数字(このリポジトリは公開) | 数字は非公開のデータ用リポジトリと Discord にだけ置く。スクリプトのログは件数だけ。Claude のやりとりはログに出さない(`show_full_output: false`) |
| 鍵 | environment の secret。App Store の Admin の鍵は、依頼を作る 1 回だけ使い、Sales の鍵に入れ替えて取り消す。使う step の `env` にだけ渡す。deploy key は使う step の中でファイルにして消す。**Claude の step には API の鍵も deploy key も無い** |
| Claude | ツールは Read だけ。集計済みの事実だけを渡す。出力は規則で検証してから使う |
| 利用者の文章 | レビューの文面は取得の時点で捨てる |

## 7. 運用

- 手動で動かす: Actions の analytics → Run workflow(`notify` を外すと Discord に送らない。`backfill_since` で過去分)
- **公開リポジトリの schedule は、60 日リポジトリに活動がないと止まる**。朝に Discord が来なければ、Actions の画面を確認する
- 実験の記録: [`.claude/skills/analytics-handoff/SKILL.md`](../.claude/skills/analytics-handoff/SKILL.md) の 3 章

## 8. 既知の問題と、これから

- App Store の Analytics Reports の列名(`Event`・`Download Type`・`Counts` など)と種類の値は、Apple の公開資料で確かめきれていない。初回の実データで指標名を確認する。列が見つからないレポートは、行を作らずに飛ばす。
- `promo/records/videos.csv` の投稿日と、再生のあった日が合わない動画がある。動画の結びつけは(タイトル, 投稿日)なので、食い違うと「記録なし」になる。
- チャンネル合計と、動画別の合計が一致しない期間がある(削除・非公開の動画の可能性。原因は未確認)。`data_quality` に出す。
- 「視聴 vs スワイプ」は API に無い。`promo/analytics/import_studio.py`(Studio の CSV の手動取り込み)は残す。
- Play のバルクレポートの列名は、CSV の見出しを機械的に変換して指標名にしている。初回の実データで名前を確認する。
