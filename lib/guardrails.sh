#!/usr/bin/env bash
# ============================================================================
# lib/guardrails.sh — Diff size and scope guardrails
#
# Enforces limits on how much the agent can change per round:
#   - Max lines changed
#   - Max files changed
#   - Allowed/denied directories
#   - Forbidden file patterns
#
# Usage:
#   source lib/guardrails.sh
#   check_guardrails "/path/to/project"
# ============================================================================

MAX_LINES_CHANGED="${MAX_LINES_CHANGED:-500}"
MAX_FILES_CHANGED="${MAX_FILES_CHANGED:-20}"
GUARDRAIL_ACTION="${GUARDRAIL_ACTION:-warn}"  # warn, block, revert

# Check if recent changes exceed guardrails
check_guardrails() {
    local project_dir="${1:-.}"
    local since_commit="${2:-}"  # If empty, checks uncommitted + last commit

    cd "$project_dir" || return 1

    if ! git rev-parse --git-dir &>/dev/null; then
        return 0  # Not a git repo, skip
    fi

    local violations=()

    # ── Check diff size ──
    local diff_stat
    if [ -n "$since_commit" ]; then
        diff_stat=$(git diff --stat "$since_commit"..HEAD 2>/dev/null)
    else
        diff_stat=$(git diff --stat HEAD~1 2>/dev/null || git diff --stat 2>/dev/null)
    fi

    # Extract lines changed (insertions + deletions)
    local lines_changed=0
    if [ -n "$diff_stat" ]; then
        local insertions deletions
        insertions=$(echo "$diff_stat" | tail -1 | grep -o '[0-9]* insertion' | grep -o '[0-9]*' || echo "0")
        deletions=$(echo "$diff_stat" | tail -1 | grep -o '[0-9]* deletion' | grep -o '[0-9]*' || echo "0")
        lines_changed=$((${insertions:-0} + ${deletions:-0}))
    fi

    if [ "$lines_changed" -gt "$MAX_LINES_CHANGED" ]; then
        violations+=("Lines changed: $lines_changed (max: $MAX_LINES_CHANGED)")
    fi

    # ── Check files changed count ──
    local files_changed=0
    if [ -n "$since_commit" ]; then
        files_changed=$(git diff --name-only "$since_commit"..HEAD 2>/dev/null | wc -l | tr -d ' ')
    else
        files_changed=$(git diff --name-only HEAD~1 2>/dev/null | wc -l | tr -d ' ')
    fi

    if [ "$files_changed" -gt "$MAX_FILES_CHANGED" ]; then
        violations+=("Files changed: $files_changed (max: $MAX_FILES_CHANGED)")
    fi

    # ── Check scope restrictions ──
    if [ -n "${PROJECT_SCOPE_EXCLUDE:-}" ]; then
        local changed_files
        if [ -n "$since_commit" ]; then
            changed_files=$(git diff --name-only "$since_commit"..HEAD 2>/dev/null)
        else
            changed_files=$(git diff --name-only HEAD~1 2>/dev/null)
        fi

        IFS=',' read -ra excluded_dirs <<< "$PROJECT_SCOPE_EXCLUDE"
        for dir in "${excluded_dirs[@]}"; do
            dir=$(echo "$dir" | xargs)  # trim whitespace
            local out_of_scope
            out_of_scope=$(echo "$changed_files" | grep "^${dir}" || true)
            if [ -n "$out_of_scope" ]; then
                violations+=("Files modified in excluded scope '$dir': $(echo "$out_of_scope" | wc -l | tr -d ' ') file(s)")
            fi
        done
    fi

    # ── Check for sensitive files ──
    local sensitive_patterns=(".env" "credentials" "secret" "token" ".pem" ".key" "id_rsa")
    local changed_files_all
    if [ -n "$since_commit" ]; then
        changed_files_all=$(git diff --name-only "$since_commit"..HEAD 2>/dev/null)
    else
        changed_files_all=$(git diff --name-only HEAD~1 2>/dev/null)
    fi

    for pattern in "${sensitive_patterns[@]}"; do
        local matches
        matches=$(echo "$changed_files_all" | grep -i "$pattern" 2>/dev/null || true)
        if [ -n "$matches" ]; then
            violations+=("Sensitive file modified: $matches")
        fi
    done

    # ── Report ──
    if [ ${#violations[@]} -eq 0 ]; then
        echo "Guardrails: ALL CLEAR (${lines_changed} lines, ${files_changed} files)"
        return 0
    fi

    echo "## Guardrail Violations"
    for v in "${violations[@]}"; do
        echo "  WARNING: $v"
    done

    case "$GUARDRAIL_ACTION" in
        block)
            echo "  Action: BLOCKING — changes exceed guardrails"
            return 1
            ;;
        revert)
            echo "  Action: REVERTING last commit"
            git revert --no-edit HEAD 2>/dev/null || true
            return 1
            ;;
        warn)
            echo "  Action: WARNING only — proceeding"
            return 0
            ;;
    esac
}

# Pre-round check: ensure guardrails config is loaded
init_guardrails() {
    MAX_LINES_CHANGED="${MAX_LINES_CHANGED:-500}"
    MAX_FILES_CHANGED="${MAX_FILES_CHANGED:-20}"
    GUARDRAIL_ACTION="${GUARDRAIL_ACTION:-warn}"
    echo "Guardrails: max_lines=$MAX_LINES_CHANGED, max_files=$MAX_FILES_CHANGED, action=$GUARDRAIL_ACTION"
}
