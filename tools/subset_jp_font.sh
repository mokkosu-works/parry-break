#!/bin/sh
# 日本語のドット文字 (DotGothic16) を、アプリで使っている文字だけに絞り込んで作る。
# 翻訳ファイルやステージ名に新しい漢字を足したら、作り直す。
#
#   pip install fonttools
#   curl -L -o DotGothic16-Regular.ttf "https://github.com/google/fonts/raw/main/ofl/dotgothic16/DotGothic16-Regular.ttf"
#   tools/subset_jp_font.sh DotGothic16-Regular.ttf
set -eu
src="$1"
cd "$(dirname "$0")/.."
chars=$(mktemp)
# 使っている文字 + ひらがな・カタカナ・記号すべて
cat app/lib/l10n/app_ja.arb app/assets/stages/*.json app/lib/ui/*.dart app/lib/ui/*/*.dart app/lib/game/*.dart \
  app/lib/render/*.dart app/lib/input/*.dart > "$chars"
pyftsubset "$src" \
  --text-file="$chars" \
  --unicodes="U+0020-007E,U+00A0-00FF,U+2000-206F,U+2190-21FF,U+2460-24FF,U+25A0-25FF,U+2600-26FF,U+3000-30FF,U+FF00-FFEF" \
  --layout-features='*' \
  --output-file=app/assets/fonts/DotGothic16-subset.ttf
rm "$chars"
ls -la app/assets/fonts/DotGothic16-subset.ttf
