# 疑難排解

## 常見問題

### 「Night shift already running (PID XXXXX)」

另一個執行個體正在運行，或存在過時的 lock 目錄。

**修復：**
```bash
# 檢查是否真的在運行
ps aux | grep night_shift

# 如果是過時的，移除 lock 目錄
rm -rf logs/night_shift.lock
```

### 速率限制錯誤

夜班會自動處理速率限制（等待 60 分鐘）。如果經常遇到限制：

**修復：**
- 減少 `MAX_ROUNDS`（較少回合 = 較少 API 用量）
- 增加 `RATE_LIMIT_WAIT`（重試之間等待更長時間）
- 使用較不頻繁的 cron 排程

### 「Prompt file not found」

**修復：**
```bash
# 檢查 prompt 檔案是否存在
ls -la claude-code/prompt_template.txt

# 或指定自訂路徑
./night_shift.sh --prompt /path/to/your/prompt.txt
```

### Cron 作業未觸發

**調試：**
```bash
# 檢查 cron 是否在運行
systemctl status cron

# 查看 cron 日誌
grep CRON /var/log/syslog | tail -20

# 驗證 crontab
crontab -l | grep night-shift
```

**常見原因：**
- cron 環境中 PATH 未設定
- 工作目錄錯誤
- 腳本不可執行（`chmod +x`）

### 權限被拒

**修復：**
```bash
chmod +x claude-code/night_shift.sh
chmod +x claude-code/wrapper.sh
chmod +x gemini/patrol.sh
chmod +x protocols/*.sh
chmod +x plugins/plugin_loader.sh
```

### 外掛未運行

**檢查：**
```bash
# 列出已啟用的外掛
bash plugins/plugin_loader.sh --list

# 驗證符號連結是否正確
ls -la plugins/enabled/

# 重新啟用
ln -sf ../examples/system_health.sh plugins/enabled/system_health.sh
```

### 儀表板無資料

儀表板讀取本地檔案。請確保：
1. 點擊「Load Reports」或將檔案拖放到區域
2. 指向 `reports/` 和 `protocols/night_chat.md` 中的檔案

### 代理之間無法通訊

**檢查 protocols 目錄：**
```bash
# 驗證收件匣目錄是否存在
ls protocols/bot_inbox/

# 檢查未處理的訊息
find protocols/bot_inbox/ -name "*.json" ! -path "*/done/*"

# 檢查 night_chat.md 的最近條目
tail -20 protocols/night_chat.md
```

### Gemini CLI YOLO 模式未啟動

在 tmux 會話中運行 Gemini CLI 進行自動化時，`--yolo` 標誌可能無法自動啟用 YOLO 模式。TUI 顯示「YOLO ctrl+y」（可用但未啟動）而非「shift+tab」（已啟動）。

**根本原因：** Gemini CLI v0.33.0 的 `--yolo` 標誌在互動式 TUI 模式中無法可靠地切換 YOLO。

**修復：**

1. 新增到 `~/.gemini/settings.json`:
```json
{
  "approvalMode": "yolo"
}
```

2. 啟動會話後，以程式方式切換 YOLO：
```bash
# 等待 UI 呈現（尋找「YOLO ctrl+y」+「Type your message」）
tmux capture-pane -t <session> -p | grep "YOLO"

# 傳送 Ctrl+Y 切換
tmux send-keys -t <session> C-y

# 驗證（應顯示「shift+tab」）
tmux capture-pane -t <session> -p | grep "shift+tab"
```

3. 對於生產自動化，實現輪詢循環（最多 30 秒）：
   - 每秒擷取 tmux 面板
   - 檢查 UI 就緒指標
   - 就緒時傳送 Ctrl+Y
   - 驗證切換成功

請參閱 [gemini/README.md](../gemini/README.md#known-issue-yolo-mode-in-automated-sessions) 取得實作詳情。

## 取得協助

- **GitHub Issues：** 報告錯誤或請求功能
- **日誌：** 報告問題時務必附上相關日誌檔案
  - `logs/session_YYYY-MM-DD.log`
  - `logs/wrapper_YYYY-MM-DD.log`
  - `logs/patrol_YYYY-MM-DD.log`
