# Escalation Flow

> When and how AI agents should escalate issues during autonomous night shifts.

## Escalation Levels

### Level 0: Self-Resolve
**Trigger:** Minor issues within agent's capability
**Action:** Fix it, log it, move on
**Example:** Lint warning, minor test fix, documentation typo

### Level 1: Peer Agent
**Trigger:** Need input from another agent's domain
**Action:** Send message via `msg.sh`, continue other work
**Example:** Claude needs research → message Gemini

### Level 2: Human Review Queue
**Trigger:** Decision requires human judgment
**Action:** Log to `escalations.md`, continue non-blocked work
**Example:** Architecture decision, security concern, budget impact

### Level 3: Immediate Alert
**Trigger:** Service down, security breach, data loss risk
**Action:** Send alert via configured channel (TG/Slack/email)
**Example:** Database unreachable, suspicious activity, disk full

## Decision Tree

```
Issue Found
├── Can I fix it myself?
│   ├── Yes → Fix it (Level 0)
│   └── No ─┐
│            ├── Does another agent have expertise?
│            │   ├── Yes → Message them (Level 1)
│            │   └── No ─┐
│            │            ├── Is it urgent/breaking?
│            │            │   ├── Yes → Immediate Alert (Level 3)
│            │            │   └── No → Queue for human (Level 2)
```

## Escalation Message Format

```json
{
  "level": 2,
  "agent": "claude",
  "issue": "Brief description",
  "context": "What was being done when this was found",
  "attempted": "What was tried to resolve it",
  "suggestion": "Recommended next step",
  "blocking": ["TASK-42", "TASK-43"]
}
```

## Rules

1. **Never ignore** — every issue gets classified and logged
2. **Don't guess on security** — when in doubt, escalate to Level 2+
3. **Don't block on Level 1** — send the message and continue other work
4. **Rate limit alerts** — max 3 Level 3 alerts per shift (prevent alert fatigue)
5. **Include context** — always explain what you tried before escalating
