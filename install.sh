#!/usr/bin/env bash
# ============================================================================
# AI Night Shift — One-Click Installer
#
# Sets up the complete night shift framework:
#   1. Directory structure and permissions
#   2. Cron jobs (Claude Code night shift + Gemini patrol)
#   3. Systemd service (optional, for TG bot relay)
#   4. Cross-agent protocol directories
#   5. Plugin system
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/judyailab/ai-night-shift/main/install.sh | bash
#   # or
#   ./install.sh [--dir ~/ai-night-shift] [--no-cron] [--no-systemd]
# ============================================================================

set -euo pipefail

# ── Defaults ──
INSTALL_DIR="${HOME}/ai-night-shift"
SETUP_CRON=true
SETUP_SYSTEMD=false
CLAUDE_SCHEDULE="0 17 * * *"       # 5 PM UTC (adjust to your timezone)
GEMINI_SCHEDULE="45 17,19,21 * * *" # Every 2h during night window
TIMEZONE="${TZ:-UTC}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}"
    echo "  ╔═══════════════════════════════════════╗"
    echo "  ║       AI Night Shift Installer        ║"
    echo "  ║   Multi-Agent Autonomous Framework    ║"
    echo "  ╚═══════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ── Parse arguments ──
while [[ $# -gt 0 ]]; do
    case $1 in
        --dir) INSTALL_DIR="$2"; shift 2 ;;
        --no-cron) SETUP_CRON=false; shift ;;
        --no-systemd) SETUP_SYSTEMD=false; shift ;;
        --with-systemd) SETUP_SYSTEMD=true; shift ;;
        --claude-schedule) CLAUDE_SCHEDULE="$2"; shift 2 ;;
        --gemini-schedule) GEMINI_SCHEDULE="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dir PATH           Install directory (default: ~/ai-night-shift)"
            echo "  --no-cron            Skip cron job setup"
            echo "  --with-systemd       Set up systemd service"
            echo "  --claude-schedule    Cron schedule for Claude (default: '0 17 * * *')"
            echo "  --gemini-schedule    Cron schedule for Gemini (default: '45 17,19,21 * * *')"
            echo "  --help               Show this help"
            exit 0
            ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

print_header

# ── Pre-flight checks ──
log_info "Checking prerequisites..."

MISSING=()
command -v bash &>/dev/null || MISSING+=("bash")
command -v python3 &>/dev/null || MISSING+=("python3")

if [ ${#MISSING[@]} -gt 0 ]; then
    log_error "Missing required tools: ${MISSING[*]}"
    exit 1
fi

# Check for AI CLI tools
HAS_CLAUDE=false
HAS_GEMINI=false
command -v claude &>/dev/null && HAS_CLAUDE=true
command -v gemini &>/dev/null && HAS_GEMINI=true

if ! $HAS_CLAUDE && ! $HAS_GEMINI; then
    log_warn "Neither 'claude' nor 'gemini' CLI found."
    log_warn "Install at least one to use the night shift system."
    log_warn "  Claude Code: npm install -g @anthropic-ai/claude-code"
    log_warn "  Gemini CLI:  npm install -g @anthropic-ai/gemini-cli"
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] || exit 0
fi

# ── Create directory structure ──
log_info "Creating directory structure at ${INSTALL_DIR}..."

mkdir -p "${INSTALL_DIR}"/{claude-code,gemini,openclaw,protocols/bot_inbox/{claude,gemini,heartbeat},protocols/examples,templates,dashboard,plugins/examples,docs,logs,reports,research}

# Create done directories for inbox
for agent in claude gemini heartbeat; do
    mkdir -p "${INSTALL_DIR}/protocols/bot_inbox/${agent}/done"
done

# ── Copy files (if running from cloned repo) ──
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -f "${SCRIPT_DIR}/claude-code/night_shift.sh" ]; then
    log_info "Copying framework files..."
    # Copy all module files
    for module in claude-code gemini openclaw protocols templates plugins dashboard docs; do
        if [ -d "${SCRIPT_DIR}/${module}" ]; then
            cp -r "${SCRIPT_DIR}/${module}/"* "${INSTALL_DIR}/${module}/" 2>/dev/null || true
        fi
    done
    # Copy root files
    for f in LICENSE README.md README.zh-TW.md; do
        [ -f "${SCRIPT_DIR}/${f}" ] && cp "${SCRIPT_DIR}/${f}" "${INSTALL_DIR}/"
    done
else
    log_info "No source files found — creating minimal setup..."
    # Create minimal config
    cat > "${INSTALL_DIR}/config.env" << 'ENVEOF'
# AI Night Shift Configuration
# Adjust these values to match your setup

# Night shift window (UTC)
WINDOW_HOURS=6
MAX_ROUNDS=5

# Claude Code
CLAUDE_BIN=claude
ROUND_TIMEOUT=9000

# Gemini CLI
GEMINI_BIN=gemini

# Reporting (optional)
# TELEGRAM_BOT_TOKEN=your_token
# TELEGRAM_CHAT_ID=your_chat_id

# Agent names
AGENT_NAME=my-agent
ENVEOF
fi

# ── Set permissions ──
log_info "Setting permissions..."
chmod +x "${INSTALL_DIR}/claude-code/"*.sh 2>/dev/null || true
chmod +x "${INSTALL_DIR}/gemini/"*.sh 2>/dev/null || true
chmod +x "${INSTALL_DIR}/protocols/"*.sh 2>/dev/null || true
chmod +x "${INSTALL_DIR}/plugins/"*.sh 2>/dev/null || true
chmod +x "${INSTALL_DIR}/install.sh" 2>/dev/null || true

# ── Initialize night_chat.md ──
if [ ! -f "${INSTALL_DIR}/protocols/night_chat.md" ]; then
    echo "# Night Chat — Agent Communication Log" > "${INSTALL_DIR}/protocols/night_chat.md"
    echo "" >> "${INSTALL_DIR}/protocols/night_chat.md"
    echo "[$(date '+%H:%M')] System: Night shift framework initialized" >> "${INSTALL_DIR}/protocols/night_chat.md"
fi

# ── Create config.env if not exists ──
if [ ! -f "${INSTALL_DIR}/config.env" ]; then
    cat > "${INSTALL_DIR}/config.env" << 'ENVEOF'
# AI Night Shift Configuration
NIGHT_SHIFT_DIR="${HOME}/ai-night-shift"
WINDOW_HOURS=6
MAX_ROUNDS=5
CLAUDE_BIN=claude
GEMINI_BIN=gemini
AGENT_NAME=my-agent
ENVEOF
fi

# ── Setup cron jobs ──
if $SETUP_CRON; then
    log_info "Setting up cron jobs..."

    # Backup existing crontab
    CRON_BACKUP="/tmp/crontab_backup_$(date +%s)"
    crontab -l > "$CRON_BACKUP" 2>/dev/null || true

    # Check if our jobs already exist
    if grep -q "ai-night-shift" "$CRON_BACKUP" 2>/dev/null; then
        log_warn "Night shift cron jobs already exist. Skipping."
    else
        {
            cat "$CRON_BACKUP" 2>/dev/null || true
            echo ""
            echo "# === AI Night Shift ==="
            if $HAS_CLAUDE; then
                echo "# Claude Code night shift (adjust schedule to your timezone)"
                echo "${CLAUDE_SCHEDULE} cd ${INSTALL_DIR} && bash claude-code/night_shift.sh >> ${INSTALL_DIR}/logs/cron_claude.log 2>&1"
            fi
            if $HAS_GEMINI; then
                echo "# Gemini patrol (runs during night window)"
                echo "${GEMINI_SCHEDULE} cd ${INSTALL_DIR} && bash gemini/patrol.sh >> ${INSTALL_DIR}/logs/cron_gemini.log 2>&1"
            fi
            echo "# === End AI Night Shift ==="
        } | crontab -

        log_info "Cron jobs installed successfully"
        if $HAS_CLAUDE; then
            log_info "  Claude: ${CLAUDE_SCHEDULE}"
        fi
        if $HAS_GEMINI; then
            log_info "  Gemini: ${GEMINI_SCHEDULE}"
        fi
    fi
else
    log_info "Skipping cron setup (--no-cron)"
fi

# ── Summary ──
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Installation Complete!                ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════╝${NC}"
echo ""
echo "  Install directory: ${INSTALL_DIR}"
echo ""
echo "  Modules installed:"
$HAS_CLAUDE && echo "    ✅ Claude Code night shift"
$HAS_GEMINI && echo "    ✅ Gemini patrol"
echo "    ✅ Cross-agent protocols"
echo "    ✅ Plugin system"
echo ""
echo "  Next steps:"
echo "    1. Edit ${INSTALL_DIR}/config.env with your settings"
echo "    2. Customize prompt templates in claude-code/ and gemini/"
echo "    3. (Optional) Add plugins from plugins/examples/"
echo "    4. Test with: cd ${INSTALL_DIR} && bash claude-code/night_shift.sh --max-rounds 1"
echo ""
echo "  Documentation: ${INSTALL_DIR}/docs/"
echo "  Dashboard:     open ${INSTALL_DIR}/dashboard/index.html"
echo ""
log_info "Happy autonomous coding! 🌙"
