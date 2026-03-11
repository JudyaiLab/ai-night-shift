# OpenClaw Heartbeat Module

The heartbeat module provides a **periodic wake-up system** for AI agents. Unlike the continuous Claude Code runner or the cron-based Gemini patrol, the heartbeat model keeps an agent semi-dormant — waking up at regular intervals to check for work.

## Concept

```
Sleep 30min → Wake → Check inbox → Process tasks → Report → Sleep
```

This is ideal for:
- **Coordinator agents** that dispatch work to others
- **Monitoring agents** that check system health
- **Router agents** that forward tasks based on labels

## Configuration

Edit `heartbeat_config.json` to customize:

| Field | Description |
|-------|-------------|
| `interval_minutes` | How often the agent wakes up (default: 30) |
| `active_hours` | Time window for the heartbeat (e.g., 01:00-08:00) |
| `pre_check.collect` | Data sources to gather before waking the agent |
| `routing.rules` | How to forward tasks to other agents |
| `reporting.channel` | Where to send the patrol report |

## Pre-Check System

Before waking the LLM, the heartbeat collects data automatically:

1. **bot_inbox** — pending messages and tasks from other agents
2. **task_board** — assigned items from your task management tool
3. **system_health** — disk, memory, service status

This reduces LLM token usage by only presenting relevant context.

## Integration

The heartbeat module integrates with:
- [Cross-Agent Protocols](../protocols/) for inter-agent messaging
- [Plugin System](../plugins/) for extensible task handlers
- Any task management tool (Linear, GitHub Issues, Jira, etc.)

## Adapting to Your Setup

This module is designed as a **reference architecture**. To implement it:

1. Use your platform's scheduling system (cron, systemd timer, cloud scheduler)
2. Write a pre-check script that collects your specific data sources
3. Call your preferred LLM with the collected context
4. Route the output to your reporting channel

See `heartbeat_config.json` for a complete configuration example.
