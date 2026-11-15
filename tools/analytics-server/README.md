# アナリティクス用サーバー

YouTube と Google Play の数字を毎週取って、AI に引き渡すためのサーバー側の道具。仕組みの全体・安全の設計・運用は [docs/analytics-pipeline.md](../../docs/analytics-pipeline.md)。

```
server/
  analytics/   取得・集計・検証・通知のスクリプト      → 運用ユーザーの ~/analytics/
  bin/         Claude を動かすスクリプト (root 所有)     → /usr/local/bin/
  systemd/     service と timer                         → /etc/systemd/system/
deploy.sh      server/ をサーバーに入れる / 現物と比べる
deploy.env     環境の値 (ユーザー名など。git に入れない)。deploy.env.example を写す
```

`server/` の中は、ユーザー名やパスを `@OPS_USER@` `@OPS_HOME@` `@BOT_USER@` `@BOT_HOME@` `@SSH_HOST@` の目印にしてある(公開リポジトリのため)。`deploy.sh` が、`deploy.env` の値に置き換えて配置する。

```sh
cp tools/analytics-server/deploy.env.example tools/analytics-server/deploy.env   # 値を書く
tools/analytics-server/deploy.sh check    # サーバーの現物と比べる (何も変えない)
tools/analytics-server/deploy.sh apply    # 入れる (systemd の再読み込みと timer の有効化まで)
```

## 役割の分け方

- **運用ユーザー**: 鍵を持つ。取得・集計・検証・通知を動かす。
- **Claude 用ユーザー**: sudo なし、鍵なし。集計済みの事実を読んで、分析と提案を書くだけ(ツールは使わせない)。

## 初めて作るとき(`deploy.sh` がしないこと)

1. 2 つのユーザーを作る(Claude 用は `adduser --disabled-password`)。Claude Code は、Claude 用ユーザーに入れて、一度ログインしておく。
2. 運用ユーザーの `~/analytics/state/` に、鍵を置く(権限 600)。置くものと作り方は、[docs/analytics-pipeline.md](../../docs/analytics-pipeline.md) の「運用」。
3. `deploy.sh apply`。
4. `deploy.sh check` で一致を確かめ、`sudo systemctl start yt-weekly-fetch.service` で通しで 1 回動かす。

## 直すときの決まり

サーバー上で直接直したら、同じ変更をこのリポジトリの `server/` にも入れる(目印に戻して)。`deploy.sh check` が、差を教える。**鍵・Webhook の URL・バケット名・プロジェクトの ID などは、リポジトリに入れない**(`state/` にだけ置く)。
