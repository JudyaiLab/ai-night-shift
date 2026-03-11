# 🌙 AI Night Shift

> A multi-agent autonomous framework that lets your AI assistants work while you sleep.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**AI Night Shift** is an open-source framework for running multiple AI agents (Claude Code, Gemini, and more) in coordinated autonomous sessions during off-hours. Born from 30+ real production night shifts, this isn't theoretical — it's battle-tested.

## What Makes This Different

Most "autonomous agent" tools run a single agent in isolation. AI Night Shift orchestrates **multiple heterogeneous AI agents** working together:

| Agent | Engine | Role | Mode |
|-------|--------|------|------|
| Developer | Claude Code | Coding, debugging, deploying | Continuous (hours) |
| Researcher | Gemini CLI | Research, data gathering, triage | Periodic (minutes) |
| Coordinator | Any LLM | Task routing, monitoring | Heartbeat (30min) |

They communicate through shared protocols — a file-based message queue, shared chat log, and task board integration.

## Architecture

```
┌─────────────────────────────────────────────┐
│              AI Night Shift                  │
│                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │  Claude   │  │  Gemini  │  │Heartbeat │  │
│  │  Code     │  │  CLI     │  │  Agent   │  │
│  │          │  │          │  │          │  │
│  │ night_   │  │ patrol.  │  │ heartbeat│  │
│  │ shift.sh │  │ sh       │  │ _config  │  │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  │
│       │              │              │        │
│       └──────┬───────┴──────┬───────┘        │
│              │              │                │
│       ┌──────▼──────┐ ┌────▼─────┐          │
│       │ night_chat  │ │ bot_inbox│          │
│       │    .md      │ │  (JSON)  │          │
│       └─────────────┘ └──────────┘          │
│                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │ Plugins  │  │Dashboard │  │Templates │  │
│  └──────────┘  └──────────┘  └──────────┘  │
└─────────────────────────────────────────────┘
```

## Quick Start

### 1. Install

```bash
git clone https://github.com/judyailab/ai-night-shift.git
cd ai-night-shift
bash install.sh
```

### 2. Configure

```bash
# Edit your settings
nano config.env

# Customize the night shift prompt
nano claude-code/prompt_template.txt
```

### 3. Test

```bash
# Run a single round to verify setup
bash claude-code/night_shift.sh --max-rounds 1
```

### 4. Schedule

```bash
# The installer adds cron jobs automatically, or set up manually:
crontab -e
# Add: 0 1 * * * cd ~/ai-night-shift && bash claude-code/wrapper.sh
```

## Modules

| Module | Description | Docs |
|--------|-------------|------|
| [Claude Code](claude-code/) | Continuous developer sessions | [README](claude-code/README.md) |
| [Gemini](gemini/) | Periodic patrol and research | [README](gemini/README.md) |
| [OpenClaw](openclaw/) | Heartbeat coordinator pattern | [README](openclaw/README.md) |
| [Protocols](protocols/) | Inter-agent communication | [README](protocols/README.md) |
| [Plugins](plugins/) | Extensible pre/post/task hooks | [README](plugins/README.md) |
| [Dashboard](dashboard/) | Visual monitoring interface | Open `dashboard/index.html` |
| [Templates](templates/) | Prompt templates by use case | 4 templates included |

## Prompt Templates

| Template | Use Case |
|----------|----------|
| `development.txt` | Coding, testing, debugging |
| `research.txt` | Data gathering, analysis |
| `content.txt` | Writing, translation, SEO |
| `maintenance.txt` | System admin, monitoring |

## Plugin System

Extend your night shift with pre-built or custom plugins:

```bash
# Enable a plugin
ln -s plugins/examples/system_health.sh plugins/enabled/

# List all plugins
bash plugins/plugin_loader.sh --list
```

Built-in plugins: System Health, Backup, Git Commit Summary, Morning Report

## Dashboard

Open `dashboard/index.html` in a browser. Drag and drop your report files to visualize:
- Agent activity and status
- Round-by-round timeline
- Night chat messages
- System health metrics

## Requirements

- **Bash 4+** and **Python 3.6+**
- At least one AI CLI tool:
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`npm install -g @anthropic-ai/claude-code`)
  - [Gemini CLI](https://github.com/google-gemini/gemini-cli) (`npm install -g @anthropic-ai/gemini-cli`)
- A Linux/macOS system with cron (or any task scheduler)

## Safety & Security

- **PID locking** prevents concurrent runs
- **Time windows** ensure shifts end on schedule
- **Rate limit handling** with automatic retry
- **No secrets in code** — all credentials via environment variables
- **Append-only communication** — agents can't delete each other's messages
- **Plugin timeout** — max 5 minutes per plugin execution

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

[MIT](LICENSE) — Judy AI Lab

---

*Built with real-world experience from 30+ autonomous night shifts. If your AI works harder while you sleep, you're doing it right.* 🌙
