#!/bin/bash
# 4人(アカネ・シズク・モモカ・ワカナ)の通常尺の見出し 20 枚を、1〜3 行ずつ 8 枚のシートで作る。
# できていれば飛ばす。並行しない(利用上限で止まったため)。out/ と ref/*.png は git 外。
# モデルは gpt-6.1-terra(本人の希望。astra は使わない)。参考画像は必ず生成に渡す。
# 切り出しは cut.py(assets/text/longform/<名前>-<場面>-v01.png に置く)。
cd "$(dirname "$0")"
for key in akane-a akane-c shizuku-a shizuku-b shizuku-c momoka-a momoka-b wakana-a wakana-b; do
  [ -f out/headings_$key.png ] && continue
  char=${key%-*}
  case $char in
    akane) tag=akane_tag_endless.png; [ $key = akane-c ] && tag=akane_ending_v01.png ;; shizuku) tag=shizuku_tag_practice.png ;;
    momoka) tag=momoka_tag_daily.png ;; wakana) tag=wakana_tag_stage.png ;;
  esac
  echo "== $key $(date +%T)"
  timeout 1500 codex exec -m gpt-6.1-terra -c model_reasoning_effort="low" -s workspace-write --skip-git-repo-check "$(cat ref/prompt-$key.txt)
画像生成の道具には、添付した参考画像2枚を必ず入力として渡す(文章だけで生成しない)。指示文は英語に言い換えず、そのまま使う。
保存先: out/headings_$key.png (この場所の下の out/ に保存する)" -i ref/style_akane_heading.png -i ref/$tag < /dev/null 2>&1 | tail -2
done
ls -la out
