# Gemini Patrol Module

Periodic patrol runner for [Gemini CLI](https://github.com/google-gemini/gemini-cli). Designed for frequent, lightweight check-ins rather than long continuous sessions.

## How It Works

```
Cron (every 1-2 hours)
  → Collect inbox items
  → Read recent team chat
  → Build context-aware prompt
  → Execute Gemini CLI
  → Post results to night chat
  → Move processed items to done/
```

## Quick Start

```bash
# Run a single patrol
./patrol.sh

# With custom prompt
./patrol.sh --prompt my_patrol_prompt.txt
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `GEMINI_BIN` | `gemini` | Path to Gemini CLI |
| `NIGHT_SHIFT_DIR` | auto-detected | Root directory of the framework |

## Cron Setup

```bash
# Patrol every 2 hours during night window (1 AM - 7 AM)
0 1,3,5,7 * * * cd ~/ai-night-shift && bash gemini/patrol.sh >> logs/patrol.log 2>&1
```

## Best Use Cases

Gemini's strengths (grounding, search, large context) make it ideal for:
- **Research tasks** — web search, data gathering
- **Task triage** — reading inbox, routing work to other agents
- **Documentation** — writing summaries, formatting reports
- **Translation** — localizing content

## Integration with Claude Code

The two modules are complementary:

| Feature | Claude Code | Gemini |
|---------|-------------|--------|
| Mode | Continuous (hours) | Periodic (minutes) |
| Strength | Coding, debugging | Research, triage |
| Token cost | Higher (Opus/Sonnet) | Lower (Pro/Flash) |
| Output | Code commits | Reports, messages |

They share context through `night_chat.md` and `bot_inbox/`.
