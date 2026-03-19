#!/usr/bin/env bash
# PLUGIN_NAME: CI Feedback Loop
# PLUGIN_PHASE: post
#
# ci_feedback.sh — Watches CI after push and triggers fix-up if failed
#
# Phase: post (runs after each night shift round)
# Purpose: After the agent pushes code, check if CI passes.
#          If CI fails, create a fix-up task in the task queue.
#
# Requirements: gh CLI authenticated, GitHub Actions CI
#
# Usage:
#   Enable by copying to plugins/post/ci_feedback.sh
#
# Configuration:
#   CI_FEEDBACK_WAIT=60       # Seconds to wait for CI to start
#   CI_FEEDBACK_TIMEOUT=600   # Max seconds to wait for CI completion
#   CI_FEEDBACK_RETRY=false   # Auto-create fix task on failure

set -euo pipefail

CI_FEEDBACK_WAIT="${CI_FEEDBACK_WAIT:-60}"
CI_FEEDBACK_TIMEOUT="${CI_FEEDBACK_TIMEOUT:-600}"
CI_FEEDBACK_RETRY="${CI_FEEDBACK_RETRY:-false}"

NIGHT_SHIFT_DIR="${NIGHT_SHIFT_DIR:-$(cd "$(dirname "$(realpath "$0")")/../.." && pwd)}"

log() { echo "[ci_feedback] $(date '+%H:%M:%S') $1"; }

check_ci() {
    # Verify gh is available
    if ! command -v gh &>/dev/null; then
        log "SKIP: gh CLI not found"
        return 0
    fi

    if ! gh auth status &>/dev/null 2>&1; then
        log "SKIP: gh not authenticated"
        return 0
    fi

    # Get current branch
    local branch
    branch=$(git branch --show-current 2>/dev/null)
    if [ -z "$branch" ]; then
        log "SKIP: Not on a branch"
        return 0
    fi

    # Wait for CI to start
    log "Waiting ${CI_FEEDBACK_WAIT}s for CI to start on branch $branch..."
    sleep "$CI_FEEDBACK_WAIT"

    # Poll for CI completion
    local elapsed=0
    local interval=30
    local status=""

    while [ "$elapsed" -lt "$CI_FEEDBACK_TIMEOUT" ]; do
        # Get the latest run for this branch
        local run_info
        run_info=$(gh run list --branch "$branch" --limit 1 \
            --json databaseId,status,conclusion,name \
            --jq '.[0] | "\(.databaseId) \(.status) \(.conclusion // "pending") \(.name)"' 2>/dev/null)

        if [ -z "$run_info" ]; then
            log "No CI runs found for branch $branch"
            return 0
        fi

        local run_id run_status run_conclusion run_name
        run_id=$(echo "$run_info" | awk '{print $1}')
        run_status=$(echo "$run_info" | awk '{print $2}')
        run_conclusion=$(echo "$run_info" | awk '{print $3}')
        run_name=$(echo "$run_info" | awk '{$1=$2=$3=""; print $0}' | xargs)

        case "$run_status" in
            completed)
                if [ "$run_conclusion" = "success" ]; then
                    log "CI PASSED: $run_name (#$run_id)"
                    return 0
                else
                    log "CI FAILED: $run_name (#$run_id) — conclusion: $run_conclusion"
                    _handle_ci_failure "$run_id" "$run_name" "$branch"
                    return 1
                fi
                ;;
            *)
                log "CI still running ($run_status)... waiting ${interval}s"
                sleep "$interval"
                elapsed=$((elapsed + interval))
                ;;
        esac
    done

    log "CI timeout after ${CI_FEEDBACK_TIMEOUT}s — status unknown"
    return 0
}

_handle_ci_failure() {
    local run_id="$1"
    local run_name="$2"
    local branch="$3"

    # Fetch failure details
    local failure_log
    failure_log=$(gh run view "$run_id" --log-failed 2>/dev/null | tail -30)

    # Log to night_chat
    local night_chat="${NIGHT_SHIFT_DIR}/protocols/night_chat.md"
    if [ -d "$(dirname "$night_chat")" ]; then
        {
            echo "[$(date '+%H:%M')] CI_FEEDBACK: CI failed on $branch"
            echo "  Run: $run_name (#$run_id)"
            echo "  Last 5 lines: $(echo "$failure_log" | tail -5 | tr '\n' ' ')"
        } >> "$night_chat" 2>/dev/null || true
    fi

    # Add to task queue if enabled
    if [ "$CI_FEEDBACK_RETRY" = "true" ]; then
        if [ -f "${NIGHT_SHIFT_DIR}/lib/task_queue.sh" ]; then
            # shellcheck source=/dev/null
            source "${NIGHT_SHIFT_DIR}/lib/task_queue.sh"
            queue_init "${NIGHT_SHIFT_DIR}/protocols/task_queue.json"
            queue_add "Fix CI failure: $run_name on $branch (run #$run_id)" "urgent" "ci"
            log "Created fix-up task in task queue"
        fi
    fi
}

# === Main ===
check_ci
