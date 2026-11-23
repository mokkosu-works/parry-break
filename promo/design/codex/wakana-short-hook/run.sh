#!/bin/bash
# ワカナのショート(v014 の型、冒頭に COLLAPSE)の見出しと吹き出し。並行しない。out/ と ref/*.png は git 外。
# モデルは gpt-6.1-terra。参考画像は必ず生成に渡す。「ストアで検索!」は shorts-play/wakana_v05_store_search.png をそのまま使う。
# 吹き出しは白の中が半透明でしみに見えたので、明るい画素 (min>200) を (253,253,253) の不透明に直してから assets/ に置いた (out/bubbleN-clean.png)。
cd "$(dirname "$0")"
for key in headline bubble1 bubble2 bubble3 bubble4; do
  [ -f out/$key.png ] && continue
  style=bubble; [ $key = headline ] && style=headline
  echo "== $key $(date +%T)"
  timeout 1500 codex exec -m gpt-6.1-terra -c model_reasoning_effort="low" -s workspace-write --skip-git-repo-check "$(cat ref/prompt-$key.txt)
画像生成の道具には、添付した参考画像を必ず入力として渡す(文章だけで生成しない)。指示文は英語に言い換えず、そのまま使う。
保存先: out/$key.png (この場所の下の out/ に保存する)" -i ref/style_$style.png < /dev/null 2>&1 | tail -2
done
ls -la out
