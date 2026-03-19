#!/usr/bin/env bash
# ============================================================================
# AI Night Shift — Main Runner
# Autonomous night shift runner with pluggable agent adapters
#
# Usage:
#   ./night_shift.sh [--max-rounds 5] [--window-hours 6] [--prompt prompt.txt]
#                    [--adapter claude-code] [--project /path/to/project]
#                    [--dry-run]
#
# Adapters:
#   claude-code  — Claude Code CLI (default)
#   codex-cli    — OpenAI Codex CLI
#   aider        — Aider
#   custom       — Your own agent (copy adapters/custom.sh)
#
# Features:
#   - Runs multiple autonomous rounds within a configurable time window
#   - Automatic rate-limit detection and retry (waits 60 min)
#   - PID locking to prevent concurrent runs
#   - Per-round timeout with graceful shutdown buffer
#   - Generates structured reports for each round
#   - Integrates with cross-agent protocols (night_chat, bot_inbox)
#   - Project-aware: reads .nightshift.yml for project configuration
#   - Task integration: fetches tasks from GitHub/Linear/file
#   - Pre-round context injection: git log, CI status, open PRs
#   - Test-before-commit guardrails
#   - Branch & PR workflow management
#   - Multi-project rotation
#   - Structured metrics collection
#   - Diff size guardrails
#   - Dry run mode for previewing behavior
# ============================================================================

set -euo pipefail

# ── Load config (YAML or env) ──
NIGHT_SHIFT_DIR="${NIGHT_SHIFT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
if [ -f "${NIGHT_SHIFT_DIR}/lib/yaml_config.sh" ]; then
    # shellcheck source=/dev/null
    source "${NIGHT_SHIFT_DIR}/lib/yaml_config.sh"
    load_config "$NIGHT_SHIFT_DIR"
elif [ -f "${NIGHT_SHIFT_DIR}/config.env" ]; then
    # shellcheck source=/dev/null
    source "${NIGHT_SHIFT_DIR}/config.env"
fi

# ── Configuration (override via env or flags) ──
LOGS_DIR="${NIGHT_SHIFT_DIR}/logs"
REPORTS_DIR="${NIGHT_SHIFT_DIR}/reports"
METRICS_DIR="${METRICS_DIR:-$REPORTS_DIR}"
PROMPT_FILE="${NIGHT_SHIFT_DIR}/claude-code/prompt_template.txt"
NIGHT_CHAT="${NIGHT_SHIFT_DIR}/protocols/night_chat.md"

MAX_ROUNDS="${MAX_ROUNDS:-5}"
WINDOW_HOURS="${WINDOW_HOURS:-6}"
ROUND_TIMEOUT="${ROUND_TIMEOUT:-9000}"  # seconds per round (2.5h default)
RATE_LIMIT_WAIT="${RATE_LIMIT_WAIT:-3600}"  # seconds to wait on rate limit
SHUTDOWN_BUFFER="${SHUTDOWN_BUFFER:-300}"  # 5 min buffer before window ends
COMPLETION_SIGNAL="${COMPLETION_SIGNAL:-NIGHT_SHIFT_COMPLETE}"  # Agent signals "done"
COMPLETION_THRESHOLD="${COMPLETION_THRESHOLD:-2}"  # Consecutive signals to stop
SHARED_NOTES="${NIGHT_SHIFT_DIR}/protocols/examples/shared_task_notes.md"

# Agent adapter (claude-code, codex-cli, aider, or custom)
AGENT_ADAPTER="${AGENT_ADAPTER:-claude-code}"

# Agent binary (override to use a custom path)
AGENT_BIN="${AGENT_BIN:-}"

# Permission mode: set to "true" ONLY if you understand the risks.
SKIP_PERMISSIONS="${SKIP_PERMISSIONS:-false}"

# Project directory (for project-aware features)
PROJECT_DIR="${PROJECT_DIR:-}"

# Dry run mode
DRY_RUN="${DRY_RUN:-false}"

# ── Parse arguments ──
while [[ $# -gt 0 ]]; do
    case $1 in
        --max-rounds) MAX_ROUNDS="$2"; shift 2 ;;
        --window-hours) WINDOW_HOURS="$2"; shift 2 ;;
        --prompt) PROMPT_FILE="$2"; shift 2 ;;
        --timeout) ROUND_TIMEOUT="$2"; shift 2 ;;
        --adapter) AGENT_ADAPTER="$2"; shift 2 ;;
        --project) PROJECT_DIR="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --max-rounds N      Maximum rounds per shift (default: 5)"
            echo "  --window-hours H    Time window in hours (default: 6)"
            echo "  --prompt FILE       Prompt template file"
            echo "  --timeout SEC       Timeout per round in seconds"
            echo "  --adapter NAME      Agent adapter: claude-code, codex-cli, aider, custom"
            echo "  --project DIR       Target project directory"
            echo "  --dry-run           Preview what would happen without executing"
            echo "  --help              Show this help message"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Load lib modules ──
for lib_file in \
    "${NIGHT_SHIFT_DIR}/lib/project_config.sh" \
    "${NIGHT_SHIFT_DIR}/lib/task_router.sh" \
    "${NIGHT_SHIFT_DIR}/lib/context_collector.sh" \
    "${NIGHT_SHIFT_DIR}/lib/verify.sh" \
    "${NIGHT_SHIFT_DIR}/lib/git_workflow.sh" \
    "${NIGHT_SHIFT_DIR}/lib/guardrails.sh" \
    "${NIGHT_SHIFT_DIR}/lib/metrics.sh" \
    "${NIGHT_SHIFT_DIR}/lib/task_queue.sh" \
    "${NIGHT_SHIFT_DIR}/lib/project_router.sh"; do
    if [ -f "$lib_file" ]; then
        # shellcheck source=/dev/null
        source "$lib_file"
    fi
done

# ── Load agent adapter ──
ADAPTER_FILE="${NIGHT_SHIFT_DIR}/adapters/${AGENT_ADAPTER}.sh"
if [ ! -f "$ADAPTER_FILE" ]; then
    echo "ERROR: Adapter not found: $ADAPTER_FILE"
    echo "Available adapters:"
    find "${NIGHT_SHIFT_DIR}/adapters/" -maxdepth 1 -name "*.sh" -exec basename {} .sh \;
    exit 1
fi
# shellcheck source=/dev/null
source "$ADAPTER_FILE"

# Verify the agent CLI is installed (skip in dry run)
if [ "$DRY_RUN" != "true" ] && ! adapter_verify; then
    echo "ERROR: $(adapter_name) CLI not found. Install it first."
    exit 1
fi

# ── Setup ──
mkdir -p "$LOGS_DIR" "$REPORTS_DIR"
WINDOW_END=$(($(date +%s) + WINDOW_HOURS * 3600))
DATE_TAG=$(date +%Y-%m-%d)
SESSION_LOG="${LOGS_DIR}/session_${DATE_TAG}.log"

log() {
    local msg
    msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" | tee -a "$SESSION_LOG"
}

LOCK_DIR="${LOGS_DIR}/night_shift.lock"

cleanup() {
    # Collect final metrics
    if [ -n "${PROJECT_DIR:-}" ] && type collect_metrics &>/dev/null; then
        collect_metrics "$PROJECT_DIR" "$ROUND" "${SESSION_START:-$(date +%s)}" 2>/dev/null || true
    fi

    # Finish git workflow (push & create PR)
    if [ -n "${PROJECT_DIR:-}" ] && [ "$DRY_RUN" != "true" ] && type workflow_finish &>/dev/null; then
        log "Finishing git workflow..."
        workflow_finish "$PROJECT_DIR" "Completed $ROUND rounds" 2>/dev/null || true
    fi

    rm -rf "$LOCK_DIR"
    log "Night shift session ended"
}
trap cleanup EXIT

# ── PID Lock (atomic mkdir to prevent TOCTOU race) ──
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    OLD_PID=$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "")
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        log "ERROR: Night shift already running (PID $OLD_PID)"
        exit 1
    else
        log "WARN: Stale lock found, cleaning up"
        rm -rf "$LOCK_DIR"
        mkdir "$LOCK_DIR"
    fi
fi
echo $$ > "$LOCK_DIR/pid"

# ── Validate prompt file ──
if [ ! -f "$PROMPT_FILE" ]; then
    log "ERROR: Prompt file not found: $PROMPT_FILE"
    exit 1
fi

# ── Project-aware initialization ──
if [ -n "$PROJECT_DIR" ]; then
    # Load project config (.nightshift.yml or auto-detect)
    if type load_project_config &>/dev/null; then
        load_project_config "$PROJECT_DIR"
        log "Project: $PROJECT_NAME ($PROJECT_LANGUAGE)"
    fi

    # Initialize task backend
    if type init_task_backend &>/dev/null; then
        init_task_backend "${TASK_TOOL:-}" 2>/dev/null || true
    fi

    # Initialize task queue
    if type queue_init &>/dev/null; then
        queue_init "${NIGHT_SHIFT_DIR}/protocols/task_queue.json" 2>/dev/null || true
    fi

    # Initialize guardrails
    if type init_guardrails &>/dev/null; then
        init_guardrails 2>/dev/null || true
    fi

    # Start git workflow (create branch)
    if [ "$DRY_RUN" != "true" ] && type workflow_start &>/dev/null; then
        workflow_start "$PROJECT_DIR" 2>/dev/null || true
    fi
elif [ -n "${PROJECT_DIRS:-}" ] && type init_project_router &>/dev/null; then
    # Multi-project mode
    init_project_router 2>/dev/null || true
fi

SESSION_START=$(date +%s)

# ── Dry Run Mode ──
if [ "$DRY_RUN" = "true" ]; then
    log "=== DRY RUN MODE ==="
    log "Config: max_rounds=$MAX_ROUNDS, window=${WINDOW_HOURS}h, timeout=${ROUND_TIMEOUT}s"
    log "Agent: $(adapter_name 2>/dev/null || echo "$AGENT_ADAPTER") (adapter: $AGENT_ADAPTER)"
    log "Prompt: $PROMPT_FILE"

    if [ -n "$PROJECT_DIR" ]; then
        log ""
        log "Project configuration:"
        if type format_project_config &>/dev/null; then
            format_project_config | while IFS= read -r line; do log "  $line"; done
        fi

        log ""
        log "Context that would be collected:"
        if type collect_context_fast &>/dev/null; then
            collect_context_fast "$PROJECT_DIR" 2>/dev/null | while IFS= read -r line; do log "  $line"; done
        fi

        log ""
        log "Tasks that would be fetched:"
        if type fetch_tasks &>/dev/null; then
            fetch_tasks "$PROJECT_DIR" 5 2>/dev/null | while IFS= read -r line; do log "  $line"; done
        fi
    fi

    log ""
    log "Prompt template preview (first 20 lines):"
    head -20 "$PROMPT_FILE" | while IFS= read -r line; do log "  $line"; done

    log ""
    log "=== DRY RUN COMPLETE (no changes made) ==="
    exit 0
fi

# ── Main Loop ──
log "=== Night Shift Started ==="
log "Config: max_rounds=$MAX_ROUNDS, window=${WINDOW_HOURS}h, timeout=${ROUND_TIMEOUT}s"
log "Agent: $(adapter_name) (adapter: $AGENT_ADAPTER)"
log "Prompt: $PROMPT_FILE"
if [ -n "$PROJECT_DIR" ]; then
    log "Project: ${PROJECT_NAME:-$PROJECT_DIR} (${PROJECT_LANGUAGE:-auto})"
fi
log "Window ends at: $(date -d "@$WINDOW_END" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$WINDOW_END" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$WINDOW_END")"

ROUND=0
CONSECUTIVE_COMPLETE=0
while [ "$ROUND" -lt "$MAX_ROUNDS" ]; do
    ROUND=$((ROUND + 1))
    ROUND_START=$(date +%s)
    NOW=$ROUND_START
    REMAINING=$((WINDOW_END - NOW))

    # Check if window is expiring
    if [ "$REMAINING" -le "$SHUTDOWN_BUFFER" ]; then
        log "Window expiring in ${REMAINING}s (buffer=${SHUTDOWN_BUFFER}s), stopping"
        break
    fi

    # Multi-project: select next project for this round
    if [ -z "$PROJECT_DIR" ] && [ -n "${PROJECT_DIRS:-}" ] && type select_next_project &>/dev/null; then
        PROJECT_DIR=$(select_next_project 2>/dev/null)
        if [ -n "$PROJECT_DIR" ]; then
            log "Selected project: $PROJECT_DIR"
            load_project_config "$PROJECT_DIR" 2>/dev/null || true
            init_task_backend "${TASK_TOOL:-}" 2>/dev/null || true
        fi
    fi

    # Calculate round timeout (min of configured timeout and remaining window)
    EFFECTIVE_TIMEOUT=$ROUND_TIMEOUT
    if [ "$((REMAINING - SHUTDOWN_BUFFER))" -lt "$EFFECTIVE_TIMEOUT" ]; then
        EFFECTIVE_TIMEOUT=$((REMAINING - SHUTDOWN_BUFFER))
    fi

    log "--- Round $ROUND/$MAX_ROUNDS (timeout: ${EFFECTIVE_TIMEOUT}s) ---"

    # Write round start to night_chat
    if [ -f "$NIGHT_CHAT" ] || [ -d "$(dirname "$NIGHT_CHAT")" ]; then
        echo "[$(date '+%H:%M')] NightShift: Round $ROUND started" >> "$NIGHT_CHAT" 2>/dev/null || true
    fi

    # ── Collect context for this round ──
    NOTES_CONTEXT=""
    if [ -f "$SHARED_NOTES" ]; then
        NOTES_CONTEXT=$(cat "$SHARED_NOTES")
    fi

    # Project context (git state, CI, PRs)
    PROJECT_CONTEXT=""
    if [ -n "$PROJECT_DIR" ] && type collect_context &>/dev/null; then
        PROJECT_CONTEXT=$(collect_context "$PROJECT_DIR" 2>/dev/null) || true
    fi

    # Task list
    TASK_LIST=""
    if type fetch_tasks &>/dev/null; then
        TASK_LIST=$(fetch_tasks "${PROJECT_DIR:-.}" 10 2>/dev/null) || true
    fi

    # Task queue (cross-round)
    TASK_QUEUE_CONTENT=""
    if type format_task_queue &>/dev/null; then
        TASK_QUEUE_CONTENT=$(format_task_queue "pending" 2>/dev/null) || true
    fi

    # Project config summary
    PROJECT_CONFIG=""
    if type format_project_config &>/dev/null; then
        PROJECT_CONFIG=$(format_project_config 2>/dev/null) || true
    fi

    # ── Build prompt with all context ──
    ROUND_PROMPT=$(cat "$PROMPT_FILE")
    ROUND_PROMPT="${ROUND_PROMPT//\{ROUND\}/$ROUND}"
    ROUND_PROMPT="${ROUND_PROMPT//\{MAX_ROUNDS\}/$MAX_ROUNDS}"
    ROUND_PROMPT="${ROUND_PROMPT//\{DATE\}/$DATE_TAG}"
    ROUND_PROMPT="${ROUND_PROMPT//\{REMAINING_TIME\}/$((REMAINING / 60)) minutes}"
    ROUND_PROMPT="${ROUND_PROMPT//\{SHARED_NOTES\}/$NOTES_CONTEXT}"
    ROUND_PROMPT="${ROUND_PROMPT//\{PROJECT_CONTEXT\}/$PROJECT_CONTEXT}"
    ROUND_PROMPT="${ROUND_PROMPT//\{TASK_LIST\}/$TASK_LIST}"
    ROUND_PROMPT="${ROUND_PROMPT//\{TASK_QUEUE\}/$TASK_QUEUE_CONTENT}"
    ROUND_PROMPT="${ROUND_PROMPT//\{PROJECT_CONFIG\}/$PROJECT_CONFIG}"

    # Execute agent via adapter
    ROUND_REPORT="${REPORTS_DIR}/${DATE_TAG}_round${ROUND}.md"
    ROUND_EXIT=0

    adapter_run "$ROUND_PROMPT" "$ROUND_REPORT" "$EFFECTIVE_TIMEOUT" || ROUND_EXIT=$?

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
            if adapter_check_rate_limit "$ROUND_REPORT"; then
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

    # ── Post-round: verification & guardrails ──
    if [ -n "$PROJECT_DIR" ]; then
        # Run test verification
        if type verify_project &>/dev/null && [ -n "${PROJECT_TEST_CMD:-}" ]; then
            local verify_result="${REPORTS_DIR}/${DATE_TAG}_verify_round${ROUND}.txt"
            log "Running post-round verification..."
            verify_project "$PROJECT_DIR" "$verify_result" 2>/dev/null || \
                log "WARN: Verification found failures (see $verify_result)"
        fi

        # Check guardrails
        if type check_guardrails &>/dev/null; then
            check_guardrails "$PROJECT_DIR" 2>/dev/null || \
                log "WARN: Guardrail violations detected"
        fi

        # Collect metrics
        if type collect_metrics &>/dev/null; then
            collect_metrics "$PROJECT_DIR" "$ROUND" "$ROUND_START" "$ROUND_REPORT" 2>/dev/null || true
        fi

        # Record project round (multi-project mode)
        if type record_project_round &>/dev/null; then
            record_project_round "$PROJECT_DIR" "ok" 2>/dev/null || true
        fi
    fi

    # Check for completion signal (agent says "I'm done")
    if adapter_check_completion "$ROUND_REPORT" "$COMPLETION_SIGNAL"; then
        CONSECUTIVE_COMPLETE=$((CONSECUTIVE_COMPLETE + 1))
        log "Completion signal detected ($CONSECUTIVE_COMPLETE/$COMPLETION_THRESHOLD)"
        if [ "$CONSECUTIVE_COMPLETE" -ge "$COMPLETION_THRESHOLD" ]; then
            log "Completion threshold reached, stopping early"
            break
        fi
    else
        CONSECUTIVE_COMPLETE=0
    fi

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
    if [ -n "${PROJECT_NAME:-}" ]; then
        echo "- Project: $PROJECT_NAME ($PROJECT_LANGUAGE)"
    fi
    if [ -n "${NIGHTSHIFT_BRANCH:-}" ]; then
        echo "- Branch: $NIGHTSHIFT_BRANCH"
    fi
    echo ""

    # Include metrics if available
    if type format_metrics &>/dev/null; then
        format_metrics 2>/dev/null || true
        echo ""
    fi

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
