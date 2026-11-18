#!/bin/bash
# アカネのショート(冒頭を作り直した版)の見出しと吹き出し。並行しない。out/ と ref/*.png は git 外。
# モデルは gpt-6.1-terra。参考画像は必ず生成に渡す。
cd "$(dirname "$0")"
for key in headline bubble; do
  [ -f out/$key.png ] && continue
  echo "== $key $(date +%T)"
  timeout 1500 codex exec -m gpt-6.1-terra -c model_reasoning_effort="low" -s workspace-write --skip-git-repo-check "$(cat ref/prompt-$key.txt)
画像生成の道具には、添付した参考画像を必ず入力として渡す(文章だけで生成しない)。指示文は英語に言い換えず、そのまま使う。
保存先: out/$key.png (この場所の下の out/ に保存する)" -i ref/style_$key.png < /dev/null 2>&1 | tail -2
done
ls -la out
