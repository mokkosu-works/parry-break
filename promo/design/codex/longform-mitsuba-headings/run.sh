#!/bin/bash
# ミツバの通常尺の見出し 9 つを、3 行ずつ 3 枚のシートで作る(できていれば飛ばす。並行しない)。out/ は git 外
# モデルは gpt-6.1-terra(本人の希望。astra は使わない)。参考画像は必ず生成に渡す
cd "$(dirname "$0")"
for k in a b c; do
  [ -f out/mitsuba_headings_$k.png ] && continue
  echo "== $k $(date +%T)"
  timeout 1500 codex exec -m gpt-6.1-terra -c model_reasoning_effort="low" -s workspace-write --skip-git-repo-check "$(cat ref/prompt-mitsuba-headings-$k.txt)
画像生成の道具には、添付した参考画像2枚を必ず入力として渡す(文章だけで生成しない)。指示文は英語に言い換えず、そのまま使う。
保存先: out/mitsuba_headings_$k.png (この場所の下の out/ に保存する)" -i ref/style_akane_heading.png -i ref/mitsuba_tag.png < /dev/null 2>&1 | tail -2
done
ls -la out
