#!/bin/bash
# クラウドセッション用: Flutter SDK を入れて、テスト・解析・Web ビルドができるようにする。
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# app/.metadata の revision と同じ stable
FLUTTER_VERSION="3.47.6"
FLUTTER_HOME="${FLUTTER_HOME:-$HOME/flutter}"
APP_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}/app"

if [ ! -x "$FLUTTER_HOME/bin/flutter" ]; then
  tmp="$(mktemp -d)"
  curl -fsSL --retry 4 --retry-delay 3 \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    -o "$tmp/flutter.tar.xz"
  mkdir -p "$(dirname "$FLUTTER_HOME")"
  tar -xJf "$tmp/flutter.tar.xz" -C "$(dirname "$FLUTTER_HOME")"
  rm -rf "$tmp"
fi

export PATH="$FLUTTER_HOME/bin:$PATH"
export CHROME_EXECUTABLE="${CHROME_EXECUTABLE:-/opt/pw-browsers/chromium}"
git config --global --add safe.directory "$FLUTTER_HOME" 2>/dev/null || true

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  {
    echo "export PATH=\"$FLUTTER_HOME/bin:\$PATH\""
    echo "export CHROME_EXECUTABLE=\"$CHROME_EXECUTABLE\""
    echo 'export CI=true'
  } >> "$CLAUDE_ENV_FILE"
fi

flutter config --no-analytics --no-cli-animations >/dev/null 2>&1 || true
flutter precache --web >/dev/null
(cd "$APP_DIR" && flutter pub get)

# Web 版の動作確認 (tools/web_check) 用。Chromium は環境に入っている
(cd "${CLAUDE_PROJECT_DIR:-$(pwd)}/tools/web_check" && npm install --no-audit --no-fund --silent)
