#!/usr/bin/env bash
# ============================================================================
# lib/metrics.sh — Structured metrics collection
#
# Extracts and stores structured metrics after each round:
#   - Lines/files changed
#   - Test pass/fail counts
#   - Commits made
#   - Time per round
#   - Lint issues
#
# Usage:
#   source lib/metrics.sh
#   collect_metrics "/path/to/project" 1
# ============================================================================

METRICS_DIR="${METRICS_DIR:-reports}"

collect_metrics() {
    local project_dir="${1:-.}"
    local round="${2:-0}"
    local start_time="${3:-$(date +%s)}"
    local round_report="${4:-}"

    local date_tag
    date_tag=$(date +%Y-%m-%d)
    local metrics_file="${METRICS_DIR}/${date_tag}_metrics.json"

    mkdir -p "$METRICS_DIR"

    cd "$project_dir" 2>/dev/null || return 1

    # ── Git metrics ──
    local commits_count=0
    local lines_added=0
    local lines_deleted=0
    local files_changed=0

    if git rev-parse --git-dir &>/dev/null; then
        # Commits in this round (last N minutes approximation)
        commits_count=$(git log --oneline --since="3 hours ago" 2>/dev/null | wc -l | tr -d ' ')

        # Diff stats
        local stat_line
        stat_line=$(git diff --stat HEAD~"${commits_count:-1}" 2>/dev/null | tail -1 || echo "")
        lines_added=$(echo "$stat_line" | grep -o '[0-9]* insertion' | grep -o '[0-9]*' || echo "0")
        lines_deleted=$(echo "$stat_line" | grep -o '[0-9]* deletion' | grep -o '[0-9]*' || echo "0")
        files_changed=$(git diff --name-only HEAD~"${commits_count:-1}" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    fi

    # ── Test metrics ──
    local tests_passed=0
    local tests_failed=0
    local tests_skipped=0
    local test_exit=0

    if [ -n "${PROJECT_TEST_CMD:-}" ]; then
        local test_output
        test_output=$(cd "$project_dir" && timeout 120 bash -c "$PROJECT_TEST_CMD" 2>&1) || test_exit=$?

        # Try to parse common test output formats
        # Jest / Vitest
        if echo "$test_output" | grep -q "Tests:"; then
            tests_passed=$(echo "$test_output" | grep -o '[0-9]* passed' | grep -o '[0-9]*' | head -1 || echo "0")
            tests_failed=$(echo "$test_output" | grep -o '[0-9]* failed' | grep -o '[0-9]*' | head -1 || echo "0")
            tests_skipped=$(echo "$test_output" | grep -o '[0-9]* skipped' | grep -o '[0-9]*' | head -1 || echo "0")
        # Pytest
        elif echo "$test_output" | grep -qE "[0-9]+ passed"; then
            tests_passed=$(echo "$test_output" | grep -oE '[0-9]+ passed' | grep -o '[0-9]*' | head -1 || echo "0")
            tests_failed=$(echo "$test_output" | grep -oE '[0-9]+ failed' | grep -o '[0-9]*' | head -1 || echo "0")
            tests_skipped=$(echo "$test_output" | grep -oE '[0-9]+ skipped' | grep -o '[0-9]*' | head -1 || echo "0")
        # Go
        elif echo "$test_output" | grep -q "^ok\|^FAIL"; then
            tests_passed=$(echo "$test_output" | grep -c "^ok" || echo "0")
            tests_failed=$(echo "$test_output" | grep -c "^FAIL" || echo "0")
        # Cargo
        elif echo "$test_output" | grep -qE "test result:"; then
            tests_passed=$(echo "$test_output" | grep -oE '[0-9]+ passed' | grep -o '[0-9]*' | head -1 || echo "0")
            tests_failed=$(echo "$test_output" | grep -oE '[0-9]+ failed' | grep -o '[0-9]*' | head -1 || echo "0")
        fi
    fi

    # ── Lint metrics ──
    local lint_warnings=0
    if [ -n "${PROJECT_LINT_CMD:-}" ]; then
        local lint_output
        lint_output=$(cd "$project_dir" && timeout 60 bash -c "$PROJECT_LINT_CMD" 2>&1) || true
        lint_warnings=$(echo "$lint_output" | grep -cE "warning|warn|W[0-9]" || echo "0")
    fi

    # ── Time metrics ──
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # ── Write metrics ──
    python3 -c "
import json, os
from datetime import datetime, timezone

metrics_file = '$metrics_file'

# Load existing metrics
if os.path.exists(metrics_file):
    with open(metrics_file) as f:
        data = json.load(f)
else:
    data = {'date': '$date_tag', 'rounds': []}

data['rounds'].append({
    'round': $round,
    'timestamp': datetime.now(timezone.utc).isoformat(),
    'duration_seconds': $duration,
    'git': {
        'commits': int('${commits_count:-0}' or 0),
        'lines_added': int('${lines_added:-0}' or 0),
        'lines_deleted': int('${lines_deleted:-0}' or 0),
        'files_changed': int('${files_changed:-0}' or 0)
    },
    'tests': {
        'passed': int('${tests_passed:-0}' or 0),
        'failed': int('${tests_failed:-0}' or 0),
        'skipped': int('${tests_skipped:-0}' or 0),
        'exit_code': $test_exit
    },
    'lint': {
        'warnings': int('${lint_warnings:-0}' or 0)
    }
})

# Compute totals
data['totals'] = {
    'rounds': len(data['rounds']),
    'total_commits': sum(r['git']['commits'] for r in data['rounds']),
    'total_lines_added': sum(r['git']['lines_added'] for r in data['rounds']),
    'total_lines_deleted': sum(r['git']['lines_deleted'] for r in data['rounds']),
    'total_duration_seconds': sum(r['duration_seconds'] for r in data['rounds']),
    'tests_passing': data['rounds'][-1]['tests']['exit_code'] == 0
}

with open(metrics_file, 'w') as f:
    json.dump(data, f, indent=2)

print(f'Metrics: round=$round, commits=${commits_count:-0}, lines=+${lines_added:-0}/-${lines_deleted:-0}, tests={int(\"${tests_passed:-0}\" or 0)}pass/{int(\"${tests_failed:-0}\" or 0)}fail, duration={$duration}s')
" 2>/dev/null
}

# Format metrics for display
format_metrics() {
    local date_tag
    date_tag=$(date +%Y-%m-%d)
    local metrics_file="${METRICS_DIR}/${date_tag}_metrics.json"

    if [ ! -f "$metrics_file" ]; then
        echo "No metrics available for today."
        return 0
    fi

    python3 -c "
import json

with open('$metrics_file') as f:
    data = json.load(f)

totals = data.get('totals', {})
print('## Session Metrics')
print(f'  Rounds: {totals.get(\"rounds\", 0)}')
print(f'  Commits: {totals.get(\"total_commits\", 0)}')
print(f'  Lines: +{totals.get(\"total_lines_added\", 0)}/-{totals.get(\"total_lines_deleted\", 0)}')
print(f'  Tests passing: {totals.get(\"tests_passing\", \"unknown\")}')
dur = totals.get('total_duration_seconds', 0)
print(f'  Total time: {dur // 3600}h {(dur % 3600) // 60}m')
" 2>/dev/null
}
