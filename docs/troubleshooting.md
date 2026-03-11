# Troubleshooting

## Common Issues

### "Night shift already running (PID XXXXX)"

Another instance is running, or a stale PID file exists.

**Fix:**
```bash
# Check if it's actually running
ps aux | grep night_shift

# If stale, remove the PID file
rm logs/night_shift.pid
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

## Getting Help

- **GitHub Issues:** Report bugs or request features
- **Logs:** Always include relevant log files when reporting issues
  - `logs/session_YYYY-MM-DD.log`
  - `logs/wrapper_YYYY-MM-DD.log`
  - `logs/patrol_YYYY-MM-DD.log`
