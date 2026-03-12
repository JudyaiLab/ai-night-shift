# Plugin System

Extend your night shift with custom plugins. Plugins run at specific phases of the night shift lifecycle.

## Phases

| Phase | When | Use Case |
|-------|------|----------|
| `pre` | Before the night shift starts | System health checks, backups, data collection |
| `task` | During each round | Custom tasks, monitoring, reporting |
| `post` | After the night shift ends | Report generation, cleanup, notifications |

## Creating a Plugin

Create a bash script with these header comments:

```bash
#!/usr/bin/env bash
# PLUGIN_NAME: My Plugin
# PLUGIN_PHASE: pre
# PLUGIN_DESCRIPTION: Brief description of what it does

set -euo pipefail

NIGHT_SHIFT_DIR="${NIGHT_SHIFT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

# Your code here
echo "Plugin running!"
```

## Enabling Plugins

```bash
# Enable an example plugin
ln -s ../examples/system_health.sh plugins/enabled/system_health.sh

# Or copy and customize
cp plugins/examples/system_health.sh plugins/enabled/
```

## Available Example Plugins

| Plugin | Phase | Description |
|--------|-------|-------------|
| `system_health.sh` | pre | Disk, memory, Docker health check |
| `backup.sh` | pre | Backup configs and chat history |
| `de_sloppify.sh` | task | Quality cleanup pass — removes code slop |
| `git_commit_summary.sh` | post | Summary of all commits made |
| `morning_report.sh` | post | Compile morning briefing + TG push |

## Running Plugins

```bash
# Run all enabled plugins
./plugins/plugin_loader.sh

# Run only pre-shift plugins
./plugins/plugin_loader.sh --phase pre

# List all plugins
./plugins/plugin_loader.sh --list
```

## Plugin Guidelines

1. **Timeout:** Each plugin has a 5-minute max execution time
2. **Exit codes:** Return 0 for success, non-zero for failure (won't block the shift)
3. **Logging:** Write output to stdout — the loader captures it
4. **No secrets:** Don't hardcode API keys; use environment variables
5. **Idempotent:** Plugins may run multiple times; handle gracefully
