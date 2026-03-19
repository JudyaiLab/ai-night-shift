#!/usr/bin/env bash
# ============================================================================
# lib/tasks/file.sh — File-based task backend
#
# Reads tasks from a markdown file (tasks.md) in the project directory.
# Format:
#   - [ ] Task description
#   - [x] Completed task
#   - [~] In progress task
# ============================================================================

TASKS_FILE="${TASKS_FILE:-tasks.md}"

tasks_fetch() {
    local project_dir="${1:-.}"
    local limit="${2:-10}"
    local tasks_path="$project_dir/$TASKS_FILE"

    if [ ! -f "$tasks_path" ]; then
        echo "## Tasks"
        echo "No $TASKS_FILE found in $project_dir"
        return 0
    fi

    echo "## Tasks from $TASKS_FILE"
    echo ""

    # Show pending and in-progress tasks
    local count=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*-\ \[\ \] ]] || [[ "$line" =~ ^[[:space:]]*-\ \[~\] ]]; then
            echo "$line"
            count=$((count + 1))
            [ "$count" -ge "$limit" ] && break
        fi
    done < "$tasks_path"

    if [ "$count" -eq 0 ]; then
        echo "All tasks completed."
    fi
}

tasks_update() {
    local project_dir="${1:-.}"
    local task_pattern="$2"
    local action="${3:-complete}"
    local tasks_path="$project_dir/$TASKS_FILE"

    [ -f "$tasks_path" ] || return 1

    case "$action" in
        complete)
            # Mark matching task as done
            sed -i "s/- \[ \] \(.*${task_pattern}.*\)/- [x] \1/" "$tasks_path" 2>/dev/null
            ;;
        in-progress)
            sed -i "s/- \[ \] \(.*${task_pattern}.*\)/- [~] \1/" "$tasks_path" 2>/dev/null
            ;;
    esac
}

tasks_create_pr() {
    echo "File-based tasks do not support PR creation — use GitHub backend"
    return 1
}
