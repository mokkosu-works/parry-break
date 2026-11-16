#!/bin/bash
# 4 人のバストアップのシートを Codex で 1 枚ずつ作る (並行しない)。できたものは飛ばす
cd "$(dirname "$0")"
for c in mitsuba shizuku momoka wakana; do
  for n in 1 2 3; do
    [ -f out/${c}_bust_sheet$n.png ] && continue
    echo "== $c sheet$n $(date +%T)"
    timeout 1500 codex exec -c model_reasoning_effort="low" -s workspace-write --skip-git-repo-check "$(cat ref/prompt-$c-sheet$n.txt)" -i ref/${c}_sheet.png -i ref/color_roster.png < /dev/null 2>&1 | tail -3
  done
  if [ ! -f out/${c}_bust_blink.png ] && [ -f out/${c}_bust_sheet1.png ]; then
    echo "== $c blink $(date +%T)"
    cp out/${c}_bust_sheet1.png ref/${c}_sheet1_ref.png
    timeout 1500 codex exec -c model_reasoning_effort="low" -s workspace-write --skip-git-repo-check "$(cat ref/prompt-$c-blink.txt)" -i ref/${c}_sheet1_ref.png < /dev/null 2>&1 | tail -3
  fi
done
ls -la out
