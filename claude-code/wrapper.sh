#!/usr/bin/env bash
# ============================================================================
# AI Night Shift — Wrapper Script
#
# Wraps the night shift runner with:
#   1. Pre-shift plugins
#   2. Night shift execution
#   3. Post-shift plugins
#   4. Optional morning report push
#
# Usage:
#   cron calls this instead of night_shift.sh directly
# ============================================================================

set -euo pipefail

NIGHT_SHIFT_DIR="${NIGHT_SHIFT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
export NIGHT_SHIFT_DIR

LOGS_DIR="${NIGHT_SHIFT_DIR}/logs"
DATE_TAG=$(date +%Y-%m-%d)
WRAPPER_LOG="${LOGS_DIR}/wrapper_${DATE_TAG}.log"

mkdir -p "$LOGS_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [wrapper] $*" | tee -a "$WRAPPER_LOG"
}

log "=== Night Shift Wrapper Starting ==="

# ── Phase 1: Pre-shift plugins ──
log "Running pre-shift plugins..."
bash "${NIGHT_SHIFT_DIR}/plugins/plugin_loader.sh" --phase pre 2>&1 | tee -a "$WRAPPER_LOG" || true

# ── Phase 2: Main night shift ──
log "Starting night shift..."
bash "${NIGHT_SHIFT_DIR}/claude-code/night_shift.sh" "$@" 2>&1 | tee -a "$WRAPPER_LOG"
SHIFT_EXIT=$?

log "Night shift exited with code $SHIFT_EXIT"

# ── Phase 3: Post-shift plugins ──
log "Running post-shift plugins..."
bash "${NIGHT_SHIFT_DIR}/plugins/plugin_loader.sh" --phase post 2>&1 | tee -a "$WRAPPER_LOG" || true

# ── Phase 4: Summary ──
SUMMARY="${NIGHT_SHIFT_DIR}/reports/${DATE_TAG}_summary.md"
if [ -f "$SUMMARY" ]; then
    log "Summary available at: $SUMMARY"
fi

log "=== Night Shift Wrapper Complete ==="
