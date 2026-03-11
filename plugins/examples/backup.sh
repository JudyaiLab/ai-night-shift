#!/usr/bin/env bash
# PLUGIN_NAME: Backup
# PLUGIN_PHASE: pre
# PLUGIN_DESCRIPTION: Creates backups of critical files before the night shift starts

set -euo pipefail

NIGHT_SHIFT_DIR="${NIGHT_SHIFT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
BACKUP_DIR="${NIGHT_SHIFT_DIR}/backups"
DATE_TAG=$(date +%Y-%m-%d)

echo "=== Backup Plugin ==="

mkdir -p "${BACKUP_DIR}/${DATE_TAG}"

# Backup night shift configuration
for f in config.env claude-code/prompt_template.txt gemini/prompt_template.txt; do
    src="${NIGHT_SHIFT_DIR}/${f}"
    if [ -f "$src" ]; then
        dest="${BACKUP_DIR}/${DATE_TAG}/$(basename "$f")"
        cp "$src" "$dest"
        echo "Backed up: $f"
    fi
done

# Backup night_chat.md (append-only, so backup before new entries)
CHAT="${NIGHT_SHIFT_DIR}/protocols/night_chat.md"
if [ -f "$CHAT" ]; then
    cp "$CHAT" "${BACKUP_DIR}/${DATE_TAG}/night_chat_backup.md"
    echo "Backed up: night_chat.md"
fi

# Cleanup old backups (keep 7 days)
find "$BACKUP_DIR" -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true

echo "Backups stored in ${BACKUP_DIR}/${DATE_TAG}/"
