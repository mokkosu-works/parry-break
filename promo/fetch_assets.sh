#!/bin/sh
# 宣伝動画に使う、リポジトリに入れない素材 (フォントと、ストアの公式バッジ) を取ってくる。
#   promo/fetch_assets.sh
# - フォント: DotGothic16 (SIL OFL)。ゲーム内の文字と同じ系統。
# - バッジ: App Store と Google Play の公式の日本語版。絵は変えず、大きさだけ変える。
#   使い方の決まりは、Apple と Google のバッジのガイドラインに従う。
set -eu
cd "$(dirname "$0")"
mkdir -p fonts assets/badges

[ -f fonts/DotGothic16-Regular.ttf ] || curl -fL -o fonts/DotGothic16-Regular.ttf \
  "https://github.com/google/fonts/raw/main/ofl/dotgothic16/DotGothic16-Regular.ttf"

# Google Play のバッジ (PNG)
[ -f assets/badges/googleplay.png ] || curl -fL -o assets/badges/googleplay.png \
  "https://play.google.com/intl/en_us/badges/static/images/badges/ja_badge_web_generic.png"

# App Store のバッジ (SVG)。表示サイズだけ 8 倍にして PNG にする (ffmpeg が必要)
if [ ! -f assets/badges/appstore.png ]; then
  curl -fL -o assets/badges/appstore.svg \
    "https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/ja-jp?size=250x83"
  tmp=$(mktemp --suffix=.svg)
  sed 's/width="108.85157" height="40"/width="871" height="320"/' assets/badges/appstore.svg > "$tmp"
  ffmpeg -y -v error -i "$tmp" -frames:v 1 assets/badges/appstore.png
  rm -f "$tmp"
fi
echo "素材をそろえた: promo/fonts, promo/assets/badges"
