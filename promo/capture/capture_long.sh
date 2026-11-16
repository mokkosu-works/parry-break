#!/usr/bin/env bash
# 撮影用 .promo アプリの映像と出来事ログを同時に保存する。
# 使い方: bash promo/capture/capture_long.sh <endless|daily|practice|stage> <テイク> [秒=120]
set -euo pipefail
cd "$(dirname "$0")/../.."
exec python3 promo/capture/capture_long.py "$@"
