#!/bin/sh
# 宣伝動画に使う、リポジトリに入れない素材 (フォントと、ストアの公式バッジ) を取ってくる。
#   promo/build/fetch_assets.sh
# - フォント: DotGothic16 (SIL OFL)。ゲーム内の文字と同じ系統。
# - バッジ: App Store と Google Play の公式の日本語版。絵は変えず、大きさだけ変える。
#   使い方の決まりは、Apple と Google のバッジのガイドラインに従う。
# 要るもの: curl、ffmpeg (librsvg 入り。SVG のバッジを PNG にする)。入れ方は promo/README.md の「要るもの」。
# Linux と macOS の両方で動くように、GNU だけのオプションは使わない。
set -eu
cd "$(dirname "$0")"
command -v curl >/dev/null 2>&1 || { echo "curl がない (promo/README.md の「要るもの」)" >&2; exit 1; }
mkdir -p fonts assets/badges

[ -f fonts/DotGothic16-Regular.ttf ] || curl -fL -o fonts/DotGothic16-Regular.ttf \
  "https://github.com/google/fonts/raw/main/ofl/dotgothic16/DotGothic16-Regular.ttf"

# Google Play のバッジ (PNG)
[ -f assets/badges/googleplay.png ] || curl -fL -o assets/badges/googleplay.png \
  "https://play.google.com/intl/en_us/badges/static/images/badges/ja_badge_web_generic.png"

# App Store のバッジ (SVG)。表示サイズだけ 8 倍にして PNG にする (ffmpeg が必要)
if [ ! -f assets/badges/appstore.png ]; then
  command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg がない (promo/README.md の「要るもの」)" >&2; exit 1; }
  ffmpeg -hide_banner -decoders 2>/dev/null | grep -q librsvg || {
    echo "この ffmpeg は SVG を読めない (librsvg なし)。promo/README.md の「要るもの」の入れ方で入れ直す" >&2; exit 1; }
  curl -fL -o assets/badges/appstore.svg \
    "https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/ja-jp?size=250x83"
  # 拡張子 .svg の一時ファイル。mktemp --suffix は GNU だけなので、一時ディレクトリの中に作る
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT
  sed 's/width="108.85157" height="40"/width="871" height="320"/' assets/badges/appstore.svg > "$tmpdir/appstore.svg"
  ffmpeg -y -v error -i "$tmpdir/appstore.svg" -frames:v 1 assets/badges/appstore.png
fi
echo "素材をそろえた: promo/build/fonts, promo/build/assets/badges"
