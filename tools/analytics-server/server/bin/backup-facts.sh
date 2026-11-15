#!/bin/bash
# root で実行。バックアップの鮮度を「事実」として出力する（判定は [OK]/[NG] まで機械的に行う）。
set -u
NOW=$(date +%s); TODAY=$(date +%F)
if [ $# -gt 0 ]; then targets=("$@"); else targets=(@OPS_HOME@/backups/* /srv/backup/*); fi
for d in "${targets[@]}"; do
  [ -d "$d" ] || continue
  name=$(basename "$d")
  snaps=$(ls -1 "$d" | grep -E "^[0-9]{4}-[0-9]{2}-[0-9]{2}$" || true)
  if [ -z "$snaps" ]; then echo "$name: スナップショットなし [NG]"; continue; fi
  latest=$(echo "$snaps" | tail -1); count=$(echo "$snaps" | wc -l)
  partial=$(ls -1 "$d" | grep -c "\.partial$" || true)
  age=$(( (NOW - $(date -d "$latest" +%s)) / 86400 ))
  status=OK
  [ "$latest" != "$TODAY" ] && status=NG
  [ "$partial" -gt 0 ] && status=NG
  echo "$name: 最新=$latest (${age}日前) 世代数=$count 途中失敗の残骸=$partial [$status]"
done
