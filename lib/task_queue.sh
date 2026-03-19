#!/usr/bin/env bash
# ============================================================================
# lib/task_queue.sh — Structured task queue (cross-round persistence)
#
# Maintains a JSON task queue that persists across rounds.
# Agents read pending tasks at round start and update status at round end.
#
# Usage:
#   source lib/task_queue.sh
#   queue_init "/path/to/queue.json"
#   queue_add "Fix login test" "high"
#   queue_list "pending"
#   queue_update 1 "done"
# ============================================================================

TASK_QUEUE_FILE="${TASK_QUEUE_FILE:-protocols/task_queue.json}"

# Ensure python3 is available for JSON manipulation
_require_python() {
    if ! command -v python3 &>/dev/null; then
        echo "ERROR: python3 required for task queue"
        return 1
    fi
}

# Initialize the queue file if it doesn't exist
queue_init() {
    local queue_file="${1:-$TASK_QUEUE_FILE}"
    TASK_QUEUE_FILE="$queue_file"

    mkdir -p "$(dirname "$TASK_QUEUE_FILE")"

    if [ ! -f "$TASK_QUEUE_FILE" ]; then
        echo '[]' > "$TASK_QUEUE_FILE"
    fi
}

# Add a task to the queue
queue_add() {
    local description="$1"
    local priority="${2:-medium}"  # urgent, high, medium, low
    local source="${3:-agent}"     # agent, human, ci
    local round="${4:-0}"

    _require_python || return 1

    python3 -c "
import json, sys
from datetime import datetime, timezone

queue_file = '$TASK_QUEUE_FILE'
with open(queue_file) as f:
    queue = json.load(f)

next_id = max((t.get('id', 0) for t in queue), default=0) + 1

queue.append({
    'id': next_id,
    'description': '''$description''',
    'status': 'pending',
    'priority': '$priority',
    'source': '$source',
    'round_created': $round,
    'round_completed': None,
    'created_at': datetime.now(timezone.utc).isoformat(),
    'updated_at': datetime.now(timezone.utc).isoformat(),
    'notes': ''
})

with open(queue_file, 'w') as f:
    json.dump(queue, f, indent=2)

print(f'Added task #{next_id}: $description')
" 2>/dev/null
}

# List tasks by status
queue_list() {
    local status="${1:-pending}"  # pending, in_progress, done, blocked, all

    _require_python || return 1

    python3 -c "
import json

with open('$TASK_QUEUE_FILE') as f:
    queue = json.load(f)

status_filter = '$status'
prio_order = {'urgent': 0, 'high': 1, 'medium': 2, 'low': 3}

if status_filter == 'all':
    tasks = queue
else:
    tasks = [t for t in queue if t.get('status') == status_filter]

tasks.sort(key=lambda t: prio_order.get(t.get('priority', 'medium'), 2))

if not tasks:
    print(f'No {status_filter} tasks.')
else:
    for t in tasks:
        status_icon = {'pending': '[ ]', 'in_progress': '[~]', 'done': '[x]', 'blocked': '[!]'}.get(t['status'], '[?]')
        prio = t.get('priority', '?')
        print(f'{status_icon} #{t[\"id\"]} [{prio}] {t[\"description\"]}')
        if t.get('notes'):
            print(f'    Note: {t[\"notes\"]}')
" 2>/dev/null
}

# Update a task's status
queue_update() {
    local task_id="$1"
    local new_status="$2"  # pending, in_progress, done, blocked
    local notes="${3:-}"
    local round="${4:-0}"

    _require_python || return 1

    python3 -c "
import json
from datetime import datetime, timezone

with open('$TASK_QUEUE_FILE') as f:
    queue = json.load(f)

found = False
for t in queue:
    if t['id'] == $task_id:
        t['status'] = '$new_status'
        t['updated_at'] = datetime.now(timezone.utc).isoformat()
        if '$notes':
            t['notes'] = '''$notes'''
        if '$new_status' == 'done':
            t['round_completed'] = $round
        found = True
        break

if found:
    with open('$TASK_QUEUE_FILE', 'w') as f:
        json.dump(queue, f, indent=2)
    print(f'Task #{$task_id} → $new_status')
else:
    print(f'Task #{$task_id} not found')
" 2>/dev/null
}

# Format queue for prompt injection
format_task_queue() {
    local status="${1:-pending}"

    echo "## Task Queue"
    queue_list "$status"
}

# Get count of pending tasks
queue_count() {
    local status="${1:-pending}"

    _require_python || { echo "0"; return; }

    python3 -c "
import json
with open('$TASK_QUEUE_FILE') as f:
    queue = json.load(f)
print(len([t for t in queue if t.get('status') == '$status']))
" 2>/dev/null
}
