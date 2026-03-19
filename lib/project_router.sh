#!/usr/bin/env bash
# ============================================================================
# lib/project_router.sh — Multi-project rotation
#
# Manages multiple project directories, prioritizing which project
# to work on each round based on:
#   1. Pending tasks count
#   2. Failing tests
#   3. Time since last worked on
#   4. Manual priority weight
#
# Usage:
#   source lib/project_router.sh
#   PROJECT_DIRS="/home/user/proj-a,/home/user/proj-b"
#   init_project_router
#   NEXT_PROJECT=$(select_next_project)
# ============================================================================

NIGHT_SHIFT_DIR="${NIGHT_SHIFT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PROJECT_ROSTER="${NIGHT_SHIFT_DIR}/protocols/project_roster.json"

# Initialize the project router
init_project_router() {
    local project_dirs="${PROJECT_DIRS:-}"

    if [ -z "$project_dirs" ]; then
        echo "WARN: PROJECT_DIRS not set, multi-project routing disabled"
        return 0
    fi

    mkdir -p "$(dirname "$PROJECT_ROSTER")"

    # Build roster if it doesn't exist
    if [ ! -f "$PROJECT_ROSTER" ] || [ ! -s "$PROJECT_ROSTER" ]; then
        _build_roster "$project_dirs"
    fi
}

_build_roster() {
    local dirs="$1"

    python3 -c "
import json, os
from datetime import datetime, timezone

dirs = '''$dirs'''.split(',')
roster = []

for d in dirs:
    d = d.strip()
    if not d or not os.path.isdir(d):
        continue
    name = os.path.basename(os.path.abspath(d))
    roster.append({
        'path': os.path.abspath(d),
        'name': name,
        'priority': 1,
        'last_worked': None,
        'total_rounds': 0,
        'last_status': 'unknown'
    })

with open('$PROJECT_ROSTER', 'w') as f:
    json.dump(roster, f, indent=2)

print(f'Initialized roster with {len(roster)} projects')
" 2>/dev/null
}

# Select the next project to work on
# Returns the path of the highest-priority project
select_next_project() {
    if [ ! -f "$PROJECT_ROSTER" ]; then
        echo ""
        return 1
    fi

    python3 -c "
import json
from datetime import datetime, timezone

with open('$PROJECT_ROSTER') as f:
    roster = json.load(f)

if not roster:
    print('')
    exit(1)

def score(project):
    '''Higher score = work on this project next'''
    s = project.get('priority', 1) * 10

    # Bonus for not recently worked on
    last = project.get('last_worked')
    if last is None:
        s += 50  # Never worked on = high priority
    else:
        try:
            last_dt = datetime.fromisoformat(last)
            now = datetime.now(timezone.utc)
            hours_since = (now - last_dt).total_seconds() / 3600
            s += min(hours_since * 2, 40)  # Up to 40 points for staleness
        except Exception:
            s += 20

    # Bonus if last status was failing
    if project.get('last_status') == 'failing':
        s += 30

    return s

roster.sort(key=score, reverse=True)
print(roster[0]['path'])
" 2>/dev/null
}

# Record that we worked on a project this round
record_project_round() {
    local project_path="$1"
    local status="${2:-ok}"  # ok, failing, blocked

    [ -f "$PROJECT_ROSTER" ] || return 0

    python3 -c "
import json
from datetime import datetime, timezone

with open('$PROJECT_ROSTER') as f:
    roster = json.load(f)

for p in roster:
    if p['path'] == '''$project_path''':
        p['last_worked'] = datetime.now(timezone.utc).isoformat()
        p['total_rounds'] = p.get('total_rounds', 0) + 1
        p['last_status'] = '$status'
        break

with open('$PROJECT_ROSTER', 'w') as f:
    json.dump(roster, f, indent=2)
" 2>/dev/null
}

# List all projects and their status
list_projects() {
    [ -f "$PROJECT_ROSTER" ] || {
        echo "No project roster found"
        return 0
    }

    python3 -c "
import json

with open('$PROJECT_ROSTER') as f:
    roster = json.load(f)

print('## Project Roster')
for p in roster:
    last = p.get('last_worked', 'never')
    if last and last != 'never':
        last = last[:16]  # Trim to datetime
    status = p.get('last_status', '?')
    rounds = p.get('total_rounds', 0)
    print(f'  {p[\"name\"]}: status={status}, rounds={rounds}, last={last}')
    print(f'    path: {p[\"path\"]}')
" 2>/dev/null
}

# Format for prompt injection
format_project_roster() {
    list_projects
}
