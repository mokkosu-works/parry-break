#!/bin/bash
# 毎朝のサーバー状態レポート。@BOT_USER@（sudoなし）が、読み取り専用のコマンドだけで作る。
set -euo pipefail
export HOME=@BOT_HOME@
export PATH=@BOT_HOME@/.local/bin:/usr/local/bin:/usr/bin:/bin
cd @BOT_HOME@/work
OUT=@BOT_HOME@/reports/$(date +%F).md
BACKUP_FACTS=$(cat /run/claude-report/backup-facts.txt 2>/dev/null || echo "バックアップ状況の取得に失敗 [NG]")
PROMPT="このサーバーの朝の状態報告を、日本語のMarkdownで作って。確認する項目: 稼働時間、ディスク使用率(/)、メモリとスワップの使用量、失敗しているsystemdサービス(systemctl --failed)、バックアップの状況。
バックアップの状況は、次の事実をそのまま表にして載せること（数値や判定を変えない）:
${BACKUP_FACTS}
判定: ディスクの空きが20%未満、失敗サービスあり、スワップを大きく使用、バックアップに[NG]が1つでもある、のいずれかに当てはまる場合は、先頭に「要確認」と書き、理由を1行で添える。問題がなければ先頭に「異常なし」と書く。読み取りのみで、何も変更しないこと。"
timeout 300 claude -p "$PROMPT" --allowedTools "Bash(uptime:*) Bash(df:*) Bash(free:*) Bash(systemctl --failed:*)" > "$OUT"
install -m 644 "$OUT" /srv/analytics/reports/
find @BOT_HOME@/reports -name "*.md" -mtime +90 -delete
