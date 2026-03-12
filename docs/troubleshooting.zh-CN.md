# 故障排除

## 常见问题

### 「Night shift already running (PID XXXXX)」

另一个实例正在运行，或存在过时的 lock 目录。

**修复：**
```bash
# 检查是否真的在运行
ps aux | grep night_shift

# 如果是过时的，移除 lock 目录
rm -rf logs/night_shift.lock
```

### 速率限制错误

夜班会自动处理速率限制（等待 60 分钟）。如果经常遇到限制：

**修复：**
- 减少 `MAX_ROUNDS`（较少回合 = 较少 API 用量）
- 增加 `RATE_LIMIT_WAIT`（重试之间等待更长时间）
- 使用较不频繁的 cron 计划

### 「Prompt file not found」

**修复：**
```bash
# 检查 prompt 文件是否存在
ls -la claude-code/prompt_template.txt

# 或指定自定义路径
./night_shift.sh --prompt /path/to/your/prompt.txt
```

### Cron 任务未触发

**调试：**
```bash
# 检查 cron 是否在运行
systemctl status cron

# 查看 cron 日志
grep CRON /var/log/syslog | tail -20

# 验证 crontab
crontab -l | grep night-shift
```

**常见原因：**
- cron 环境中 PATH 未设置
- 工作目录错误
- 脚本不可执行（`chmod +x`）

### 权限被拒

**修复：**
```bash
chmod +x claude-code/night_shift.sh
chmod +x claude-code/wrapper.sh
chmod +x gemini/patrol.sh
chmod +x protocols/*.sh
chmod +x plugins/plugin_loader.sh
```

### 插件未运行

**检查：**
```bash
# 列出已启用的插件
bash plugins/plugin_loader.sh --list

# 验证符号链接是否正确
ls -la plugins/enabled/

# 重新启用
ln -sf ../examples/system_health.sh plugins/enabled/system_health.sh
```

### 仪表板无数据

仪表板读取本地文件。请确保：
1. 点击「Load Reports」或将文件拖放到区域
2. 指向 `reports/` 和 `protocols/night_chat.md` 中的文件

### 代理之间无法通讯

**检查 protocols 目录：**
```bash
# 验证收件箱目录是否存在
ls protocols/bot_inbox/

# 检查未处理的消息
find protocols/bot_inbox/ -name "*.json" ! -path "*/done/*"

# 检查 night_chat.md 的最近条目
tail -20 protocols/night_chat.md
```

### Gemini CLI YOLO 模式未启动

在 tmux 会话中运行 Gemini CLI 进行自动化时，`--yolo` 标志可能无法自动启动 YOLO 模式。TUI 显示「YOLO ctrl+y」（可用但未启动）而非「shift+tab」（已启动）。

**根本原因：** Gemini CLI v0.33.0 的 `--yolo` 标志在互动式 TUI 模式中无法可靠地切换 YOLO。

**修复：**

1. 新增到 `~/.gemini/settings.json`:
```json
{
  "approvalMode": "yolo"
}
```

2. 启动会话后，以编程方式切换 YOLO：
```bash
# 等待 UI 呈现（寻找「YOLO ctrl+y」+「Type your message」）
tmux capture-pane -t <session> -p | grep "YOLO"

# 传送 Ctrl+Y 切换
tmux send-keys -t <session> C-y

# 验证（应显示「shift+tab」）
tmux capture-pane -t <session> -p | grep "shift+tab"
```

3. 对于生产自动化，实现轮询循环（最多 30 秒）：
   - 每秒擷取 tmux 面板
   - 检查 UI 就绪指标
   - 就绪时传送 Ctrl+Y
   - 验证切换成功

请参阅 [gemini/README.md](../gemini/README.md#known-issue-yolo-mode-in-automated-sessions) 取得实作详情。

## 取得帮助

- **GitHub Issues：** 报告错误或请求功能
- **日志：** 报告问题时务必附上相关日志文件
  - `logs/session_YYYY-MM-DD.log`
  - `logs/wrapper_YYYY-MM-DD.log`
  - `logs/patrol_YYYY-MM-DD.log`
