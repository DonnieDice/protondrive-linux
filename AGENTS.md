# Agent Operations Manual

**Version**: 7.0  
**Purpose**: Prevent confusion, maintain context, track changes

---

## THREE SYSTEMS

| System | Purpose | Location |
|--------|---------|----------|
| **Session Log** | Prevent loops, track reasoning | `.agent_logs/session_YYYYMMDD_HHMMSS.log` |
| **Memory File** | Persist context across sessions | `.agent_logs/MEMORY.md` |
| **Changelog** | Track project changes | `CHANGELOG.md` |

---

## 1. SESSION LOGGING (Anti-Loop)

### Purpose
Prevent getting lost or stuck in loops by logging decisions and actions.

### Setup (Start of Every Session)
```bash
mkdir -p .agent_logs
LOG=".agent_logs/session_$(date +%Y%m%d_%H%M%S).log"
echo "[START] $(date -Iseconds)" >> "$LOG"
```

### What to Log

**Decisions** (before acting):
```
[DECIDE] What: Select next task | Why: Phase 1.2 unblocked | Choice: Encryption layer
```

**Actions** (after completing):
```
[ACTION] Created internal/encryption/gopenpgp.go (847 chars)
[ACTION] Ran tests: 12 passed, 0 failed
```

**Blockers** (when stuck):
```
[STUCK] Problem: API returns 429 | Tried: Retry 3x | Next: Check rate limit config
```

### Loop Detection

**You're in a loop if:**
- Same action appears 3+ times in last 10 entries
- Same error appears 3+ times
- No `[ACTION]` entries in last 5 minutes

**Breaking loops:**
1. Log: `[LOOP] Detected: [pattern]`
2. Stop current approach
3. Try different approach OR skip task
4. Log: `[LOOP] Broke via: [new approach]`

### Minimum Logging
- Simple task: 5+ entries
- Complex task: 10+ entries
- If fewer: you're not logging enough

---

## 2. MEMORY FILE (Cross-Session Context)

### Purpose
Remember important context between sessions.

### Location
`.agent_logs/MEMORY.md`

### Structure
```markdown
# Agent Memory

## Last Session
- Date: YYYY-MM-DD
- Completed: [list of completed tasks]
- In Progress: [current task if interrupted]
- Blockers: [any known blockers]

## Key Decisions
- [Date]: Chose GopenPGP over SQLCipher because [reason]
- [Date]: Deferred GUI work until encryption complete

## Known Issues
- fsnotify doesn't work on NFS (use polling fallback)
- Fyne table widget has performance issues >1000 rows

## User Preferences
- [Any stated preferences from conversation]
```

### When to Update
- End of session (always)
- After major decision
- When discovering important issue
- When user states preference

---

## 3. CHANGELOG (Project Changes)

### Purpose
Track what changed in the codebase for users and future reference.

### Location
`CHANGELOG.md` (project root)

### Format (Keep It Simple)
```markdown
# Changelog

## [Unreleased]
### Added
- GopenPGP encryption wrapper (internal/encryption/)
- Keyring integration with fallback chain

### Changed
- Simplified crypto stack from 15 to 6 dependencies

### Fixed
- Config validation now rejects empty sync paths

### Removed
- SQLCipher dependency (replaced with GopenPGP)

## [0.1.0] - 2024-12-15
### Added
- Initial project structure
- Basic configuration system
```

### Categories
- **Added**: New features/files
- **Changed**: Modifications to existing
- **Fixed**: Bug fixes
- **Removed**: Deleted features/files
- **Security**: Security-related changes
- **Deprecated**: Soon-to-be-removed features

### When to Update
- After completing any task that changes code/docs
- Group related changes together
- Update `[Unreleased]` section; version on release

---

## QUICK REFERENCE

### Session Start Checklist
1. [ ] Create session log file
2. [ ] Read MEMORY.md for context
3. [ ] Read TASKS.md for current priorities
4. [ ] Log: `[START] Resuming from: [last state]`

### During Session
- Log decisions before acting
- Log actions after completing
- Check for loops every 5 tasks
- Update MEMORY.md if learning something important

### Session End Checklist
1. [ ] Update MEMORY.md with session summary
2. [ ] Update CHANGELOG.md with any project changes
3. [ ] Update TASKS.md checkboxes
4. [ ] Log: `[END] Completed: [summary]`

---

## WHEN STUCK

### Decision Tree
```
Stuck on task?
├─ Error message? → Search/fix error → Log solution
├─ No progress? → Check if blocked → Log blocker → Try different approach
├─ Loop detected? → Stop → Try different approach → Log what broke loop
└─ Still stuck after 3 attempts? → Skip task → Log why → Move to next
```

### Escape Hatches
1. **Different approach**: Same goal, different method
2. **Skip and return**: Move to next task, revisit later
3. **Reduce scope**: Do simpler version first
4. **Ask for help**: Note question in MEMORY.md for next session

---

## FILE SIZE LIMITS

| Threshold | Action |
|-----------|--------|
| < 1MB | ✅ Safe |
| 1-1.5MB | ⚠️ Monitor |
| 1.5-2MB | 🔶 Consider splitting |
| > 2MB | ❌ Must split |

**Before creating large files**: Check size, split if needed.

---

## CONTEXT MANAGEMENT

### Token Thresholds
| Usage | Action |
|-------|--------|
| < 50% | Normal operation |
| 50-70% | Be aware, summarize if needed |
| 70-80% | Wrap up current task |
| > 80% | Save state, end session |

### When Context High
1. Complete current task
2. Update MEMORY.md thoroughly
3. Update CHANGELOG.md
4. Log session end
5. Summarize for next session

---

## EXAMPLE SESSION

```
# Session Log: 2024-12-10 14:30:00

[START] Resuming from: Phase 1.1 complete, starting 1.2 encryption layer
[DECIDE] What: First task | Why: Encryption is P0 | Choice: Create gopenpgp.go
[ACTION] Created internal/encryption/gopenpgp.go (1247 chars)
[DECIDE] What: Test approach | Why: 100% coverage required | Choice: Table-driven tests
[ACTION] Created internal/encryption/gopenpgp_test.go (892 chars)
[ACTION] Ran tests: 5 passed, 0 failed
[DECIDE] What: Next | Why: Core done | Choice: Add keyring integration
[STUCK] Problem: go-keyring import error | Tried: go get | Next: Check module path
[ACTION] Fixed: module was github.com/zalando/go-keyring (not go-keyring)
[ACTION] Created internal/encryption/keyring.go (634 chars)
[END] Completed: gopenpgp.go, keyring.go with tests. Next: memory.go
```

---

**Remember**: Logging is for YOU. It prevents confusion and loops. Keep it brief but useful.