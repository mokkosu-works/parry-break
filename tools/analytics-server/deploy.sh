#!/bin/bash
# アナリティクス用サーバーの配置。リポジトリの server/ を、環境の値に置き換えて、サーバーに入れる。
#
#   tools/analytics-server/deploy.sh check    # サーバーの現物と、リポジトリの内容を比べる (何も変えない)
#   tools/analytics-server/deploy.sh apply    # サーバーに入れる (systemd の再読み込みと、timer の有効化まで)
#
# 環境の値は deploy.env に書く (deploy.env.example を写す。deploy.env は git に入れない)。
# 鍵 (YouTube・Play・Discord の Webhook) は、このスクリプトは扱わない。サーバーの state/ に、手で置く (docs/analytics-pipeline.md)。
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
MODE=${1:-}
[ "$MODE" = check ] || [ "$MODE" = apply ] || { sed -n '2,8p' "$0"; exit 2; }
[ -f "$HERE/deploy.env" ] || { echo "deploy.env がない。deploy.env.example を写して、値を書く"; exit 1; }
# shellcheck disable=SC1091
. "$HERE/deploy.env"
: "${SSH_HOST:?}" "${OPS_USER:?}" "${OPS_HOME:?}" "${BOT_USER:?}" "${BOT_HOME:?}"

TIMERS="claude-morning-report.timer yt-weekly-fetch.timer yt-weekly-report.timer play-watch.timer"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

render() { sed -e "s|@OPS_HOME@|$OPS_HOME|g; s|@BOT_HOME@|$BOT_HOME|g; s|@OPS_USER@|$OPS_USER|g; s|@BOT_USER@|$BOT_USER|g; s|@SSH_HOST@|$SSH_HOST|g" "$1"; }

# 置き場所の対応: server/analytics → $OPS_HOME/analytics、server/bin → /usr/local/bin、server/systemd → /etc/systemd/system
dest_of() {
  case "$1" in
    analytics/*) echo "$OPS_HOME/analytics/$(basename "$1")" ;;
    bin/*)       echo "/usr/local/bin/$(basename "$1")" ;;
    systemd/*)   echo "/etc/systemd/system/$(basename "$1")" ;;
  esac
}

cd "$HERE/server"
FILES=$(find analytics bin systemd -type f | sort)
for f in $FILES; do mkdir -p "$WORK/$(dirname "$f")"; render "$f" > "$WORK/$f"; done

if [ "$MODE" = check ]; then
  bad=0
  for f in $FILES; do
    want=$(sha256sum < "$WORK/$f" | cut -d' ' -f1)
    have=$(ssh "$SSH_HOST" "sudo sha256sum '$(dest_of "$f")' 2>/dev/null" | cut -d' ' -f1 || true)
    if [ "$want" = "$have" ]; then echo "一致   $f"; else echo "違う   $f  (サーバーに無いか、内容が違う)"; bad=$((bad+1)); fi
  done
  [ "$bad" -eq 0 ] && echo "すべて一致" || { echo "$bad 件が違う"; exit 1; }
  exit 0
fi

# apply
ssh "$SSH_HOST" "mkdir -p /tmp/analytics-deploy && rm -rf /tmp/analytics-deploy/*"
scp -q -r "$WORK/analytics" "$WORK/bin" "$WORK/systemd" "$SSH_HOST:/tmp/analytics-deploy/"
ssh "$SSH_HOST" "set -e; cd /tmp/analytics-deploy
  sudo mkdir -p /srv/analytics/facts /srv/analytics/handoff && sudo chown -R $OPS_USER:$OPS_USER /srv/analytics
  sudo mkdir -p /srv/analytics/reports && sudo chown $BOT_USER:$BOT_USER /srv/analytics/reports
  sudo chmod 755 /srv/analytics /srv/analytics/facts /srv/analytics/handoff /srv/analytics/reports
  mkdir -p '$OPS_HOME/analytics/state' && chmod 700 '$OPS_HOME/analytics' '$OPS_HOME/analytics/state'
  install -m 755 analytics/* '$OPS_HOME/analytics/'
  sudo install -o root -g root -m 755 bin/* /usr/local/bin/
  sudo install -o root -g root -m 644 systemd/* /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable --now $TIMERS
  rm -rf /tmp/analytics-deploy"
echo "配置した。次に、'check' で一致を確かめる"
