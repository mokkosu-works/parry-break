#!/usr/bin/env bash
# 撮影用アプリ (1.5.0 以降、ストア版と並べて入れた com.watsuwo.parrybreak.promo) で、
# タイトル画面から録画を始め、モードを選んで遊ぶところまでを撮る。モード紹介の動画用。
#
# 使い方: promo/capture/capture_mode.sh <モード> <テイク番号 例 01> [録画秒数]
#   title     タイトル画面でメニューのカーソルを上下に動かす (既定 14 秒)
#   endless   ENDLESS を選んで遊ぶ (既定 120 秒。ボスの出る R10 の前に止める)
#   daily     DAILY を選んで遊ぶ (既定 90 秒)
#   practice  PRACTICE を選んで遊ぶ (既定 45 秒)
#   stage     STAGES → 1-1 → START で遊び、クリアの結果まで (既定 100 秒)
# 保存先: promo/capture/raw/m<モード>_<テイク>.mp4 (あるファイルは上書きせず止まる)
#
# 撮影用アプリの作り方は promo/README.md。タップの座標は 2400x1080 の横画面の値。
set -euo pipefail
cd "$(dirname "$0")"
die() { echo "capture_mode.sh: $*" >&2; exit 1; }
[ $# -ge 2 ] || die "使い方: promo/capture/capture_mode.sh <title|endless|daily|practice|stage> <テイク番号> [録画秒数]"
mode=$1; take=$2
case $mode in
  title) secs=${3:-14} ;;
  endless) secs=${3:-120} ;;
  daily) secs=${3:-90} ;;
  practice) secs=${3:-45} ;;
  stage) secs=${3:-100} ;;
  *) die "モードは title / endless / daily / practice / stage のどれか: $mode" ;;
esac
pkg=${PROMO_PKG:-com.watsuwo.parrybreak.promo}
mkdir -p raw
out="raw/m${mode}_${take}.mp4"
log="raw/m${mode}_${take}.log"
[ -e "$out" ] && die "既にある: $out"
[ "$(adb get-state 2>/dev/null)" = device ] || die "adb で端末が見えない、または 2 台以上つながっている"
size=$(adb shell wm size | tr -d '\r' | awk -F': *' '/Override size/ {o = $2} /Physical size/ {p = $2} END {print (o != "" ? o : p)}')
case $size in 2400x1080 | 1080x2400) ;; *) die "画面が ${size:-不明} で、2400x1080 ではない" ;; esac
adb shell pm path "$pkg" >/dev/null 2>&1 || die "撮影用アプリ $pkg が入っていない"

adb shell am force-stop "$pkg"
adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 6

timeout "$secs" scrcpy --no-playback --no-control --audio-source=playback --video-bit-rate=16M \
  --max-fps=60 --record="$out" --record-format=mp4 >"$log" 2>&1 &
pid=$!
sleep 3
kill -0 "$pid" 2>/dev/null || { wait "$pid" || true; tail -n 20 "$log" >&2; die "scrcpy が録画を始められなかった"; }
sleep 1.5   # タイトル画面を少し見せてから選ぶ

case $mode in
  title)
    for k in DOWN DOWN UP UP DOWN; do adb shell input keyevent "KEYCODE_DPAD_$k"; sleep 1.6; done ;;
  endless) adb shell input tap 1740 392 ;;
  stages | stage)
    adb shell input tap 1720 506; sleep 2.5      # STAGES
    adb shell input tap 291 535; sleep 2         # 1-1
    adb shell input tap 2102 927 ;;              # START
  daily) adb shell input tap 430 870 ;;
  practice) adb shell input tap 470 976 ;;
esac

status=0
wait "$pid" || status=$?
if [ "$status" -ne 0 ] && [ "$status" -ne 124 ]; then tail -n 20 "$log" >&2; die "scrcpy が失敗した (終了コード $status)"; fi
[ -s "$out" ] || { tail -n 20 "$log" >&2; rm -f "$out"; die "録画のファイルが空"; }
rm -f "$log"
adb shell am force-stop "$pkg"
echo "録画: $out"
