#!/bin/bash
# 全身シートの口パク・目パチ用の素材を Codex で作る (できていれば飛ばす。並行しない)。out/ は git 外
# 使い方: run.sh <名前> [<名前>...]   例: run.sh mitsuba
# モデルは gpt-6.1-terra(本人の希望。astra は使わない)。参考画像は必ず生成に渡す
cd "$(dirname "$0")"
for c in "$@"; do
  [ -f ref/${c}_sheet.png ] || cp ../../../characters/sheets/${c}_sheet.png ref/${c}_sheet.png
  for kind in mouth blink; do
    [ -f out/${c}_${kind}.png ] && continue
    [ -f ref/prompt-$c-$kind.txt ] || { echo "指示文がありません: ref/prompt-$c-$kind.txt"; continue; }
    echo "== $c $kind $(date +%T)"
    timeout 1500 codex exec -m gpt-6.1-terra -c model_reasoning_effort="low" -s workspace-write --skip-git-repo-check "$(cat ref/prompt-$c-$kind.txt)
画像生成の道具には、添付した参考画像を必ず入力として渡す(文章だけで生成しない)。指示文は英語に言い換えず、そのまま使う。
保存先: out/${c}_${kind}.png (この場所の下の out/ に保存する)" -i ref/${c}_sheet.png < /dev/null 2>&1 | tail -2
  done
done
ls -la out
