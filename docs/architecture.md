# Architecture

## System Overview

AI Night Shift is a **multi-agent orchestration framework** that coordinates autonomous AI sessions during off-hours. It uses a file-based communication protocol that works across different LLM engines.

## Design Principles

1. **Engine-agnostic** — works with any AI CLI tool (Claude, Gemini, etc.)
2. **File-based communication** — no databases, message brokers, or complex infrastructure
3. **Fail-safe** — rate limits, timeouts, and PID locks prevent runaway processes
4. **Plugin-extensible** — customize behavior without modifying core code
5. **Observable** — every action is logged and reportable

## Component Diagram

```
                    ┌─────────────────┐
                    │   Cron / Timer   │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  wrapper.sh     │  ← Entry point
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
     ┌────────▼───┐  ┌──────▼─────┐  ┌────▼────────┐
     │ Pre Plugins │  │ Night Shift│  │Post Plugins │
     │ (health,   │  │  Runner    │  │ (report,    │
     │  backup)   │  │            │  │  summary)   │
     └────────────┘  └──────┬─────┘  └─────────────┘
                            │
                   ┌────────▼────────┐
                   │  Round Loop     │
                   │  ┌──────────┐   │
                   │  │ Claude   │   │
                   │  │ Code CLI │   │
                   │  └────┬─────┘   │
                   │       │         │
                   │  ┌────▼─────┐   │
                   │  │ Report   │   │
                   │  │ Output   │   │
                   │  └──────────┘   │
                   └─────────────────┘

     ┌──────────────────────────────────────┐
     │       Shared Communication Layer     │
     │                                      │
     │  ┌──────────┐  ┌─────────────────┐  │
     │  │night_chat│  │   bot_inbox/    │  │
     │  │   .md    │  │  (JSON queue)   │  │
     │  └──────────┘  └─────────────────┘  │
     │                                      │
     │  ┌──────────┐  ┌─────────────────┐  │
     │  │notify.sh │  │    msg.sh       │  │
     │  └──────────┘  └─────────────────┘  │
     └──────────────────────────────────────┘
```

## Communication Protocol

### File-Based Message Queue

Instead of using complex message brokers (Redis, RabbitMQ), we use simple JSON files in directories:

```
protocols/bot_inbox/
├── claude/          ← Each agent has an inbox
│   ├── task_001.json
│   └── done/        ← Processed items move here
├── gemini/
│   └── done/
└── heartbeat/
    └── done/
```

**Why files?**
- Zero dependencies
- Works on any system
- Easy to inspect and debug
- Survives agent crashes
- Git-trackable (if desired)

### Night Chat (Shared Log)

A single markdown file that all agents append to:

```markdown
[01:00] Claude: Starting round 1
[01:05] Gemini: Inbox empty, standing by
[01:30] Claude: Fixed 3 bugs, running tests
[01:38] Gemini: Research task completed
```

**Why a shared file?**
- Chronological record of all agent activity
- Agents can see each other's progress
- Easy to parse and display in dashboard
- Natural handoff context between shifts

## Execution Models

| Model | Agent | Duration | Frequency |
|-------|-------|----------|-----------|
| Continuous | Claude Code | 2-3 hours/round | 1-5 rounds/night |
| Periodic | Gemini | 1-5 minutes | Every 1-2 hours |
| Heartbeat | Coordinator | 1-2 minutes | Every 30 minutes |

These models serve different purposes and can run concurrently without conflict.

## Safety Architecture

```
                    ┌─────────────┐
                    │  PID Lock   │ ← Prevents concurrent runs
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │ Time Window │ ← Enforces shift boundaries
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │Round Timeout│ ← Limits per-round duration
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │ Rate Limit  │ ← Auto-wait on 429
                    │  Handler    │
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │  Shutdown   │ ← Graceful termination
                    │  Buffer     │
                    └─────────────┘
```

## Directory Structure

```
ai-night-shift/
├── claude-code/        # Claude Code night shift module
│   ├── night_shift.sh  # Main runner
│   ├── wrapper.sh      # Full lifecycle wrapper
│   └── prompt_template.txt
├── gemini/             # Gemini patrol module
│   ├── patrol.sh       # Patrol runner
│   └── prompt_template.txt
├── openclaw/           # Heartbeat coordinator reference
│   ├── heartbeat_config.json
│   └── README.md
├── protocols/          # Inter-agent communication
│   ├── notify.sh       # Task completion notifications
│   ├── msg.sh          # Direct messaging
│   ├── bot_inbox/      # Message queues
│   └── examples/       # Handoff templates
├── templates/          # Prompt templates by use case
├── plugins/            # Extensible plugin system
│   ├── plugin_loader.sh
│   ├── enabled/        # Active plugins (symlinks)
│   └── examples/       # Pre-built plugins
├── dashboard/          # Visual monitoring
│   └── index.html      # Single-page dashboard
├── docs/               # Documentation
├── logs/               # Runtime logs (gitignored)
├── reports/            # Generated reports (gitignored)
├── config.env.example  # Configuration template
├── install.sh          # One-click installer
└── README.md
```
