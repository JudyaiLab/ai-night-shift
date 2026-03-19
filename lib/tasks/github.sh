#!/usr/bin/env bash
# ============================================================================
# lib/tasks/github.sh — GitHub Issues task backend
#
# Uses `gh` CLI to fetch assigned issues and create PRs.
#
# Exports:
#   tasks_fetch   — returns a formatted task list
#   tasks_update  — update issue status/labels
#   tasks_create_pr — create a PR for completed work
# ============================================================================

_require_gh() {
    if ! command -v gh &>/dev/null; then
        echo "ERROR: gh CLI not found. Install: https://cli.github.com/"
        return 1
    fi
    if ! gh auth status &>/dev/null 2>&1; then
        echo "ERROR: gh not authenticated. Run: gh auth login"
        return 1
    fi
}

tasks_fetch() {
    local project_dir="${1:-.}"
    local limit="${2:-10}"
    local labels="${3:-}"

    _require_gh || return 1

    cd "$project_dir" || return 1

    local label_filter=""
    if [ -n "$labels" ]; then
        label_filter="--label $labels"
    fi

    echo "## Assigned GitHub Issues"
    echo ""

    # Fetch issues assigned to the authenticated user
    # shellcheck disable=SC2086
    local issues
    issues=$(gh issue list --assignee @me --state open --limit "$limit" \
        $label_filter --json number,title,labels,body,updatedAt \
        --jq '.[] | "- #\(.number): \(.title) [\(.labels | map(.name) | join(", "))]"' 2>/dev/null) || true

    if [ -z "$issues" ]; then
        # Fall back to issues labeled for night-shift
        issues=$(gh issue list --label "night-shift" --state open --limit "$limit" \
            --json number,title,labels,body \
            --jq '.[] | "- #\(.number): \(.title) [\(.labels | map(.name) | join(", "))]"' 2>/dev/null) || true
    fi

    if [ -n "$issues" ]; then
        echo "$issues"
    else
        echo "No assigned issues found."
    fi
}

tasks_update() {
    local project_dir="${1:-.}"
    local issue_number="$2"
    local action="${3:-comment}"  # comment, close, label
    local message="${4:-}"

    _require_gh || return 1

    cd "$project_dir" || return 1

    case "$action" in
        comment)
            gh issue comment "$issue_number" --body "$message" 2>/dev/null
            ;;
        close)
            gh issue close "$issue_number" --comment "${message:-Closed by AI Night Shift}" 2>/dev/null
            ;;
        label)
            gh issue edit "$issue_number" --add-label "$message" 2>/dev/null
            ;;
        in-progress)
            gh issue edit "$issue_number" --add-label "in-progress" 2>/dev/null
            gh issue comment "$issue_number" --body "${message:-AI Night Shift is working on this.}" 2>/dev/null
            ;;
    esac
}

tasks_create_pr() {
    local project_dir="${1:-.}"
    local branch="$2"
    local title="$3"
    local body="${4:-}"
    local base="${5:-main}"
    local draft="${6:-true}"

    _require_gh || return 1

    cd "$project_dir" || return 1

    local draft_flag=""
    if [ "$draft" = "true" ]; then
        draft_flag="--draft"
    fi

    # shellcheck disable=SC2086
    gh pr create --title "$title" --body "$body" --base "$base" \
        --head "$branch" $draft_flag 2>/dev/null
}
