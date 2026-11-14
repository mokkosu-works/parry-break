#!/usr/bin/env bash
# 実機 (撮影用ビルド入り、デバッグモード済み) でステージを選び、映像と音を録画する。
# 使い方: promo/capture/capture.sh <ステージ 例 2-7> <腕前ラベル 例 sloppy> <テイク番号 例 01> [録画秒数=45]
# 保存先: promo/capture/raw/s<ステージ>_<ラベル>_<テイク>.mp4 (あるファイルは上書きせず、そこで止まる)
# 録画の前の端末の状態は promo/README.md の「録画の前に」を見る。
set -euo pipefail
cd "$(dirname "$0")"
die() { echo "capture.sh: $*" >&2; exit 1; }
# 要るもの: adb、scrcpy 2.6 以上、timeout (macOS は coreutils の gtimeout)。promo/README.md の「要るもの」
for c in adb scrcpy; do command -v "$c" >/dev/null 2>&1 || die "$c がない (promo/README.md の「要るもの」)"; done
if command -v timeout >/dev/null 2>&1; then timeout_cmd=timeout
elif command -v gtimeout >/dev/null 2>&1; then timeout_cmd=gtimeout
else die "timeout がない。macOS は brew install coreutils で gtimeout を入れる"; fi
[ $# -ge 3 ] || die "使い方: promo/capture/capture.sh <ステージ 例 2-7> <腕前ラベル> <テイク番号> [録画秒数=45]"
stage=$1; label=$2; take=$3; secs=${4:-45}
ch=${stage%-*}; n=${stage#*-}
[[ $ch =~ ^[0-9]+$ && $n =~ ^[0-9]+$ ]] || die "ステージは <章>-<番号> の形で書く: $stage"
# 章の数 (campaign.json の ch01, ch02, …)
chapters=$(grep -o '"id": *"ch[0-9]*"' ../../app/assets/stages/campaign.json | wc -l | tr -d ' ')
[ "$ch" -ge 1 ] && [ "$ch" -le "$chapters" ] || die "章は 1〜$chapters: $stage"
[ "$n" -ge 1 ] && [ "$n" -le 9 ] || die "ボス (x-10) は撮らない: $stage"
mkdir -p raw
out="raw/s${stage}_${label}_${take}.mp4"
log="raw/s${stage}_${label}_${take}.log"
[ -e "$out" ] && die "既にある: $out"

# 端末: つながっていて、画面が 2400x1080 (下のタップの座標はこの解像度の値)
[ "$(adb get-state 2>/dev/null)" = device ] || die "adb で端末が見えない、または 2 台以上つながっている (adb devices で確かめる)"
size=$(adb shell wm size | tr -d '\r' | awk -F': *' '/Override size/ {o = $2} /Physical size/ {p = $2} END {print (o != "" ? o : p)}')
case $size in
  2400x1080 | 1080x2400) ;;
  *) die "画面が ${size:-不明} で、2400x1080 ではない (タップの座標が合わない)。adb shell wm size 2400x1080 で合わせるか、2400x1080 の端末を使う" ;;
esac

# ステージ選択の画面 (2400x1080 の横画面) のタイルの位置。1〜5 は上の段を左から、6〜10 は下の段を右から
if [ "$n" -le 5 ]; then x=$((178 + 277 * (n - 1))); y=537; else x=$((1288 - 277 * (n - 6))); y=778; fi
pkg=com.watsuwo.parrybreak
adb shell am force-stop $pkg
adb shell monkey -p $pkg -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 5
adb shell input tap 1650 560; sleep 2          # STAGES
# ステージ選択は「まだクリアしていない最初のステージ」の章で開くので、まず第1章へ戻す。
# ← キーは、段の左端から前の章へ移る (1 章につき最大 5 回)。第1章の左端では何も起きない。
keys=$(printf 'KEYCODE_DPAD_LEFT %.0s' $(seq 1 $((chapters * 5))))
# shellcheck disable=SC2086
adb shell input keyevent $keys; sleep 1
for _ in $(seq 2 "$ch"); do adb shell input tap 1368 222; sleep 1.2; done   # 次の章へ
adb shell input tap $x $y; sleep 1

"$timeout_cmd" "$secs" scrcpy --no-playback --no-control --audio-source=playback --video-bit-rate=16M \
  --max-fps=60 --record="$out" --record-format=mp4 >"$log" 2>&1 &
pid=$!
sleep 3
if ! kill -0 "$pid" 2>/dev/null; then
  # 録画が始まる前に scrcpy が終わった。START は押さない
  wait "$pid" || true
  tail -n 20 "$log" >&2
  die "scrcpy が録画を始められなかった (ログ: promo/capture/$log)"
fi
adb shell input tap 1990 925                   # START
status=0
wait "$pid" || status=$?
# timeout (gtimeout) が秒数で scrcpy を止めたときは 124 (scrcpy は止められても録画を閉じてから終わる)
if [ "$status" -ne 0 ] && [ "$status" -ne 124 ]; then
  tail -n 20 "$log" >&2
  die "scrcpy が失敗した (終了コード $status、ログ: promo/capture/$log)"
fi
if [ ! -s "$out" ]; then
  tail -n 20 "$log" >&2
  rm -f "$out"   # 空のファイルが残ると、次のテイクで「既にある」で止まる
  die "録画のファイルがない、または空: promo/capture/$out (ログ: promo/capture/$log)"
fi
rm -f "$log"
echo "録画: $out"
