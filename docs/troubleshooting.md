# Troubleshooting

## Common Issues

### "Night shift already running (PID XXXXX)"

Another instance is running, or a stale lock directory exists.

**Fix:**
```bash
# Check if it's actually running
ps aux | grep night_shift

# If stale, remove the lock directory
rm -rf logs/night_shift.lock
```

### Rate Limit Errors

The night shift handles rate limits automatically (waits 60 minutes). If you're hitting limits frequently:

**Fix:**
- Reduce `MAX_ROUNDS` (fewer rounds = less API usage)
- Increase `RATE_LIMIT_WAIT` (wait longer between retries)
- Use a less aggressive cron schedule

### "Prompt file not found"

**Fix:**
```bash
# Check the prompt file exists
ls -la claude-code/prompt_template.txt

# Or specify a custom path
./night_shift.sh --prompt /path/to/your/prompt.txt
```

### Cron Job Not Triggering

**Debug:**
```bash
# Check if cron is running
systemctl status cron

# View cron logs
grep CRON /var/log/syslog | tail -20

# Verify your crontab
crontab -l | grep night-shift
```

**Common causes:**
- PATH not set in cron environment
- Wrong working directory
- Script not executable (`chmod +x`)

### Permission Denied

**Fix:**
```bash
chmod +x claude-code/night_shift.sh
chmod +x claude-code/wrapper.sh
chmod +x gemini/patrol.sh
chmod +x protocols/*.sh
chmod +x plugins/plugin_loader.sh
```

### Plugins Not Running

**Check:**
```bash
# List enabled plugins
bash plugins/plugin_loader.sh --list

# Verify symlinks are correct
ls -la plugins/enabled/

# Re-enable
ln -sf ../examples/system_health.sh plugins/enabled/system_health.sh
```

### Dashboard Shows No Data

The dashboard reads local files. Make sure you:
1. Click "Load Reports" or drag files onto the drop zones
2. Point it to files in `reports/` and `protocols/night_chat.md`

### Agents Not Communicating

**Check the protocols directory:**
```bash
# Verify inbox directories exist
ls protocols/bot_inbox/

# Check for unprocessed messages
find protocols/bot_inbox/ -name "*.json" ! -path "*/done/*"

# Check night_chat.md for recent entries
tail -20 protocols/night_chat.md
```

### Gemini CLI YOLO Mode Not Activating

When running Gemini CLI in a tmux session for automation, the `--yolo` flag may not automatically enable YOLO mode. The TUI shows "YOLO ctrl+y" (available but not active) instead of "shift+tab" (active).

**Root cause:** Gemini CLI v0.33.0's `--yolo` flag doesn't reliably toggle YOLO in interactive TUI mode.

**Fix:**

1. Add to `~/.gemini/settings.json`:
```json
{
  "approvalMode": "yolo"
}
```

2. After starting the session, programmatically toggle YOLO:
```bash
# Wait for UI to render (look for "YOLO ctrl+y" + "Type your message")
tmux capture-pane -t <session> -p | grep "YOLO"

# Send Ctrl+Y to toggle
tmux send-keys -t <session> C-y

# Verify (should show "shift+tab")
tmux capture-pane -t <session> -p | grep "shift+tab"
```

3. For production automation, implement a polling loop (up to 30 seconds) that:
   - Captures the tmux pane every second
   - Checks for UI readiness indicators
   - Sends Ctrl+Y when ready
   - Verifies the toggle succeeded

See [gemini/README.md](../gemini/README.md#known-issue-yolo-mode-in-automated-sessions) for implementation details.

## Getting Help

- **GitHub Issues:** Report bugs or request features
- **Logs:** Always include relevant log files when reporting issues
  - `logs/session_YYYY-MM-DD.log`
  - `logs/wrapper_YYYY-MM-DD.log`
  - `logs/patrol_YYYY-MM-DD.log`
