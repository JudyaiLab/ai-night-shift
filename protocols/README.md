# Cross-Agent Communication Protocols

The protocols module is the backbone of multi-agent night shifts. It defines **how different AI agents communicate, share context, and coordinate work** — even when they run on different LLM engines.

## Architecture Overview

```
┌─────────────┐     night_chat.md      ┌─────────────┐
│  Claude Code │ ◄──────────────────►  │   Gemini     │
│  (Developer) │                        │  (Research)  │
└──────┬───────┘                        └──────┬───────┘
       │           ┌─────────────┐             │
       │           │  Heartbeat  │             │
       └──────────►│ (Coordinator)│◄────────────┘
                   └──────┬───────┘
                          │
                   ┌──────▼───────┐
                   │  Task Board  │
                   │ (Linear/GH)  │
                   └──────────────┘
```

## Communication Channels

### 1. Night Chat (`night_chat.md`)

A shared markdown file where agents post real-time status updates. Think of it as a team Slack channel in a file.

**Format:**
```
[HH:MM] AgentName: Message here
[HH:MM] AgentName: Another update
```

**Rules:**
- Append-only (never overwrite existing messages)
- Keep messages concise (1-2 lines)
- Include timestamps for chronological tracking
- Any agent can read; each agent appends

**Use cases:**
- Progress updates during long tasks
- Requesting help from other agents
- Sharing findings or warnings

### 2. Bot Inbox (`bot_inbox/`)

A structured message queue using JSON files. Each agent has its own inbox directory.

**Structure:**
```
bot_inbox/
├── claude/          ← Messages for Claude Code agent
│   ├── task_001.json
│   ├── msg_002.json
│   └── done/        ← Processed messages
├── gemini/          ← Messages for Gemini agent
│   └── done/
└── heartbeat/       ← Messages for Heartbeat agent
    └── done/
```

**Message format:**
```json
{
  "from": "claude",
  "to": "gemini",
  "type": "message",
  "task_id": "TASK-123",
  "message": "Research completed, results in /reports/",
  "ts": "2026-03-11T14:45:00Z"
}
```

**Supported types:**
- `message` — free-form communication
- `task` — work assignment
- `result` — task completion report

### 3. Notify Script (`notify.sh`)

Used to report task completion to other agents.

```bash
./notify.sh <target_agent> <task_id> <status> <summary>
```

**Example:**
```bash
./notify.sh gemini TASK-42 success "Refactored auth module, 12 tests passing"
```

### 4. Message Script (`msg.sh`)

Used for direct messages between agents.

```bash
./msg.sh <target_agent> "Your message here"
```

## Protocol Rules

1. **Append-only** — never delete or modify another agent's messages
2. **Process and archive** — move handled inbox items to `done/`
3. **Structured over free-form** — prefer JSON inbox for actionable items, use night_chat for FYI updates
4. **Idempotent handling** — agents should handle duplicate messages gracefully
5. **Timeout awareness** — if a message isn't processed within 2 heartbeat cycles, escalate

## Task Board Integration

The protocols work with any task management system. Examples:

| System | Integration |
|--------|-------------|
| Linear | `linear_tool.py create/update/comment` |
| GitHub Issues | `gh issue create/edit/comment` |
| Jira | Jira CLI or API |
| Plain files | `tasks.md` with checkbox format |

The key principle: **every task assignment should exist on the board**, not just in chat. Chat is for coordination; the board is the source of truth.

## Examples

See the `examples/` directory for:
- `handoff_document.md` — template for shift handoff between agents
- `escalation_flow.md` — when and how to escalate issues
