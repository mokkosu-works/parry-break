#!/usr/bin/env bash
# 実機 (撮影用ビルド入り、デバッグモード済み) でステージを選び、映像と音を録画する。
# 使い方: promo/capture.sh <ステージ 例 2-7> <腕前ラベル 例 sloppy> <テイク番号 例 01> [録画秒数=45]
# 保存先: promo/raw/s<ステージ>_<ラベル>_<テイク>.mp4 (あるファイルは上書きせず、そこで止まる)
set -euo pipefail
cd "$(dirname "$0")"
stage=$1; label=$2; take=$3; secs=${4:-45}
ch=${stage%-*}; n=${stage#*-}
out="raw/s${stage}_${label}_${take}.mp4"
[ -e "$out" ] && { echo "既にある: $out" >&2; exit 1; }
[ "$n" -ge 1 ] && [ "$n" -le 9 ] || { echo "ボス (x-10) は撮らない: $stage" >&2; exit 1; }
# ステージ選択の画面 (2400x1080 の横画面) のタイルの位置。1〜5 は上の段を左から、6〜10 は下の段を右から
if [ "$n" -le 5 ]; then x=$((178 + 277 * (n - 1))); y=537; else x=$((1288 - 277 * (n - 6))); y=778; fi
pkg=com.watsuwo.parrybreak
adb shell am force-stop $pkg
adb shell monkey -p $pkg -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 5
adb shell input tap 1650 560; sleep 2          # STAGES
for _ in $(seq 2 "$ch"); do adb shell input tap 1368 222; sleep 1.2; done   # 次の章へ
adb shell input tap $x $y; sleep 1
timeout "$secs" scrcpy --no-playback --no-control --audio-source=playback --video-bit-rate=16M \
  --max-fps=60 --record="$out" --record-format=mp4 >/dev/null 2>&1 &
sleep 3
adb shell input tap 1990 925                   # START
wait
echo "録画: $out"
