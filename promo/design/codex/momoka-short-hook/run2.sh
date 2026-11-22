#!/bin/bash
# モモカのショート v017 の吹き出しをセリフに合わせて作り直す (冒頭と締め)。並行しない。out/ と ref/*.png は git 外。
# モデルは gpt-6.1-terra。参考画像は必ず生成に渡す。
cd "$(dirname "$0")"
for key in bubble-hook2 bubble-end; do
  [ -f out/$key.png ] && continue
  echo "== $key $(date +%T)"
  timeout 1500 codex exec -m gpt-6.1-terra -c model_reasoning_effort="low" -s workspace-write --skip-git-repo-check "$(cat ref/prompt-$key.txt)
画像生成の道具には、添付した参考画像を必ず入力として渡す(文章だけで生成しない)。指示文は英語に言い換えず、そのまま使う。
保存先: out/$key.png (この場所の下の out/ に保存する)" -i ref/style_bubble.png < /dev/null 2>&1 | tail -2
done
ls -la out
