# Claude Code Night Shift Module

Run [Claude Code](https://docs.anthropic.com/en/docs/claude-code) autonomously during off-hours with automatic retry, rate-limit handling, and structured reporting.

## How It Works

```
┌─ Cron triggers at your night time ─┐
│                                     │
│  Round 1  →  Round 2  →  Round N    │
│  (2.5h)      (2.5h)     (until     │
│                          window     │
│                          ends)      │
│                                     │
│  PID lock prevents concurrent runs  │
│  Rate limits → auto-wait 60 min     │
│  Timeout → next round               │
└─────────────────────────────────────┘
```

## Quick Start

```bash
# Test with a single round
./night_shift.sh --max-rounds 1

# Full night shift (5 rounds, 6-hour window)
./night_shift.sh

# Custom configuration
./night_shift.sh --max-rounds 3 --window-hours 8 --prompt my_prompt.txt
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `MAX_ROUNDS` | 5 | Maximum number of rounds per shift |
| `WINDOW_HOURS` | 6 | Total time window in hours |
| `ROUND_TIMEOUT` | 9000 (2.5h) | Max seconds per round |
| `RATE_LIMIT_WAIT` | 3600 (1h) | Seconds to wait on rate limit |
| `SHUTDOWN_BUFFER` | 300 (5m) | Buffer before window close |
| `CLAUDE_BIN` | `claude` | Path to Claude Code CLI |

## Cron Setup

```bash
# Run at 1 AM local time, Monday-Friday
0 1 * * 1-5 cd ~/ai-night-shift && bash claude-code/night_shift.sh >> logs/cron.log 2>&1
```

## Customizing the Prompt

Edit `prompt_template.txt` to define what Claude Code does during the shift. Available template variables:

- `{ROUND}` — current round number
- `{MAX_ROUNDS}` — total rounds configured
- `{DATE}` — current date
- `{REMAINING_TIME}` — time remaining in window

See `../templates/` for specialized prompt templates (development, research, content, maintenance).

## Output

Reports are saved to `../reports/`:
- `YYYY-MM-DD_roundN.md` — individual round output
- `YYYY-MM-DD_summary.md` — compiled session summary

## Safety Features

- **PID locking** — prevents two shifts from running simultaneously
- **Timeout per round** — no single round can run forever
- **Window enforcement** — stops before exceeding the time window
- **Rate limit recovery** — detects 429 errors and waits automatically
- **Graceful shutdown** — 5-minute buffer for clean termination
