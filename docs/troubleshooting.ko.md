# 문제 해결

## 일반적인 문제

### "Night shift already running (PID XXXXX)"

다른 인스턴스가 실행 중이거나 오래된 lock 디렉토리가 존재합니다.

**해결:**
```bash
# 실제로 실행 중인지 확인
ps aux | grep night_shift

# 오래된 경우 lock 디렉토리 제거
rm -rf logs/night_shift.lock
```

###Rate Limit 오류

야간 근무는 Rate Limit을 자동으로 처리합니다(60분 대기). 제한에 자주 도달하는 경우:

**해결:**
- `MAX_ROUNDS` 감소 (적은 라운드 = 적은 API 사용량)
- `RATE_LIMIT_WAIT` 증가 (재시도 간 대기 시간 증가)
- 덜 공격적인 cron 일정 사용

### "Prompt file not found"

**해결:**
```bash
# 프롬프트 파일 존재 확인
ls -la claude-code/prompt_template.txt

# 또는 사용자 정의 경로 지정
./night_shift.sh --prompt /path/to/your/prompt.txt
```

### Cron 작업이 트리거되지 않음

**디버그:**
```bash
# cron이 실행 중인지 확인
systemctl status cron

# cron 로그 보기
grep CRON /var/log/syslog | tail -20

# crontab 확인
crontab -l | grep night-shift
```

**일반적인 원인:**
- cron 환경에서 PATH가 설정되지 않음
- 잘못된 작업 디렉토리
- 스크립트 실행 불가 (`chmod +x`)

### 권한 거부

**해결:**
```bash
chmod +x claude-code/night_shift.sh
chmod +x claude-code/wrapper.sh
chmod +x gemini/patrol.sh
chmod +x protocols/*.sh
chmod +x plugins/plugin_loader.sh
```

### 플러그인이 실행되지 않음

**확인:**
```bash
# 활성화된 플러그인 나열
bash plugins/plugin_loader.sh --list

# 심볼릭 링크가 올바른지 확인
ls -la plugins/enabled/

# 다시 활성화
ln -sf ../examples/system_health.sh plugins/enabled/system_health.sh
```

### 대시보드에 데이터 없음

대시보드는 로컬 파일을 읽습니다. 다음을 확인하세요:
1. "Load Reports"를 클릭하거나 파일을 드롭 영역으로 드래그
2. `reports/` 및 `protocols/night_chat.md`의 파일 지정

### 에이전트가 통신하지 않음

**protocols 디렉토리 확인:**
```bash
# 받은 편지함 디렉토리 존재 확인
ls protocols/bot_inbox/

# 처리되지 않은 메시지 확인
find protocols/bot_inbox/ -name "*.json" ! -path "*/done/*"

# night_chat.md의 최근 항목 확인
tail -20 protocols/night_chat.md
```

### Gemini CLI YOLO 모드가 활성화되지 않음

tmux 세션에서 자동화를 위해 Gemini CLI를 실행할 때 `--yolo` 플래그가 YOLO 모드를 자동으로 활성화하지 못할 수 있습니다. TUI는 "shift+tab"(활성화됨)이 아닌 "YOLO ctrl+y"(사용 가능但비활성화됨)를 표시합니다.

**근본 원인:** Gemini CLI v0.33.0의 `--yolo` 플래그가 대화형 TUI 모드에서 YOLO를 신뢰할 수 있게 전환하지 못합니다.

**해결:**

1. `~/.gemini/settings.json`에 추가:
```json
{
  "approvalMode": "yolo"
}
```

2. 세션을 시작한 후 프로그래밍 방식으로 YOLO 전환:
```bash
# UI가 렌더링될 때까지 대기 ("YOLO ctrl+y" + "Type your message" 찾기)
tmux capture-pane -t <session> -p | grep "YOLO"

# Ctrl+Y를 보내 전환
tmux send-keys -t <session> C-y

# 확인 ("shift+tab"이 표시되어야 함)
tmux capture-pane -t <session> -p | grep "shift+tab"
```

3. 프로덕션 자동화의 경우 폴링 루프 구현(최대 30초):
   - 매초 tmux pane 캡처
   - UI 준비 상태 표시기 확인
   - 준비되면 Ctrl+Y 전송
   - 전환 성공 확인

구현 세부사항은 [gemini/README.md](../gemini/README.md#known-issue-yolo-mode-in-automated-sessions)를 참조하세요.

## 도움말 얻기

- **GitHub Issues:** 버그를 보고하거나 기능 요청
- **로그:** 문제를 보고할 때 항상 관련 로그 파일 포함
  - `logs/session_YYYY-MM-DD.log`
  - `logs/wrapper_YYYY-MM-DD.log`
  - `logs/patrol_YYYY-MM-DD.log`
