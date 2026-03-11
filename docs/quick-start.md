# Quick Start Guide

Get your AI Night Shift running in 5 minutes.

## Prerequisites

- Linux or macOS
- Bash 4+ and Python 3.6+
- At least one AI CLI tool installed:
  - **Claude Code:** `npm install -g @anthropic-ai/claude-code`
  - **Gemini CLI:** `npm install -g @google/gemini-cli`

## Step 1: Install

```bash
git clone https://github.com/judyailab/ai-night-shift.git
cd ai-night-shift
bash install.sh
```

The installer will:
- Create the directory structure
- Set file permissions
- Optionally configure cron jobs

## Step 2: Configure

```bash
cp config.env.example config.env
nano config.env
```

Key settings to adjust:
- `WINDOW_HOURS` — how long the night shift runs
- `MAX_ROUNDS` — maximum number of rounds
- `CLAUDE_BIN` / `GEMINI_BIN` — path to your CLI tools

## Step 3: Customize the Prompt

Edit the prompt template to tell your AI what to do:

```bash
nano claude-code/prompt_template.txt
```

Or use one of the pre-built templates:
```bash
cp templates/development.txt claude-code/prompt_template.txt
```

## Step 4: Test

Run a single round to verify everything works:

```bash
bash claude-code/night_shift.sh --max-rounds 1
```

Check the output:
```bash
cat reports/$(date +%Y-%m-%d)_round1.md
```

## Step 5: Schedule

The installer can set up cron jobs automatically. To do it manually:

```bash
crontab -e
```

Add your preferred schedule:
```
# Night shift at 1 AM (adjust timezone)
0 1 * * * cd ~/ai-night-shift && bash claude-code/wrapper.sh >> logs/cron.log 2>&1

# Gemini patrol every 2 hours during night
0 1,3,5,7 * * * cd ~/ai-night-shift && bash gemini/patrol.sh >> logs/patrol.log 2>&1
```

## Step 6: Enable Plugins (Optional)

```bash
# Enable system health check (runs before shift)
ln -s ../examples/system_health.sh plugins/enabled/system_health.sh

# Enable morning report (runs after shift)
ln -s ../examples/morning_report.sh plugins/enabled/morning_report.sh
```

## Step 7: Monitor

Open the dashboard:
```bash
open dashboard/index.html
# or
xdg-open dashboard/index.html
```

Drag and drop report files to visualize your night shift activity.

## Next Steps

- **[Architecture](architecture.md)** — understand how the system works
- **[Advanced Guide](advanced.md)** — multi-agent setup, custom plugins
- **[Troubleshooting](troubleshooting.md)** — common issues and fixes
