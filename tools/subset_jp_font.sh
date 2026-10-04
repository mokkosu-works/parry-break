#!/bin/sh
# Web 版 (開発用プレビュー) のための日本語フォントを、アプリで使っている文字だけに絞り込んで作る。
# 翻訳ファイルやステージ名に新しい漢字を足したら、作り直す。
#
#   pip install fonttools
#   curl -L -o NotoSansJP.ttf "https://github.com/google/fonts/raw/main/ofl/notosansjp/NotoSansJP%5Bwght%5D.ttf"
#   tools/subset_jp_font.sh NotoSansJP.ttf
set -eu
src="$1"
cd "$(dirname "$0")/.."
chars=$(mktemp)
# 使っている文字 + ひらがな・カタカナ・記号すべて
cat app/lib/l10n/app_ja.arb app/assets/stages/*.json app/lib/ui/*.dart app/lib/render/*.dart > "$chars"
pyftsubset "$src" \
  --text-file="$chars" \
  --unicodes="U+0020-007E,U+00A0-00FF,U+2000-206F,U+2190-21FF,U+2460-24FF,U+25A0-25FF,U+3000-30FF,U+FF00-FFEF" \
  --layout-features='*' \
  --output-file=app/assets/fonts/NotoSansJP-subset.ttf
rm "$chars"
ls -la app/assets/fonts/NotoSansJP-subset.ttf
