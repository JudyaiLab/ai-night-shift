#!/usr/bin/env bash
# ============================================================================
# lib/tasks/linear.sh — Linear task backend
#
# Uses Linear API to fetch assigned issues.
# Requires: LINEAR_API_KEY environment variable
# ============================================================================

_require_linear() {
    if [ -z "${LINEAR_API_KEY:-}" ]; then
        echo "ERROR: LINEAR_API_KEY not set"
        return 1
    fi
    if ! command -v curl &>/dev/null; then
        echo "ERROR: curl not found"
        return 1
    fi
}

tasks_fetch() {
    local project_dir="${1:-.}"
    local limit="${2:-10}"

    _require_linear || return 1

    local query='{ "query": "{ viewer { assignedIssues(first: '"$limit"', filter: { state: { type: { in: [\"backlog\", \"unstarted\", \"started\"] } } }) { nodes { identifier title priority state { name } labels { nodes { name } } } } } }" }'

    local response
    response=$(curl -s -X POST https://api.linear.app/graphql \
        -H "Content-Type: application/json" \
        -H "Authorization: $LINEAR_API_KEY" \
        -d "$query" 2>/dev/null) || return 1

    echo "## Assigned Linear Issues"
    echo ""

    # Parse with python if available, otherwise basic jq
    if command -v python3 &>/dev/null; then
        echo "$response" | python3 -c "
import json, sys
data = json.load(sys.stdin)
issues = data.get('data', {}).get('viewer', {}).get('assignedIssues', {}).get('nodes', [])
if not issues:
    print('No assigned issues found.')
for issue in issues:
    labels = ', '.join(l['name'] for l in issue.get('labels', {}).get('nodes', []))
    state = issue.get('state', {}).get('name', '?')
    prio = {0: 'none', 1: 'urgent', 2: 'high', 3: 'medium', 4: 'low'}.get(issue.get('priority', 0), '?')
    print(f'- [{issue[\"identifier\"]}] {issue[\"title\"]} (state: {state}, priority: {prio}) [{labels}]')
" 2>/dev/null
    elif command -v jq &>/dev/null; then
        echo "$response" | jq -r '.data.viewer.assignedIssues.nodes[] | "- [\(.identifier)] \(.title) (state: \(.state.name))"' 2>/dev/null
    else
        echo "Cannot parse response (install python3 or jq)"
    fi
}

tasks_update() {
    local project_dir="${1:-.}"
    local issue_id="$2"
    local action="${3:-comment}"
    local message="${4:-}"

    _require_linear || return 1

    case "$action" in
        comment)
            local query='{ "query": "mutation { commentCreate(input: { issueId: \"'"$issue_id"'\", body: \"'"$message"'\" }) { success } }" }'
            curl -s -X POST https://api.linear.app/graphql \
                -H "Content-Type: application/json" \
                -H "Authorization: $LINEAR_API_KEY" \
                -d "$query" >/dev/null 2>&1
            ;;
        in-progress)
            echo "Linear state transitions require workflow state IDs — skipping"
            ;;
    esac
}

tasks_create_pr() {
    echo "Linear does not manage PRs directly — use GitHub integration"
    return 1
}
