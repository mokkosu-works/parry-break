# アナリティクスの自動取得と、AI への引き渡し

YouTube と Google Play の数字を、毎週サーバーが自動で取って、事実としてまとめる。Claude がそこから提案を作り、**動画の制作やゲームの改修を進める AI**(作業セッション)に引き渡す。人は、Discord の短い通知を見て、確認する程度でよい。

```
YouTube Analytics API ─┐
Play Developer Reporting API ─┼─▶ ① 取得・集計 (事実だけ) ─▶ ② Claude が分析・提案 ─▶ ③ 検証して引き渡す ─▶ ④ 通知
Play のバルクレポート ─┘     (鍵あり・AI なし)           (鍵なし・ツールなし)       (規則で判定)           (Discord)
                                                                                         │
                          作業セッション(AI) ◀── handoff/latest.json ──┘      実行したら ─▶ exp.py で記録 ─▶ 翌週の分析が評価
```

コードと配置は [`tools/analytics-server/`](../tools/analytics-server/README.md)。

## 1. 毎週の流れ(サーバーの時刻は日本時間)

| 時刻 | 処理 | 動かすユーザー |
|---|---|---|
| 毎週月曜 6:30 | YouTube と Play から取得し、事実(集計)を作る | 鍵を持つ運用ユーザー |
| 毎週月曜 6:50 | Claude が分析(日本語の全文レポート)と、提案(JSON)を書く | Claude 用ユーザー(sudo なし、鍵なし) |
| 続けて | 提案を検証し、引き渡しファイルを作る → Discord に要約を送る | 運用ユーザー |
| 毎朝 7:00 | サーバーの状態(ディスク、バックアップの鮮度など)の報告。**要確認のときだけ**通知 | Claude 用ユーザー |
| 毎時 | Play のバルクレポートに、つながるかを確かめる(つながったら 1 回取得して止まる) | 運用ユーザー |

失敗したら、どの処理でも Discord に知らせる。

## 2. 数字の出どころと限界

| 出どころ | 取れるもの | 限界 |
|---|---|---|
| YouTube Analytics API | 動画別の再生数・エンゲージ視聴・平均視聴時間と割合・いいね・シェア・登録者、視聴維持率の曲線 | **「視聴 vs スワイプ」は API にない**。代わりに、維持率の曲線の 3 秒時点を、冒頭の強さの目安にする。数字の確定は数日遅れる(報告は 3 日前までの 7 日間) |
| Play の Vitals(クラッシュ率・ANR 率) | リリース別・日別 | 利用者が少ないと**データが出ない** |
| Play のバルクレポート | インストール・評価・クラッシュ・レビュー | 3〜7 日遅れ。読み取り専用のサービスアカウントに「アプリ情報の閲覧、一括レポートのダウンロード(読み取り専用)」(アカウント全体)が要る。**権限の反映に時間がかかる** |
| App Store | **未対応** | 閲覧できる人が限られる。読み取り専用の API キーを作って追加する |

`promo/analytics/import_studio.py`(Studio の CSV の手動取り込み)は残してある。API にない「視聴を継続 %」が必要なときだけ使う。

## 3. 引き渡しファイル(AI との約束)

サーバーの `/srv/analytics/handoff/latest.json`(週ごとの `YYYY-MM-DD.json` も残る)。読み方の正本は同じ場所の `SCHEMA.md`。作業セッションの手順は [`.claude/skills/analytics-handoff/SKILL.md`](../.claude/skills/analytics-handoff/SKILL.md)。

```
facts                事実。YouTube の動画別・チャンネル合計、Play の状況(取れなかった項目は、そう書いてある)
data_quality         数字を使う前に知っておくこと(記録の食い違い、データ不足など)
proposals[]          提案。target(video/game/data)、kind(experiment/fix/gather)、action、rationale、hypothesis、
                     evidence(根拠の数字)、confidence、sample_size、success_metric、
                     needs_human_approval、auto_executable、evidence_verified
experiment_reviews   実行済みの実験の評価(improved / no_change / worse / insufficient_data)
open_experiments     まだ閉じていない実験
rejected             検証で落とした提案とその理由
```

Claude が書いた提案は、**そのままは信用せず、決まった規則で検証し直す**(`handoff.py`)。

| 項目 | 規則 |
|---|---|
| `evidence_verified` | 根拠の数字が、渡した事実の中にあるか。計算式は、左辺の数字だけを見る。ないものは false |
| `needs_human_approval` | 公開・投稿・リリース・審査・削除・課金・広告・価格・返信・告知などの語を含む提案は、必ず true |
| `auto_executable` | 承認が不要 / 確からしさが中以上 / サンプルが 5 以上 / 根拠が検証済み / 「確かめる」提案ではない、の**すべて**を満たすものだけ true |

いまは、各区分が 1〜3 本のデータなので、`auto_executable` になる提案はほとんど出ない。**それが正しい挙動**で、データが溜まると出てくる。

### 受け取る AI が守ること
- `auto_executable` が false の提案は、実行しない(人に確認するか、情報を集める)。
- `needs_human_approval` が true のものは、人の承認を得てから動く。**公開・投稿・リリースは、人の承認なしにしない。**
- `hypothesis` は仮説で、事実ではない。事実は `facts` だけ。
- 実行したら、**必ず `exp.py` で記録する**。記録がないと、翌週の分析が効いたかを評価できない。

```sh
ssh <サーバー> python3 ~/analytics/exp.py add --target video|game --action '実行したこと' --metric '見る指標' --proposal-id P-… [--baseline '実行前の数字']
ssh <サーバー> python3 ~/analytics/exp.py close --id E-… --status done|abandoned --note '結果や理由'
ssh <サーバー> python3 ~/analytics/exp.py list --open
```

## 4. 安全の設計

| 守るもの | 方法 |
|---|---|
| 鍵(YouTube の読み取り、Play のサービスアカウント、Discord の Webhook) | 運用ユーザーだけが読める(権限 600)。**Claude 用ユーザーには渡さない** |
| 鍵の権限 | **読み取り専用だけ**。動画の投稿用・ストアのリリース用の鍵は、サーバーに置かない |
| Claude | 数字を作らせない。**ツールを使わせず**、集計済みの事実の文章だけを渡す。実行は、鍵のないユーザーで行う |
| 利用者のレビューの文面 | 利用者が書いた文章で、指示が混ざりうる。**提案を作る Claude にも、引き渡しファイルにも、渡さない**(件数と星の平均だけ) |
| 通知 | 短い要約だけ。`@` のメンションは無効にして送る。Webhook の URL は、持つ人が誰でも投稿できる秘密なので、画面にもログにも出さない |
| サーバーの出入り口 | ファイアウォールで SSH と LAN 内の限られたポートだけ。SSH はパスワードなし(鍵のみ) |

## 5. 運用

```sh
systemctl list-timers 'yt-weekly-*' 'play-*' 'claude-morning-*'      # 次の実行
sudo systemctl start yt-weekly-fetch.service                          # 手動で取得
sudo systemctl start yt-weekly-report.service                         # 手動で分析 → 引き渡し → 通知まで続く
journalctl -u yt-weekly-report.service --no-pager -n 50               # ログ
cat /srv/analytics/facts/play-status.txt                              # Play のバルクレポートにつながるか
```

- **鍵の置き場所**: サーバーの `~/analytics/state/`(権限 600)。`client_secret.json`(YouTube の OAuth クライアント。種類は「デスクトップ アプリ」)、`token.json`(許可後に自動で作られる)、`play_sa.json`、`play_config.json`(`{"bucket": "…", "packages": ["…"]}`)、`discord_webhook.txt`。
- **YouTube の許可**: `yt_analytics.py auth-start` で URL を作り、ブラウザで許可して、最後のエラー画面のアドレスを `auth-finish` に貼る。**同意画面の公開ステータスが「テスト中」だと、許可が 7 日で切れる**ので「本番環境」にする。戻り先のポート(8791)は、手元で使っているほかのツールと重ならない値にしてある。
- **Webhook の URL を入れるとき**: チャットには貼らず、サーバーで `read -s` を使って、直接ファイルに書く。貼り付けは 1 回だけ(二重に入ると形のチェックで弾かれる)。
- **更新**: `tools/analytics-server/deploy.sh check` で現物との差を見て、`apply` で入れる。サーバー上で直接直したら、必ずリポジトリにも戻す(`check` が差を教える)。

## 6. 既知の問題と、これから

- `promo/records/videos.csv` の投稿日と、再生のあった日が合わない動画がある(公開前の週に再生がある)。**AI が数字で判断する土台なので、記録の確認が先**。
- チャンネル合計(API)と、動画別の合計が一致しない週がある。削除・非公開の動画が入っている可能性。原因は未確認。報告では動画別の合計を使う。
- 視聴時間の合計が、再生数×平均視聴時間と合わない。Shorts の集計の仕様の可能性。原因は未確認で、視聴時間の比較は使わない。
- 動画の ID と記録の対応は、タイトルと投稿日で結びつける(`import_studio.py` と同じ)。記録にない動画は「記録なし」と出る。
- Play のバルクレポートは、権限の反映待ち(毎時の確認が、つながったら自動で取得する)。
- App Store の取得は未対応。
- パターンや冒頭の比較は、本数が少なく、公開日の順番と重なっているため、効いた理由を分けられない。同じ条件で冒頭だけを変えた動画を、同時に出して比べる実験が要る。
