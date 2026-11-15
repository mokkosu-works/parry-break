#!/bin/bash
# Play のバケットの権限が効くまで、1 時間おきに確かめる。効いたら 1 回だけ取得して、印を付けて、以後は何もしない。
# AI は使わない (数字を決める判断ではなく、つながるかの確認だけなので、決まった手順で十分)。@OPS_USER@ で動く。
cd @OPS_HOME@/analytics
MARK=state/play_bucket_ok
STATUS=/srv/analytics/facts/play-status.txt
[ -f "$MARK" ] && exit 0
OUT=$(python3 play_fetch.py check 2>&1)
NOW=$(date '+%F %H:%M')
OK=$(echo "$OUT" | grep -c '^\[OK\]')
if [ "$OK" -ge 4 ]; then
  date '+%F %H:%M' > "$MARK"
  python3 play_weekly.py run >/dev/null 2>&1 && install -m 644 "$(ls -1 data/facts/play-2*.md | tail -1)" /srv/analytics/facts/
  echo "バケット接続: OK (最初に確認できた日時 $NOW)。初回の取得も実行した" > "$STATUS"
else
  echo "バケット接続: まだ NG (最後に確認した日時 $NOW。$(echo "$OUT" | grep -m1 -oE '403|404|401' || echo '原因不明'))" > "$STATUS"
fi
chmod 644 "$STATUS"
