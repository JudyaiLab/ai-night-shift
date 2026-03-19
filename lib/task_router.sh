#!/usr/bin/env bash
# ============================================================================
# lib/task_router.sh — Task management router
#
# Routes task operations to the configured backend (github, linear, file).
#
# Usage:
#   source lib/task_router.sh
#   init_task_backend "github"
#   fetch_tasks "/path/to/project"
# ============================================================================

NIGHT_SHIFT_DIR="${NIGHT_SHIFT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"

init_task_backend() {
    local backend="${1:-${TASK_TOOL:-}}"

    case "$backend" in
        github)
            # shellcheck source=/dev/null
            source "${NIGHT_SHIFT_DIR}/lib/tasks/github.sh"
            ;;
        linear)
            # shellcheck source=/dev/null
            source "${NIGHT_SHIFT_DIR}/lib/tasks/linear.sh"
            ;;
        file)
            # shellcheck source=/dev/null
            source "${NIGHT_SHIFT_DIR}/lib/tasks/file.sh"
            ;;
        "")
            # Auto-detect: try GitHub first, then file
            if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
                # shellcheck source=/dev/null
                source "${NIGHT_SHIFT_DIR}/lib/tasks/github.sh"
            elif [ -f "${PROJECT_DIR:-./tasks.md}" ]; then
                # shellcheck source=/dev/null
                source "${NIGHT_SHIFT_DIR}/lib/tasks/file.sh"
            else
                # Stub functions when no backend is available
                tasks_fetch() { echo "No task backend configured."; }
                tasks_update() { return 0; }
                tasks_create_pr() { return 1; }
            fi
            ;;
        *)
            echo "ERROR: Unknown task backend: $backend"
            echo "Available: github, linear, file"
            return 1
            ;;
    esac
}

# Convenience wrappers
fetch_tasks() {
    tasks_fetch "$@"
}

update_task() {
    tasks_update "$@"
}

create_pr() {
    tasks_create_pr "$@"
}
