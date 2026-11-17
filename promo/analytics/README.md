# アナリティクス

> **自動取得**: YouTube・Google Play・App Store の数字は、GitHub Actions が毎日取って時系列で蓄積し、レポートと提案つきの引き渡しファイルにまとめる([docs/analytics-pipeline.md](../../docs/analytics-pipeline.md))。この README の CSV の取り込みは、API にない「視聴を継続 %」(視聴 vs スワイプ)が要るときだけ使う。

YouTube Studio の「アナリティクス」→ 詳細モード で、指標を増やして (視聴を継続 %、ユニークリーチ、平均視聴割合など) 書き出した zip を `exports/` に置く。

```sh
python3 promo/analytics/import_studio.py "promo/analytics/exports/<zip>"          # 予行
python3 promo/analytics/import_studio.py "promo/analytics/exports/<zip>" --write  # videos.csv と summary.md に書く
```

- 動画は、タイトルと公開日で `promo/records/videos.csv` の ID に結びつける。
- 「視聴を継続 (%)」が Studio の「視聴 vs スワイプ」にあたる。API にはこの指標がない (2026-11 に公式の指標一覧で確認) ので、CSV の書き出しで取る。
- ユニークリーチが 100 未満の動画は、視聴を継続 % が当てにならないので集計から除く。
