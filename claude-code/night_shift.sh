#!/usr/bin/env bash
# ============================================================================
# AI Night Shift — Claude Code Module
# Autonomous night shift runner for Claude Code CLI
#
# Usage:
#   ./night_shift.sh [--max-rounds 5] [--window-hours 6] [--prompt prompt.txt]
#
# Features:
#   - Runs multiple autonomous rounds within a configurable time window
#   - Automatic rate-limit detection and retry (waits 60 min)
#   - PID locking to prevent concurrent runs
#   - Per-round timeout with graceful shutdown buffer
#   - Generates structured reports for each round
#   - Integrates with cross-agent protocols (night_chat, bot_inbox)
# ============================================================================

set -euo pipefail

# ── Configuration (override via env or flags) ──
NIGHT_SHIFT_DIR="${NIGHT_SHIFT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
LOGS_DIR="${NIGHT_SHIFT_DIR}/logs"
REPORTS_DIR="${NIGHT_SHIFT_DIR}/reports"
PROMPT_FILE="${NIGHT_SHIFT_DIR}/claude-code/prompt_template.txt"
PID_FILE="${NIGHT_SHIFT_DIR}/logs/night_shift.pid"
NIGHT_CHAT="${NIGHT_SHIFT_DIR}/protocols/night_chat.md"

MAX_ROUNDS="${MAX_ROUNDS:-5}"
WINDOW_HOURS="${WINDOW_HOURS:-6}"
ROUND_TIMEOUT="${ROUND_TIMEOUT:-9000}"  # seconds per round (2.5h default)
RATE_LIMIT_WAIT="${RATE_LIMIT_WAIT:-3600}"  # seconds to wait on rate limit
SHUTDOWN_BUFFER="${SHUTDOWN_BUFFER:-300}"  # 5 min buffer before window ends

# Claude Code binary
CLAUDE_BIN="${CLAUDE_BIN:-claude}"

# ── Parse arguments ──
while [[ $# -gt 0 ]]; do
    case $1 in
        --max-rounds) MAX_ROUNDS="$2"; shift 2 ;;
        --window-hours) WINDOW_HOURS="$2"; shift 2 ;;
        --prompt) PROMPT_FILE="$2"; shift 2 ;;
        --timeout) ROUND_TIMEOUT="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--max-rounds N] [--window-hours H] [--prompt FILE] [--timeout SEC]"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Setup ──
mkdir -p "$LOGS_DIR" "$REPORTS_DIR"
WINDOW_END=$(($(date +%s) + WINDOW_HOURS * 3600))
DATE_TAG=$(date +%Y-%m-%d)
SESSION_LOG="${LOGS_DIR}/session_${DATE_TAG}.log"

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" | tee -a "$SESSION_LOG"
}

cleanup() {
    rm -f "$PID_FILE"
    log "Night shift session ended"
}
trap cleanup EXIT

# ── PID Lock ──
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        log "ERROR: Night shift already running (PID $OLD_PID)"
        exit 1
    else
        log "WARN: Stale PID file found, cleaning up"
        rm -f "$PID_FILE"
    fi
fi
echo $$ > "$PID_FILE"

# ── Validate prompt file ──
if [ ! -f "$PROMPT_FILE" ]; then
    log "ERROR: Prompt file not found: $PROMPT_FILE"
    exit 1
fi

# ── Main Loop ──
log "=== Night Shift Started ==="
log "Config: max_rounds=$MAX_ROUNDS, window=${WINDOW_HOURS}h, timeout=${ROUND_TIMEOUT}s"
log "Prompt: $PROMPT_FILE"
log "Window ends at: $(date -d @$WINDOW_END '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r $WINDOW_END '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo $WINDOW_END)"

ROUND=0
while [ $ROUND -lt $MAX_ROUNDS ]; do
    ROUND=$((ROUND + 1))
    NOW=$(date +%s)
    REMAINING=$((WINDOW_END - NOW))

    # Check if window is expiring
    if [ $REMAINING -le $SHUTDOWN_BUFFER ]; then
        log "Window expiring in ${REMAINING}s (buffer=${SHUTDOWN_BUFFER}s), stopping"
        break
    fi

    # Calculate round timeout (min of configured timeout and remaining window)
    EFFECTIVE_TIMEOUT=$ROUND_TIMEOUT
    if [ $((REMAINING - SHUTDOWN_BUFFER)) -lt $EFFECTIVE_TIMEOUT ]; then
        EFFECTIVE_TIMEOUT=$((REMAINING - SHUTDOWN_BUFFER))
    fi

    log "--- Round $ROUND/$MAX_ROUNDS (timeout: ${EFFECTIVE_TIMEOUT}s) ---"

    # Write round start to night_chat
    if [ -f "$NIGHT_CHAT" ] || [ -d "$(dirname "$NIGHT_CHAT")" ]; then
        echo "[$(date '+%H:%M')] NightShift: Round $ROUND started" >> "$NIGHT_CHAT" 2>/dev/null || true
    fi

    # Build the prompt with context injection
    ROUND_PROMPT=$(cat "$PROMPT_FILE")
    ROUND_PROMPT="${ROUND_PROMPT/\{ROUND\}/$ROUND}"
    ROUND_PROMPT="${ROUND_PROMPT/\{MAX_ROUNDS\}/$MAX_ROUNDS}"
    ROUND_PROMPT="${ROUND_PROMPT/\{DATE\}/$DATE_TAG}"
    ROUND_PROMPT="${ROUND_PROMPT/\{REMAINING_TIME\}/$((REMAINING / 60)) minutes}"

    # Execute Claude Code
    ROUND_REPORT="${REPORTS_DIR}/${DATE_TAG}_round${ROUND}.md"
    ROUND_EXIT=0

    timeout "$EFFECTIVE_TIMEOUT" $CLAUDE_BIN \
        --print \
        --dangerously-skip-permissions \
        -p "$ROUND_PROMPT" \
        > "$ROUND_REPORT" 2>&1 || ROUND_EXIT=$?

    # Handle exit codes
    case $ROUND_EXIT in
        0)
            log "Round $ROUND completed successfully"
            ;;
        124)
            log "Round $ROUND timed out (${EFFECTIVE_TIMEOUT}s)"
            ;;
        *)
            # Check for rate limit in output
            if grep -qi "rate.limit\|too many\|429\|quota" "$ROUND_REPORT" 2>/dev/null; then
                log "Rate limit detected, waiting ${RATE_LIMIT_WAIT}s..."
                if [ -f "$NIGHT_CHAT" ] || [ -d "$(dirname "$NIGHT_CHAT")" ]; then
                    echo "[$(date '+%H:%M')] NightShift: Rate limited, waiting $(( RATE_LIMIT_WAIT / 60 ))min" >> "$NIGHT_CHAT" 2>/dev/null || true
                fi
                sleep "$RATE_LIMIT_WAIT"
                ROUND=$((ROUND - 1))  # Retry this round
                continue
            fi
            log "Round $ROUND failed with exit code $ROUND_EXIT"
            ;;
    esac

    # Write round summary to night_chat
    if [ -f "$NIGHT_CHAT" ] || [ -d "$(dirname "$NIGHT_CHAT")" ]; then
        SUMMARY=$(tail -5 "$ROUND_REPORT" 2>/dev/null | head -3)
        echo "[$(date '+%H:%M')] NightShift: Round $ROUND done — ${SUMMARY:-no output}" >> "$NIGHT_CHAT" 2>/dev/null || true
    fi

    # Brief pause between rounds
    sleep 5
done

# ── Generate Summary ──
SUMMARY_FILE="${REPORTS_DIR}/${DATE_TAG}_summary.md"
{
    echo "# Night Shift Report — $DATE_TAG"
    echo ""
    echo "- Rounds completed: $ROUND / $MAX_ROUNDS"
    echo "- Window: ${WINDOW_HOURS}h"
    echo "- Started: $(head -1 "$SESSION_LOG" 2>/dev/null | sed 's/\[//;s/\].*//')"
    echo "- Ended: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "## Round Reports"
    for f in "${REPORTS_DIR}/${DATE_TAG}_round"*.md; do
        if [ -f "$f" ]; then
            echo ""
            echo "### $(basename "$f" .md)"
            echo '```'
            head -20 "$f"
            echo '```'
        fi
    done
} > "$SUMMARY_FILE"

log "Summary written to $SUMMARY_FILE"
log "=== Night Shift Complete ($ROUND rounds) ==="
