#!/usr/bin/env bash
# ============================================================================
# AI Night Shift — Gemini CLI Module
# Periodic patrol runner for Gemini CLI (gemini-cli)
#
# Usage:
#   ./patrol.sh [--prompt prompt_template.txt]
#
# Features:
#   - Lightweight patrol runs (1-5 min each)
#   - Designed for cron execution (e.g., every hour)
#   - Processes inbox messages and assigned tasks
#   - Reports results via configurable output (file, TG, webhook)
#   - Task management integration (Linear, GitHub Issues, etc.)
# ============================================================================

set -euo pipefail

# ── Configuration ──
NIGHT_SHIFT_DIR="${NIGHT_SHIFT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
LOGS_DIR="${NIGHT_SHIFT_DIR}/logs"
INBOX_DIR="${NIGHT_SHIFT_DIR}/protocols/bot_inbox/gemini"
PROMPT_FILE="${NIGHT_SHIFT_DIR}/gemini/prompt_template.txt"
NIGHT_CHAT="${NIGHT_SHIFT_DIR}/protocols/night_chat.md"
OUTPUT_FILE="${NIGHT_SHIFT_DIR}/logs/patrol_output.txt"

# Gemini CLI binary
GEMINI_BIN="${GEMINI_BIN:-gemini}"

# Task management tool (optional)
TASK_TOOL="${TASK_TOOL:-}"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M')
DATE_TAG=$(date +%Y-%m-%d)
PATROL_LOG="${LOGS_DIR}/patrol_${DATE_TAG}.log"

# ── Parse arguments ──
while [[ $# -gt 0 ]]; do
    case $1 in
        --prompt) PROMPT_FILE="$2"; shift 2 ;;
        --output) OUTPUT_FILE="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--prompt FILE] [--output FILE]"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

mkdir -p "$LOGS_DIR" "$INBOX_DIR"

log() {
    echo "[$(date '+%H:%M:%S')] $*" | tee -a "$PATROL_LOG"
}

# ── Collect inbox items ──
INBOX_CONTENT=""
if [ -d "$INBOX_DIR" ] && [ "$(ls -A "$INBOX_DIR" 2>/dev/null | grep -v done)" ]; then
    INBOX_CONTENT=$(python3 -c "
import json, os, glob
inbox = '$INBOX_DIR'
items = []
for f in sorted(glob.glob(os.path.join(inbox, '*.json'))):
    if '/done/' in f:
        continue
    try:
        with open(f) as fh:
            d = json.load(fh)
            t = d.get('type', '?')
            if t == 'linear_task':
                items.append(f'Task [{d.get(\"task_id\",\"\")}] {d.get(\"title\",\"\")} (state: {d.get(\"state\",\"\")})')
            elif t == 'linear_comment':
                items.append(f'Comment [{d.get(\"task_id\",\"\")}] by {d.get(\"by_whom\",\"?\")}')
            elif t == 'message':
                items.append(f'Message from {d.get(\"from\",\"?\")}')
    except Exception:
        pass
for item in items:
    print(item)
" 2>/dev/null || true)
fi

# ── Collect recent night_chat messages ──
RECENT_CHAT=""
if [ -f "$NIGHT_CHAT" ]; then
    RECENT_CHAT=$(tail -10 "$NIGHT_CHAT" 2>/dev/null || true)
fi

# ── Build prompt ──
if [ ! -f "$PROMPT_FILE" ]; then
    log "ERROR: Prompt file not found: $PROMPT_FILE"
    exit 1
fi

PROMPT=$(cat "$PROMPT_FILE")
PROMPT="${PROMPT/\{TIMESTAMP\}/$TIMESTAMP}"
PROMPT="${PROMPT/\{INBOX\}/${INBOX_CONTENT:-No pending items}}"
PROMPT="${PROMPT/\{RECENT_CHAT\}/${RECENT_CHAT:-No recent messages}}"

# ── Execute Gemini CLI ──
log "Patrol started"

RESULT=$($GEMINI_BIN -p "$PROMPT" --yolo 2>&1 | grep -v "^Loaded cached\|^\[ERROR\]\|^$" | head -30) || true

if [ -n "$RESULT" ]; then
    # Write output
    echo "$RESULT" > "$OUTPUT_FILE"

    # Append to night_chat
    if [ -d "$(dirname "$NIGHT_CHAT")" ]; then
        echo "[$(date '+%H:%M')] GeminiPatrol: $( echo "$RESULT" | head -3 | tr '\n' ' ')" >> "$NIGHT_CHAT" 2>/dev/null || true
    fi

    # Move processed inbox items to done
    if [ -d "$INBOX_DIR" ]; then
        mkdir -p "$INBOX_DIR/done"
        mv "$INBOX_DIR"/*.json "$INBOX_DIR/done/" 2>/dev/null || true
    fi

    log "Patrol complete: $(echo "$RESULT" | wc -l) lines output"
else
    log "Patrol complete: no actionable items"
fi
