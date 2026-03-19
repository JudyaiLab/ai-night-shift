#!/usr/bin/env bash
# ============================================================================
# lib/context_collector.sh — Pre-round context injection
#
# Gathers project state (git log, CI status, open PRs, test results)
# and formats it for injection into the agent prompt.
#
# Usage:
#   source lib/context_collector.sh
#   CONTEXT=$(collect_context "/path/to/project")
# ============================================================================

collect_context() {
    local project_dir="${1:-.}"
    local max_commits="${2:-10}"

    cd "$project_dir" 2>/dev/null || {
        echo "Cannot access project directory: $project_dir"
        return 1
    }

    echo "## Project Context"
    echo ""

    # ── Git state ──
    if git rev-parse --git-dir &>/dev/null; then
        local branch
        branch=$(git branch --show-current 2>/dev/null || echo "detached")

        echo "### Git State"
        echo "- Branch: $branch"
        echo "- Status:"
        git status --short 2>/dev/null | head -15 | sed 's/^/    /'
        local uncommitted
        uncommitted=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
        if [ "$uncommitted" -gt 15 ]; then
            echo "    ... and $((uncommitted - 15)) more files"
        fi
        echo ""

        echo "### Recent Commits"
        git log --oneline -"$max_commits" 2>/dev/null | sed 's/^/  /'
        echo ""

        # Diff stats
        local diff_stat
        diff_stat=$(git diff --stat 2>/dev/null)
        if [ -n "$diff_stat" ]; then
            echo "### Uncommitted Changes"
            echo "$diff_stat" | tail -5 | sed 's/^/  /'
            echo ""
        fi
    fi

    # ── Open PRs ──
    if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
        local prs
        prs=$(gh pr list --state open --limit 5 \
            --json number,title,headRefName,author \
            --jq '.[] | "  #\(.number) [\(.headRefName)] \(.title) (@\(.author.login))"' 2>/dev/null)

        if [ -n "$prs" ]; then
            echo "### Open Pull Requests"
            echo "$prs"
            echo ""
        fi

        # ── Recent CI runs ──
        local ci_runs
        ci_runs=$(gh run list --limit 3 \
            --json status,conclusion,name,headBranch,createdAt \
            --jq '.[] | "  \(.name): \(.conclusion // .status) (\(.headBranch))"' 2>/dev/null)

        if [ -n "$ci_runs" ]; then
            echo "### Recent CI Runs"
            echo "$ci_runs"
            echo ""
        fi
    fi

    # ── Failing tests (quick check) ──
    if [ -n "${PROJECT_TEST_CMD:-}" ]; then
        echo "### Last Test Result"
        local test_output
        test_output=$(cd "$project_dir" && timeout 120 bash -c "$PROJECT_TEST_CMD" 2>&1) || true
        local test_exit=$?
        if [ "$test_exit" -eq 0 ]; then
            echo "  Tests: PASSING"
        else
            echo "  Tests: FAILING"
            echo "  Last 10 lines of output:"
            echo "$test_output" | tail -10 | sed 's/^/    /'
        fi
        echo ""
    fi

    # ── Project structure summary ──
    echo "### Project Structure"
    if [ -f "$project_dir/package.json" ]; then
        echo "  Type: Node.js project"
        if command -v node &>/dev/null; then
            node -e "const p=require('./package.json'); console.log('  Name: '+p.name+' v'+p.version)" 2>/dev/null || true
        fi
    elif [ -f "$project_dir/Cargo.toml" ]; then
        echo "  Type: Rust project"
    elif [ -f "$project_dir/go.mod" ]; then
        echo "  Type: Go project"
        head -1 "$project_dir/go.mod" 2>/dev/null | sed 's/^/  /'
    elif [ -f "$project_dir/pyproject.toml" ]; then
        echo "  Type: Python project"
    fi
}

# Collect context without running tests (faster)
collect_context_fast() {
    local project_dir="${1:-.}"

    cd "$project_dir" 2>/dev/null || return 1

    echo "## Project Context (quick)"
    echo ""

    if git rev-parse --git-dir &>/dev/null; then
        echo "- Branch: $(git branch --show-current 2>/dev/null)"
        echo "- Uncommitted files: $(git status --short 2>/dev/null | wc -l | tr -d ' ')"
        echo "- Recent commits:"
        git log --oneline -5 2>/dev/null | sed 's/^/    /'
    fi
}
