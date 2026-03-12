#!/usr/bin/env bash
# PLUGIN_NAME: Git Commit Summary
# PLUGIN_PHASE: post
# PLUGIN_DESCRIPTION: Generates a summary of all git commits made during the night shift
#
# This plugin runs after the night shift and creates a markdown summary
# of all commits made during the session.

set -euo pipefail

NIGHT_SHIFT_DIR="${NIGHT_SHIFT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
REPORTS_DIR="${NIGHT_SHIFT_DIR}/reports"
DATE_TAG=$(date +%Y-%m-%d)

echo "=== Git Commit Summary Plugin ==="

# Find git repos that were modified today
# (customize PROJECT_DIRS to your workspace)
PROJECT_DIRS="${PROJECT_DIRS:-${HOME}/projects}"

SUMMARY_FILE="${REPORTS_DIR}/${DATE_TAG}_git_summary.md"

{
    echo "# Git Commits — $DATE_TAG"
    echo ""
    echo "Commits made during night shift:"
    echo ""

    # Search for repos with today's commits
    find "$PROJECT_DIRS" -maxdepth 3 -name ".git" -type d 2>/dev/null | while read -r gitdir; do
        repo_dir=$(dirname "$gitdir")
        repo_name=$(basename "$repo_dir")

        # Get today's commits
        commits=$(cd "$repo_dir" && git log --oneline --since="$DATE_TAG" --author="$(git config user.name 2>/dev/null || echo '')" 2>/dev/null || true)

        if [ -n "$commits" ]; then
            echo "## $repo_name"
            echo '```'
            echo "$commits"
            echo '```'
            echo ""
        fi
    done
} > "$SUMMARY_FILE"

COMMIT_COUNT=$(grep -c "^[a-f0-9]" "$SUMMARY_FILE" 2>/dev/null || echo 0)
echo "Summary written to $SUMMARY_FILE ($COMMIT_COUNT commits found)"
