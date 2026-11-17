# tools/analytics

アナリティクスの週次(収集 → 蓄積 → 分析 → レポート)のコード。仕組み・鍵・運用は [docs/analytics-pipeline.md](../../docs/analytics-pipeline.md)。動かすのは [`.github/workflows/analytics.yml`](../../.github/workflows/analytics.yml)。標準ライブラリだけ(Play・App Store の署名に `openssl`)。

| ファイル | 役割 |
|---|---|
| `store.py` | 時系列ストア。日次の行を `store/<source>/YYYY-MM.jsonl` に upsert、読み出し、取得の状況、メタ情報 |
| `youtube.py` / `play.py` / `appstore.py` | API からの取得 → 日次の行。鍵は環境変数 |
| `collect.py` | 収集(`run` / `backfill`)。source ごとに失敗を分ける |
| `content.py` | 動画の投稿内容(冒頭・本編の字幕、長さ、公開の曜日・時刻など)を `promo/` の記録から集める |
| `facts.py` | ストアから `facts.json` を作る(週ごとの推移、動画の伸びと投稿内容、要確認) |
| `prompt.md` | 分析をする Claude への指示 |
| `extract.py` | claude-code-action の実行記録から、返答の JSON を取り出す |
| `validate.py` | 提案を規則で検証して、引き渡し(`handoff.json`)を作る |
| `report.py` | HTML を作る / Discord に送る(embed + HTML 添付)/ 失敗を知らせる |
| `exp.py` | 実験の記録(作業セッションが使う) |

```sh
cd tools/analytics
python3 -m unittest                       # テスト
# 手元で通す (データ用リポジトリの clone を ../../../analytics に置いた場合)
python3 facts.py --root ../../../analytics --promo ../../promo --out /tmp/facts.json
python3 validate.py --facts /tmp/facts.json --analysis /dev/null --root ../../../analytics --out /tmp/handoff.json
python3 report.py html --facts /tmp/facts.json --handoff /tmp/handoff.json --out /tmp/report.html
python3 report.py send --facts /tmp/facts.json --handoff /tmp/handoff.json --html /tmp/report.html --dry
```

ログに数字を出さない(このリポジトリは公開で、Actions のログも公開)。件数と状態だけを出す。
