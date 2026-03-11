#!/usr/bin/env bash
# ============================================================================
# AI Night Shift — Plugin Loader
#
# Discovers and executes plugins from the plugins/ directory.
# Plugins are simple bash scripts that follow a standard interface.
#
# Usage:
#   ./plugin_loader.sh [--phase pre|post|task] [--list]
#
# Plugin Interface:
#   Each plugin must define these functions (via sourcing):
#     plugin_name()    — returns the plugin name
#     plugin_phase()   — returns when to run: "pre", "post", or "task"
#     plugin_run()     — main execution function
#
#   Or be a standalone script with:
#     # PLUGIN_NAME: My Plugin
#     # PLUGIN_PHASE: pre
#     (executable code)
# ============================================================================

set -euo pipefail

NIGHT_SHIFT_DIR="${NIGHT_SHIFT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PLUGINS_DIR="${NIGHT_SHIFT_DIR}/plugins"
ENABLED_DIR="${PLUGINS_DIR}/enabled"
EXAMPLES_DIR="${PLUGINS_DIR}/examples"
LOGS_DIR="${NIGHT_SHIFT_DIR}/logs"

PHASE_FILTER=""
LIST_ONLY=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --phase) PHASE_FILTER="$2"; shift 2 ;;
        --list) LIST_ONLY=true; shift ;;
        --help|-h)
            echo "Usage: $0 [--phase pre|post|task] [--list]"
            echo ""
            echo "Phases:"
            echo "  pre   — runs before the night shift main loop"
            echo "  post  — runs after the night shift completes"
            echo "  task  — runs as part of each round's task list"
            echo ""
            echo "Options:"
            echo "  --list   List available plugins without running them"
            exit 0
            ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

mkdir -p "$ENABLED_DIR" "$LOGS_DIR"

log() {
    echo "[$(date '+%H:%M:%S')] [plugin_loader] $*"
}

# ── Discover plugins ──
# Plugins can be in enabled/ (symlinks or copies from examples/)
discover_plugins() {
    local plugins=()
    for f in "${ENABLED_DIR}"/*.sh; do
        [ -f "$f" ] && plugins+=("$f")
    done
    echo "${plugins[@]}"
}

# ── Extract plugin metadata from header comments ──
get_plugin_meta() {
    local file="$1"
    local key="$2"
    grep "^# PLUGIN_${key}:" "$file" 2>/dev/null | sed "s/^# PLUGIN_${key}: *//" | head -1
}

# ── List plugins ──
if $LIST_ONLY; then
    echo "=== Enabled Plugins ==="
    for f in "${ENABLED_DIR}"/*.sh; do
        [ -f "$f" ] || continue
        name=$(get_plugin_meta "$f" "NAME")
        phase=$(get_plugin_meta "$f" "PHASE")
        echo "  [${phase:-?}] ${name:-$(basename "$f")} — $f"
    done
    echo ""
    echo "=== Available Examples ==="
    for f in "${EXAMPLES_DIR}"/*.sh; do
        [ -f "$f" ] || continue
        name=$(get_plugin_meta "$f" "NAME")
        phase=$(get_plugin_meta "$f" "PHASE")
        echo "  [${phase:-?}] ${name:-$(basename "$f")} — $(basename "$f")"
    done
    echo ""
    echo "Enable a plugin: ln -s ${EXAMPLES_DIR}/plugin.sh ${ENABLED_DIR}/"
    exit 0
fi

# ── Run plugins ──
PLUGIN_COUNT=0
PLUGIN_ERRORS=0

for plugin_file in "${ENABLED_DIR}"/*.sh; do
    [ -f "$plugin_file" ] || continue

    name=$(get_plugin_meta "$plugin_file" "NAME")
    phase=$(get_plugin_meta "$plugin_file" "PHASE")
    name="${name:-$(basename "$plugin_file" .sh)}"
    phase="${phase:-task}"

    # Filter by phase if specified
    if [ -n "$PHASE_FILTER" ] && [ "$phase" != "$PHASE_FILTER" ]; then
        continue
    fi

    PLUGIN_COUNT=$((PLUGIN_COUNT + 1))
    PLUGIN_LOG="${LOGS_DIR}/plugin_${name}_$(date +%Y%m%d).log"

    log "Running plugin: ${name} (phase: ${phase})"

    # Execute plugin with timeout (5 min max per plugin)
    if timeout 300 bash "$plugin_file" >> "$PLUGIN_LOG" 2>&1; then
        log "Plugin ${name}: OK"
    else
        EXIT_CODE=$?
        PLUGIN_ERRORS=$((PLUGIN_ERRORS + 1))
        if [ $EXIT_CODE -eq 124 ]; then
            log "Plugin ${name}: TIMEOUT (300s)"
        else
            log "Plugin ${name}: FAILED (exit $EXIT_CODE)"
        fi
    fi
done

if [ $PLUGIN_COUNT -eq 0 ]; then
    log "No plugins enabled for phase '${PHASE_FILTER:-all}'"
else
    log "Plugins complete: ${PLUGIN_COUNT} run, ${PLUGIN_ERRORS} errors"
fi
