# Advanced Guide

## Multi-Agent Setup

The real power of AI Night Shift comes from running multiple agents together.

### Recommended Configuration

```
Agent 1 (Claude Code) — Continuous developer
  Schedule: 1 AM - 7 AM
  Tasks: Coding, testing, deploying

Agent 2 (Gemini) — Periodic researcher
  Schedule: Every 2 hours during Agent 1's window
  Tasks: Research, triage, documentation

Agent 3 (Heartbeat) — Coordinator
  Schedule: Every 30 minutes
  Tasks: Route inbox items, monitor health, dispatch work
```

### Setting Up Inter-Agent Communication

1. **Create agent inboxes:**
```bash
mkdir -p protocols/bot_inbox/{claude,gemini,heartbeat}/{done}
```

2. **Configure agent names** in each module's environment:
```bash
# In Claude Code's session
export AGENT_NAME=claude

# In Gemini's patrol
export AGENT_NAME=gemini
```

3. **Agents send messages to each other:**
```bash
# Claude asks Gemini to research something
./protocols/msg.sh gemini "Please research React Server Components best practices"

# Gemini reports findings back
./protocols/notify.sh claude RESEARCH-1 success "Findings in reports/rsc_research.md"
```

### Task Board Integration

Connect to your preferred task management:

**Linear:**
```bash
export TASK_TOOL="linear"
# Install: pip install linear-sdk
```

**GitHub Issues:**
```bash
export TASK_TOOL="github"
# Uses: gh cli
```

**Plain File:**
```bash
export TASK_TOOL="file"
# Uses: tasks.md with checkbox format
```

## Custom Plugins

### Plugin API

Plugins have access to these environment variables:

| Variable | Description |
|----------|-------------|
| `NIGHT_SHIFT_DIR` | Root framework directory |
| `AGENT_NAME` | Current agent identifier |
| `DATE_TAG` | Current date (YYYY-MM-DD) |

And these directories:

| Path | Purpose |
|------|---------|
| `$NIGHT_SHIFT_DIR/logs/` | Write log output |
| `$NIGHT_SHIFT_DIR/reports/` | Write report files |
| `$NIGHT_SHIFT_DIR/protocols/` | Read/write messages |

### Plugin Lifecycle

```
Pre-plugins  → Run before the night shift (health checks, backups)
Task-plugins → Run during each round (custom automation)
Post-plugins → Run after the night shift (reports, cleanup)
```

### Example: Custom Monitoring Plugin

```bash
#!/usr/bin/env bash
# PLUGIN_NAME: Database Monitor
# PLUGIN_PHASE: pre
# PLUGIN_DESCRIPTION: Check database connection and query performance

set -euo pipefail
NIGHT_SHIFT_DIR="${NIGHT_SHIFT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

# Check database connection
if pg_isready -h localhost -p 5432 2>/dev/null; then
    echo "Database: OK"
else
    echo "WARNING: Database unreachable"
    # Write to night_chat for other agents
    echo "[$(date '+%H:%M')] DBMonitor: Database connection failed!" \
        >> "$NIGHT_SHIFT_DIR/protocols/night_chat.md"
fi
```

## Scaling

### Multiple Projects

Run separate night shifts for different projects:

```bash
# Project A — web development
NIGHT_SHIFT_DIR=~/project-a/night-shift \
  bash ~/ai-night-shift/claude-code/night_shift.sh --prompt project_a_prompt.txt

# Project B — data pipeline
NIGHT_SHIFT_DIR=~/project-b/night-shift \
  bash ~/ai-night-shift/claude-code/night_shift.sh --prompt project_b_prompt.txt
```

### Weekend vs Weekday

Use different schedules and prompts:

```
# Weekday: focused development
0 1 * * 1-5 cd ~/ai-night-shift && bash claude-code/wrapper.sh

# Weekend: research and cleanup
0 1 * * 0,6 cd ~/ai-night-shift && PROMPT_FILE=templates/maintenance.txt bash claude-code/wrapper.sh
```

## Telegram Integration

### Setup

1. Create a Telegram bot via [@BotFather](https://t.me/BotFather)
2. Get your chat ID
3. Add to `config.env`:
```bash
TELEGRAM_BOT_TOKEN=your_token
TELEGRAM_CHAT_ID=your_chat_id
```

4. Enable the morning report plugin:
```bash
ln -s ../examples/morning_report.sh plugins/enabled/
```

### What Gets Sent

The morning report plugin sends a summary after each shift:
- Tasks completed
- Issues found
- Git commits made
- System health status
