#!/usr/bin/env bash
# ============================================================================
# AI Night Shift — Cross-Agent Notification
# Sends task completion notifications to other agents via bot_inbox
#
# Usage:
#   ./notify.sh <target_agent> <task_id> <status> <summary>
#
# Example:
#   ./notify.sh gemini TASK-42 success "Auth module refactored, 12 tests passing"
#   ./notify.sh claude BUG-7 failed "Could not reproduce — need more info"
# ============================================================================

set -euo pipefail

NIGHT_SHIFT_DIR="${NIGHT_SHIFT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
INBOX_BASE="${NIGHT_SHIFT_DIR}/protocols/bot_inbox"
NIGHT_CHAT="${NIGHT_SHIFT_DIR}/protocols/night_chat.md"

if [ $# -lt 4 ]; then
    echo "Usage: $0 <target_agent> <task_id> <status> <summary>"
    echo "  target_agent: claude, gemini, heartbeat, or any agent name"
    echo "  task_id:      task identifier (e.g., TASK-42)"
    echo "  status:       success | failed | blocked"
    echo "  summary:      one-line description of the result"
    exit 1
fi

TARGET="$1"
TASK_ID="$2"
STATUS="$3"
SUMMARY="$4"
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
SENDER="${AGENT_NAME:-unknown}"

# Determine sender from environment or hostname
if [ "$SENDER" = "unknown" ]; then
    if command -v claude &>/dev/null && [ -n "${CLAUDE_SESSION:-}" ]; then
        SENDER="claude"
    elif command -v gemini &>/dev/null; then
        SENDER="gemini"
    else
        SENDER=$(hostname -s 2>/dev/null || echo "agent")
    fi
fi

# Create target inbox directory
TARGET_INBOX="${INBOX_BASE}/${TARGET}"
mkdir -p "$TARGET_INBOX"

# Write notification JSON
FILENAME="result_${TASK_ID}_$(date +%s).json"
cat > "${TARGET_INBOX}/${FILENAME}" << EOF
{
  "from": "${SENDER}",
  "to": "${TARGET}",
  "type": "result",
  "task_id": "${TASK_ID}",
  "status": "${STATUS}",
  "summary": "${SUMMARY}",
  "ts": "${TIMESTAMP}"
}
EOF

# Also log to night_chat
if [ -d "$(dirname "$NIGHT_CHAT")" ]; then
    STATUS_ICON="✅"
    [ "$STATUS" = "failed" ] && STATUS_ICON="❌"
    [ "$STATUS" = "blocked" ] && STATUS_ICON="🚧"
    echo "[$(date '+%H:%M')] ${SENDER} → ${TARGET}: ${STATUS_ICON} ${TASK_ID} — ${SUMMARY}" >> "$NIGHT_CHAT" 2>/dev/null || true
fi

echo "Notification sent to ${TARGET}: ${TASK_ID} (${STATUS})"
