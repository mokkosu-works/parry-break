#!/bin/bash
# ミツバのショートの見出し 2 と吹き出し 4 を作り直す(「面」をやめる・締めを通常尺への案内に)。mitsuba2/ は git 外
# モデルは gpt-6.1-terra(astra は使わない)。参考画像は必ず生成に渡す
cd "$(dirname "$0")"
mkdir -p mitsuba2
timeout 1500 codex exec -m gpt-6.1-terra -c model_reasoning_effort="low" -s workspace-write --skip-git-repo-check "$(cat ref/prompt-mitsuba-fix.txt)
画像生成の道具には、添付した参考画像2枚を必ず入力として渡す(文章だけで生成しない)。指示文は英語に言い換えず、そのまま使う。" -i ref/style_mitsuba_headline.png -i ref/style_mitsuba_bubble.png < /dev/null 2>&1 | tail -5
ls -la mitsuba2
