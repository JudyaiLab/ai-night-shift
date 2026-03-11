# Shift Handoff Document

> Template for passing context between agents at shift boundaries.
> Copy this file and fill in before each shift transition.

## Handoff: {FROM_AGENT} → {TO_AGENT}

**Date:** {DATE}
**Time:** {TIME}

---

## What I Did This Shift

- [ ] Task 1 description — status
- [ ] Task 2 description — status
- [ ] Task 3 description — status

## In Progress (Needs Continuation)

| Task | Status | What's Left | Priority |
|------|--------|-------------|----------|
| TASK-XX | 70% done | Need to finish tests | High |

## Issues Found

- **Issue 1:** Description, severity, suggested fix
- **Issue 2:** Description, severity, suggested fix

## Decisions Made

- Decided to use X approach because Y
- Chose library Z over W because of performance

## Notes for Next Agent

- Watch out for [specific concern]
- File X was refactored — check if tests still pass
- The API rate limit resets at [time]

## Environment State

- Branch: `feature/xxx`
- Last commit: `abc1234 - commit message`
- Tests: passing / X failing
- Services: all running / [service] needs restart
