#!/usr/bin/env bash
# ============================================================================
# AI Night Shift — Direct Message Between Agents
# Sends a message to another agent's inbox
#
# Usage:
#   ./msg.sh <target_agent> "Your message here"
#   ./msg.sh --task TASK-42 <target_agent> "Please review the PR"
# ============================================================================

set -euo pipefail

NIGHT_SHIFT_DIR="${NIGHT_SHIFT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
INBOX_BASE="${NIGHT_SHIFT_DIR}/protocols/bot_inbox"
NIGHT_CHAT="${NIGHT_SHIFT_DIR}/protocols/night_chat.md"

TASK_ID=""

# Parse optional flags
while [[ $# -gt 0 ]]; do
    case $1 in
        --task) TASK_ID="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--task TASK_ID] <target_agent> \"message\""
            exit 0
            ;;
        *) break ;;
    esac
done

if [ $# -lt 2 ]; then
    echo "Usage: $0 [--task TASK_ID] <target_agent> \"message\""
    exit 1
fi

TARGET="$1"
MESSAGE="$2"
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
SENDER="${AGENT_NAME:-unknown}"

# Auto-detect sender
if [ "$SENDER" = "unknown" ]; then
    if command -v claude &>/dev/null && [ -n "${CLAUDE_SESSION:-}" ]; then
        SENDER="claude"
    elif command -v gemini &>/dev/null; then
        SENDER="gemini"
    else
        SENDER=$(hostname -s 2>/dev/null || echo "agent")
    fi
fi

# Create target inbox
TARGET_INBOX="${INBOX_BASE}/${TARGET}"
mkdir -p "$TARGET_INBOX"

# Build message JSON
FILENAME="msg_$(date +%s)_${RANDOM}.json"
TASK_FIELD=""
if [ -n "$TASK_ID" ]; then
    TASK_FIELD="\"task_id\": \"${TASK_ID}\","
fi

cat > "${TARGET_INBOX}/${FILENAME}" << EOF
{
  "from": "${SENDER}",
  "to": "${TARGET}",
  "type": "message",
  ${TASK_FIELD}
  "message": "${MESSAGE}",
  "ts": "${TIMESTAMP}"
}
EOF

# Log to night_chat
if [ -d "$(dirname "$NIGHT_CHAT")" ]; then
    echo "[$(date '+%H:%M')] ${SENDER} → ${TARGET}: ${MESSAGE}" >> "$NIGHT_CHAT" 2>/dev/null || true
fi

echo "Message sent to ${TARGET}"
