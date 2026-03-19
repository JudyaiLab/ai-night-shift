#!/usr/bin/env bash
# PLUGIN_NAME: Cross-Agent Code Review
# PLUGIN_PHASE: post
#
# code_review.sh — Uses a different AI agent to review night shift changes
#
# Phase: post (runs after shift completes)
# Purpose: Get a second opinion on the agent's code changes before
#          a human reviews the PR. Catches obvious issues, security
#          concerns, and style violations.
#
# Requirements: A second AI CLI (gemini, claude, or aider)
#
# Usage:
#   Enable by copying to plugins/post/code_review.sh
#
# Configuration:
#   REVIEWER_CLI=gemini          # Which CLI to use for review
#   REVIEWER_APPROVAL_MODE=yolo  # For gemini
#   REVIEW_DIFF_LIMIT=500        # Max lines of diff to review

set -euo pipefail

NIGHT_SHIFT_DIR="${NIGHT_SHIFT_DIR:-$(cd "$(dirname "$(realpath "$0")")/../.." && pwd)}"
REVIEWER_CLI="${REVIEWER_CLI:-gemini}"
REVIEW_DIFF_LIMIT="${REVIEW_DIFF_LIMIT:-500}"
REVIEW_OUTPUT="${NIGHT_SHIFT_DIR}/reports/$(date +%Y-%m-%d)_code_review.md"

log() { echo "[code_review] $(date '+%H:%M:%S') $1"; }

run_review() {
    # Verify reviewer CLI is available
    if ! command -v "$REVIEWER_CLI" &>/dev/null; then
        log "SKIP: $REVIEWER_CLI CLI not found"
        return 0
    fi

    # Get the diff to review
    local base_branch="${PROJECT_BASE_BRANCH:-main}"
    local diff
    diff=$(git diff "origin/$base_branch"..HEAD 2>/dev/null | head -"$REVIEW_DIFF_LIMIT")

    if [ -z "$diff" ]; then
        log "SKIP: No changes to review"
        return 0
    fi

    local commit_log
    commit_log=$(git log --oneline "origin/$base_branch"..HEAD 2>/dev/null | head -20)

    local file_list
    file_list=$(git diff --name-only "origin/$base_branch"..HEAD 2>/dev/null)

    # Build review prompt
    local review_prompt
    review_prompt=$(cat <<EOF
You are reviewing code changes made by an AI coding agent during an overnight shift.
Review the following diff and provide a brief, actionable review.

Focus on:
1. **Bugs** — Logic errors, off-by-one, null handling
2. **Security** — Injection, exposed secrets, unsafe operations
3. **Breaking changes** — API changes, removed functionality
4. **Test coverage** — Are changes tested?
5. **Code quality** — Readability, naming, dead code

Files changed:
$file_list

Commits:
$commit_log

Diff (first $REVIEW_DIFF_LIMIT lines):
\`\`\`
$diff
\`\`\`

Respond with:
## Code Review Summary
- **Risk level:** LOW / MEDIUM / HIGH
- **Issues found:** [count]

### Issues
[List each issue with file, line, and description]

### Approval
[APPROVE / REQUEST_CHANGES / NEEDS_DISCUSSION]
EOF
)

    log "Running code review with $REVIEWER_CLI..."

    local review_result=""
    case "$REVIEWER_CLI" in
        gemini)
            review_result=$("$REVIEWER_CLI" -p "$review_prompt" --approval-mode yolo 2>/dev/null | head -100) || true
            ;;
        claude)
            review_result=$("$REVIEWER_CLI" --print -p "$review_prompt" 2>/dev/null | head -100) || true
            ;;
        *)
            log "Unsupported reviewer CLI: $REVIEWER_CLI"
            return 0
            ;;
    esac

    if [ -z "$review_result" ]; then
        log "Review returned no output"
        return 0
    fi

    # Save review
    mkdir -p "$(dirname "$REVIEW_OUTPUT")"
    {
        echo "# Code Review — $(date '+%Y-%m-%d %H:%M')"
        echo ""
        echo "Reviewer: $REVIEWER_CLI"
        echo "Branch: $(git branch --show-current 2>/dev/null)"
        echo "Files: $(echo "$file_list" | wc -l | tr -d ' ')"
        echo ""
        echo "$review_result"
    } > "$REVIEW_OUTPUT"

    log "Review saved to $REVIEW_OUTPUT"

    # Post review as PR comment if we have a PR
    if command -v gh &>/dev/null; then
        local branch
        branch=$(git branch --show-current 2>/dev/null)
        local pr_number
        pr_number=$(gh pr list --head "$branch" --json number --jq '.[0].number' 2>/dev/null)

        if [ -n "$pr_number" ]; then
            gh pr comment "$pr_number" --body "$(cat "$REVIEW_OUTPUT")" 2>/dev/null && \
                log "Posted review to PR #$pr_number" || true
        fi
    fi

    # Log to night_chat
    local night_chat="${NIGHT_SHIFT_DIR}/protocols/night_chat.md"
    if [ -d "$(dirname "$night_chat")" ]; then
        echo "[$(date '+%H:%M')] CODE_REVIEW: $(echo "$review_result" | head -3 | tr '\n' ' ')" >> "$night_chat" 2>/dev/null || true
    fi
}

# === Main ===
run_review
