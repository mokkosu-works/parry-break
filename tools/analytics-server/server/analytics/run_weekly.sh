#!/bin/bash
# 週次: YouTube と Google Play から取得 → 事実 (集計) を作る → @BOT_USER@ が読める場所に写す。@OPS_USER@ で動く。
# Play の取得が失敗しても、YouTube の週次は止めない。
set -uo pipefail
cd @OPS_HOME@/analytics
rc=0
python3 weekly.py run || rc=1
LATEST=$(ls -1 data/facts/2*.md 2>/dev/null | tail -1)
[ -n "$LATEST" ] && install -m 644 "$LATEST" /srv/analytics/facts/ && echo "facts 公開: $(basename "$LATEST")"
[ -n "$LATEST" ] && install -m 644 "${LATEST%.md}.json" /srv/analytics/facts/ && echo "facts(JSON) 公開: $(basename "${LATEST%.md}.json")"
if python3 play_weekly.py run; then
  P=$(ls -1 data/facts/play-*.md | tail -1)
  install -m 644 "$P" /srv/analytics/facts/ && echo "facts 公開: $(basename "$P")"
else
  echo "Play の取得に失敗 (YouTube の分は続行)"
fi
exit $rc
