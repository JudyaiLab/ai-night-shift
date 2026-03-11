#!/usr/bin/env bash
# PLUGIN_NAME: System Health Check
# PLUGIN_PHASE: pre
# PLUGIN_DESCRIPTION: Checks disk, memory, and critical services before the night shift starts

set -euo pipefail

NIGHT_SHIFT_DIR="${NIGHT_SHIFT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
REPORTS_DIR="${NIGHT_SHIFT_DIR}/reports"
DATE_TAG=$(date +%Y-%m-%d)
HEALTH_FILE="${REPORTS_DIR}/${DATE_TAG}_health.md"

echo "=== System Health Check Plugin ==="

WARNINGS=0

{
    echo "# System Health — $DATE_TAG $(date '+%H:%M')"
    echo ""

    # Disk usage
    echo "## Disk Usage"
    echo '```'
    df -h / /home 2>/dev/null | head -5
    echo '```'

    # Check if disk is >85% full
    DISK_PCT=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
    if [ "$DISK_PCT" -gt 85 ]; then
        echo "**WARNING: Root disk at ${DISK_PCT}%**"
        WARNINGS=$((WARNINGS + 1))
    fi
    echo ""

    # Memory
    echo "## Memory"
    echo '```'
    free -h
    echo '```'

    # Check if memory is >90% used
    MEM_PCT=$(free | awk '/Mem:/ {printf "%.0f", $3/$2*100}')
    if [ "$MEM_PCT" -gt 90 ]; then
        echo "**WARNING: Memory at ${MEM_PCT}%**"
        WARNINGS=$((WARNINGS + 1))
    fi
    echo ""

    # Load average
    echo "## Load Average"
    echo '```'
    uptime
    echo '```'
    echo ""

    # Docker (if available)
    if command -v docker &>/dev/null; then
        echo "## Docker Containers"
        echo '```'
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Docker not accessible"
        echo '```'
        echo ""
    fi

    # Summary
    echo "## Summary"
    if [ $WARNINGS -eq 0 ]; then
        echo "All systems normal."
    else
        echo "**${WARNINGS} warning(s) found — review above.**"
    fi

} > "$HEALTH_FILE"

echo "Health report: $HEALTH_FILE ($WARNINGS warnings)"

# Exit with warning code if issues found
[ $WARNINGS -gt 0 ] && exit 0 || exit 0  # Don't fail the night shift
