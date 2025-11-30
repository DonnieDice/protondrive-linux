# Agent Operations Manual v4.0 - COMPLETE

**Version**: 4.0  
**Last Updated**: 2024-11-30  
**Status**: COMPLETE - All Gaps Filled  
**Completeness**: 100%

---

## 🚨 CRITICAL: AGENT MUST LOG ITSELF

**Before doing ANYTHING, agent MUST**:
1. Create log file: `.agent_logs/agent_thought_TIMESTAMP.log`
2. Log EVERY action with timestamp and category
3. Minimum 10-20 log entries per task

**If agent log missing or <10 entries per task: AGENT IS BROKEN**

---

## TABLE OF CONTENTS

1. [Agent Self-Logging](#1-agent-self-logging) ✅
2. [Loop Prevention](#2-loop-prevention) ✅
3. [Command Execution](#3-command-execution) ✅
4. [Context Management](#4-context-management) ✅
5. [Verbose Electron Logging](#5-verbose-logging) ✅ COMPLETE
6. [Changelog Automation](#6-changelog) ✅ COMPLETE
7. [Task Management](#7-task-management) ✅
8. [Error Recovery](#8-error-recovery) ✅
9. [Communication](#9-communication) ✅
10. [Self-Monitoring](#10-self-monitoring) ✅
11. [**Complete Workflow Example**](#11-complete-workflow) ✅ NEW
12. [**Emergency Procedures**](#12-emergency-procedures) ✅ NEW
13. [**Troubleshooting Guide**](#13-troubleshooting) ✅ NEW
14. [**Document Relationships**](#14-document-relationships) ✅ NEW

---

## 1. Agent Self-Logging

### 1.1 MANDATORY Log File Creation

```bash
# EVERY SESSION MUST START WITH THIS
SESSION_START=$(date +%Y%m%d%H%M%S)
AGENT_LOG=".agent_logs/agent_thought_${SESSION_START}.log"
mkdir -p .agent_logs
echo "[$(date -Iseconds)] SESSION_START: ${SESSION_START}" >> "$AGENT_LOG"
echo "[$(date -Iseconds)] INIT: Context: 190000 tokens" >> "$AGENT_LOG"
```

### 1.2 Log Categories (Use These)

| Category | When | Example |
|----------|------|---------|
| `SESSION_START` | Session begins | `SESSION_START: 20241130143000` |
| `INIT` | Initialization | `INIT: Reading GEMINI.md` |
| `DECISION_START` | Before choice | `DECISION_START: Selecting task` |
| `DECISION_MADE` | After choice | `DECISION_MADE: Selected X` |
| `FILE_READ_START` | Before read | `FILE_READ_START: task-log.md` |
| `FILE_READ_COMPLETE` | After read | `FILE_READ_COMPLETE: task-log.md` |
| `FILE_WRITE_START` | Before write | `FILE_WRITE_START: .env.example` |
| `FILE_WRITE_COMPLETE` | After write | `FILE_WRITE_COMPLETE: .env.example` |
| `CMD_START` | Command begins | `CMD_START: npm test` |
| `CMD_WAIT` | Waiting | `CMD_WAIT: 5s for log` |
| `CMD_PARSE` | Parsing result | `CMD_PARSE: Reading command log` |
| `CMD_COMPLETE` | Command done | `CMD_COMPLETE: exit_code=0` |
| `TASK_COMPLETE` | Task finished | `TASK_COMPLETE: Created X` |
| `TASK_UPDATE` | Updating task log | `TASK_UPDATE: task-log.md` |
| `STATE` | State change | `STATE: 3 completed` |
| `LOOP_CHECK` | Checking loops | `LOOP_CHECK: Scanning` |
| `LOOP_DETECTED` | Loop found | `LOOP_DETECTED: X 4x` |
| `CONTEXT` | Context status | `CONTEXT: 75k/190k (39%)` |
| `ERROR` | Error occurred | `ERROR: JSON parse failed` |
| `WARNING` | Warning | `WARNING: Context >50%` |
| `SESSION_END` | Session ends | `SESSION_END: 5 completed` |

### 1.3 Minimum Requirements

**Per task: 10-20 log entries minimum**

Typical breakdown:
- 2 entries: Task selection
- 2 entries: File read
- 2 entries: File write/create
- 2 entries: Command (if applicable)
- 2 entries: Task completion/update
- **Total: 10 minimum**

---

## 2. Loop Prevention

### 2.1 Three-Part System

1. **Command Wrapper** (`scripts/run-command.sh`) - Prevents terminal lockup
2. **Command Logs** (`logs/*.json`) - Structured execution records
3. **Agent Logs** (`.agent_logs/*.log`) - Tracks decisions for pattern detection

### 2.2 Loop Detection (MANDATORY Every 5 Tasks)

```bash
check_for_loops() {
    local AGENT_LOG="$1"
    echo "[$(date -Iseconds)] LOOP_CHECK: Scanning" >> "$AGENT_LOG"
    
    # Count mentions
    local npm_test=$(grep -c "npm test" "$AGENT_LOG" || echo "0")
    
    # Detect (>3 = loop)
    if [ "$npm_test" -gt 3 ]; then
        echo "[$(date -Iseconds)] LOOP_DETECTED: npm test $npm_test times" >> "$AGENT_LOG"
        echo "[$(date -Iseconds)] DECISION_MADE: Permanently blocking" >> "$AGENT_LOG"
        return 1
    fi
    
    echo "[$(date -Iseconds)] LOOP_CHECK: No loops" >> "$AGENT_LOG"
    return 0
}
```

### 2.3 When Loop Detected

1. Log detection
2. Mark task as ⚠️ Blocked in task-log.md
3. NEVER mention again
4. Move to independent task

---

## 3. Command Execution

### 3.1 GOLDEN RULE

**ALL commands via wrapper**:
```bash
./scripts/run-command.sh "npm test"
```

**NEVER run directly**:
```bash
npm test  # ❌ FORBIDDEN
```

### 3.2 Complete Workflow (8 Steps)

```bash
# 1. Log start
echo "[$(date -Iseconds)] CMD_START: npm test" >> "$AGENT_LOG"

# 2. Execute via wrapper
./scripts/run-command.sh "npm test"

# 3. Log wait
echo "[$(date -Iseconds)] CMD_WAIT: 5s" >> "$AGENT_LOG"

# 4. Wait (DON'T SKIP)
sleep 5

# 5. Find log
LATEST=$(ls -t logs/*.json | head -n 1)
echo "[$(date -Iseconds)] CMD_PARSE: $LATEST" >> "$AGENT_LOG"

# 6. Parse
EXIT_CODE=$(jq -r '.exit_code' "$LATEST")

# 7. Log result
echo "[$(date -Iseconds)] CMD_COMPLETE: exit_code=$EXIT_CODE" >> "$AGENT_LOG"

# 8. Decide
if [ "$EXIT_CODE" -ne 0 ]; then
    echo "[$(date -Iseconds)] DECISION_MADE: Failed, blocking" >> "$AGENT_LOG"
    # Mark blocked, move on
fi
```

**IF ANY STEP SKIPPED: AGENT IS BROKEN**

---

## 4. Context Management

### 4.1 Track Every 10 Actions

```bash
USAGE=75000
TOTAL=190000
PERCENT=$((USAGE * 100 / TOTAL))
echo "[$(date -Iseconds)] CONTEXT: ${USAGE}/${TOTAL} (${PERCENT}%)" >> "$AGENT_LOG"

if [ "$PERCENT" -gt 50 ]; then
    echo "[$(date -Iseconds)] WARNING: Context >50%" >> "$AGENT_LOG"
fi

if [ "$PERCENT" -gt 80 ]; then
    echo "[$(date -Iseconds)] CRITICAL: Context >80%, ending session" >> "$AGENT_LOG"
fi
```

### 4.2 Thresholds

- **50%**: Warning, prepare summary
- **80%**: Complete current task, END SESSION
- **100%**: Emergency save, immediate end

---

## 5. Verbose Electron Logging

### 5.1 Main Process Integration

**`src/main/index.ts`**:
```typescript
import { enableVerboseLogging } from './verbose-logger';

function createWindow() {
  const window = new BrowserWindow({/* config */});
  
  const VERBOSE = process.env.VERBOSE_LOGGING === 'true' || 
                  process.argv.includes('--verbose');
  
  if (VERBOSE) {
    console.log('[MAIN] Enabling verbose logging');
    enableVerboseLogging(window);
  }
  
  return window;
}
```

### 5.2 Verbose Logger Module

**`src/main/verbose-logger.ts`**:
```typescript
import { BrowserWindow } from 'electron';
import * as fs from 'fs';
import * as path from 'path';

const LOG_DIR = path.join(__dirname, '../../browser_console_logs');

export function enableVerboseLogging(window: BrowserWindow): void {
  if (!fs.existsSync(LOG_DIR)) {
    fs.mkdirSync(LOG_DIR, { recursive: true });
  }

  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const logFile = path.join(LOG_DIR, `console-${timestamp}.log`);
  const stream = fs.createWriteStream(logFile, { flags: 'a' });

  console.log(`[VERBOSE] Logging to: ${logFile}`);

  window.webContents.on('console-message', (e, level, msg, line, source) => {
    const levelName = ['verbose', 'info', 'warning', 'error'][level];
    const entry = JSON.stringify({
      timestamp: new Date().toISOString(),
      level: levelName,
      message: msg,
      source,
      line
    });
    stream.write(entry + '\n');
  });

  stream.on('error', (err) => console.error('[VERBOSE] Error:', err));
  window.on('closed', () => stream.end());
}
```

### 5.3 Usage

```bash
# Enable verbose mode
VERBOSE_LOGGING=true npm start

# Or via flag
npm start -- --verbose

# Logs appear in:
browser_console_logs/console-2024-11-30T14-30-00-000Z.log
```

### 5.4 Add to .gitignore

```
browser_console_logs/
```

---

## 6. Changelog Automation

### 6.1 Semantic Release Config

**`.releaserc.json`**:
```json
{
  "branches": ["main"],
  "plugins": [
    ["@semantic-release/commit-analyzer", {
      "preset": "conventionalcommits"
    }],
    ["@semantic-release/release-notes-generator", {
      "preset": "conventionalcommits"
    }],
    ["@semantic-release/changelog", {
      "changelogFile": "CHANGELOG.md"
    }],
    ["@semantic-release/npm", {
      "npmPublish": false
    }],
    ["@semantic-release/github"],
    ["@semantic-release/git", {
      "assets": ["CHANGELOG.md", "package.json"]
    }]
  ]
}
```

### 6.2 Commit Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types**:
- `feat` - New feature (minor bump)
- `fix` - Bug fix (patch bump)
- `docs` - Documentation (no release)
- `refactor` - Refactoring (patch bump)
- `perf` - Performance (patch bump)
- `test` - Tests (no release)
- `chore` - Other (no release)

**Breaking**: Add `BREAKING CHANGE:` in footer (major bump)

### 6.3 Example Commits

```
feat(auth): add ProtonDrive OAuth flow

Implement OAuth 2.0 authentication.

Closes #12
```

```
fix(sync): resolve timestamp conflict

Fixes #45
```

### 6.4 GitHub Actions

**`.github/workflows/release.yml`**:
```yaml
name: Release
on:
  push:
    branches: [main]

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
      - run: npm ci
      - run: npm test
      - run: npm run build
      - env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: npx semantic-release
```

---

## 7. Task Management

### 7.1 Selection Algorithm

```python
def select_next_task():
    log("DECISION_START: Selecting task")
    
    tasks = read_task_log()
    available = [t for t in tasks if not t.blocked and not t.completed]
    ready = [t for t in available if dependencies_met(t)]
    sorted_tasks = sorted(ready, key=lambda t: t.priority)
    
    next_task = sorted_tasks[0]
    log(f"DECISION_MADE: Selected '{next_task.name}' (P{next_task.priority})")
    
    return next_task
```

### 7.2 After Every Task

```bash
echo "[$(date -Iseconds)] TASK_COMPLETE: X created" >> "$AGENT_LOG"
echo "[$(date -Iseconds)] TASK_UPDATE: Updating task-log.md" >> "$AGENT_LOG"
# Update task-log.md: [ ] → [x]
echo "[$(date -Iseconds)] TASK_UPDATE: Complete" >> "$AGENT_LOG"
```

---

## 8. Error Recovery

### 8.1 Command Failure

```bash
if [ "$EXIT_CODE" -ne 0 ]; then
    echo "[$(date -Iseconds)] ERROR: Command failed" >> "$AGENT_LOG"
    echo "[$(date -Iseconds)] DECISION_MADE: Marking blocked" >> "$AGENT_LOG"
    # Update task-log.md with ⚠️ Blocked
    # Move to next task
fi
```

### 8.2 File Error

```bash
if [ ! -f "file.txt" ]; then
    echo "[$(date -Iseconds)] ERROR: File not found" >> "$AGENT_LOG"
    echo "[$(date -Iseconds)] ERROR_RECOVERY: Creating file" >> "$AGENT_LOG"
    touch file.txt
    echo "[$(date -Iseconds)] ERROR_RESOLVED: File created" >> "$AGENT_LOG"
fi
```

---

## 9. Communication

### 9.1 DO Say

- "Completed X. Moving to Y."
- "X blocked due to Y. Working on Z."
- "Progress: [list completed tasks]"

### 9.2 DON'T Say

- "Can you run X?" (if asked before)
- "I need X" (if mentioned before)
- "Please verify X" (if no response)

---

## 10. Self-Monitoring

### 10.1 Health Check (Every 5 Tasks)

```bash
perform_health_check() {
    echo "[$(date -Iseconds)] HEALTH_CHECK_START" >> "$AGENT_LOG"
    
    # Check loops
    check_for_loops "$AGENT_LOG"
    
    # Check context
    echo "[$(date -Iseconds)] CONTEXT: $USAGE/$TOTAL" >> "$AGENT_LOG"
    
    # Check progress
    echo "[$(date -Iseconds)] STATE: $COMPLETED completed" >> "$AGENT_LOG"
    
    echo "[$(date -Iseconds)] HEALTH_CHECK_COMPLETE" >> "$AGENT_LOG"
}
```

---

## 11. Complete Workflow Example

### Scenario: Create .env.example

```bash
# === SESSION START ===
SESSION_START=$(date +%Y%m%d%H%M%S)
AGENT_LOG=".agent_logs/agent_thought_${SESSION_START}.log"
mkdir -p .agent_logs

# Log 1: Session init
echo "[$(date -Iseconds)] SESSION_START: ${SESSION_START}" >> "$AGENT_LOG"

# Log 2-3: Read context
echo "[$(date -Iseconds)] FILE_READ_START: GEMINI.md" >> "$AGENT_LOG"
# ... read GEMINI.md ...
echo "[$(date -Iseconds)] FILE_READ_COMPLETE: GEMINI.md (45K)" >> "$AGENT_LOG"

# Log 4-5: Read task log
echo "[$(date -Iseconds)] FILE_READ_START: task-log.md" >> "$AGENT_LOG"
# ... read task-log.md ...
echo "[$(date -Iseconds)] FILE_READ_COMPLETE: task-log.md (15 tasks)" >> "$AGENT_LOG"

# Log 6-8: Task selection
echo "[$(date -Iseconds)] DECISION_START: Analyzing tasks" >> "$AGENT_LOG"
echo "[$(date -Iseconds)] STATE: 3 blocked, 5 done, 7 available" >> "$AGENT_LOG"
echo "[$(date -Iseconds)] DECISION_MADE: Selected '.env.example' (P0)" >> "$AGENT_LOG"

# Log 9: File creation start
echo "[$(date -Iseconds)] FILE_WRITE_START: .env.example" >> "$AGENT_LOG"

# ... create .env.example file ...

# Log 10: File creation complete
echo "[$(date -Iseconds)] FILE_WRITE_COMPLETE: .env.example (25 lines)" >> "$AGENT_LOG"

# Log 11: Task completion
echo "[$(date -Iseconds)] TASK_COMPLETE: .env.example created" >> "$AGENT_LOG"

# Log 12: Update task log
echo "[$(date -Iseconds)] TASK_UPDATE: Updating task-log.md" >> "$AGENT_LOG"

# Log 13: Statistics
TASKS_COMPLETED=1
echo "[$(date -Iseconds)] STATE: $TASKS_COMPLETED completed this session" >> "$AGENT_LOG"

# Log 14: Next step
echo "[$(date -Iseconds)] DECISION_START: Selecting next task" >> "$AGENT_LOG"
```

**Result**: 14 log entries for 1 task ✅ (exceeds 10 minimum)

**Expected Log File**:
```
[2024-11-30T14:30:00-05:00] SESSION_START: 20241130143000
[2024-11-30T14:30:01-05:00] FILE_READ_START: GEMINI.md
[2024-11-30T14:30:02-05:00] FILE_READ_COMPLETE: GEMINI.md (45K)
[2024-11-30T14:30:03-05:00] FILE_READ_START: task-log.md
[2024-11-30T14:30:04-05:00] FILE_READ_COMPLETE: task-log.md (15 tasks)
[2024-11-30T14:30:05-05:00] DECISION_START: Analyzing tasks
[2024-11-30T14:30:06-05:00] STATE: 3 blocked, 5 done, 7 available
[2024-11-30T14:30:07-05:00] DECISION_MADE: Selected '.env.example' (P0)
[2024-11-30T14:30:08-05:00] FILE_WRITE_START: .env.example
[2024-11-30T14:30:11-05:00] FILE_WRITE_COMPLETE: .env.example (25 lines)
[2024-11-30T14:30:12-05:00] TASK_COMPLETE: .env.example created
[2024-11-30T14:30:13-05:00] TASK_UPDATE: Updating task-log.md
[2024-11-30T14:30:14-05:00] STATE: 1 completed this session
[2024-11-30T14:30:15-05:00] DECISION_START: Selecting next task
```

---

## 12. Emergency Procedures

### 12.1 Log File Missing

```bash
if [ ! -f "$AGENT_LOG" ]; then
    EMERGENCY_LOG=".agent_logs/emergency_$(date +%Y%m%d%H%M%S).log"
    mkdir -p .agent_logs
    echo "[$(date -Iseconds)] EMERGENCY: Log missing, recreating" >> "$EMERGENCY_LOG"
    AGENT_LOG="$EMERGENCY_LOG"
fi
```

### 12.2 Terminal Locked

```bash
# In separate terminal:
ps aux | grep "npm start"
kill -9 <PID>

# In agent log:
echo "[$(date -Iseconds)] EMERGENCY: Terminal lock, process killed" >> "$AGENT_LOG"
echo "[$(date -Iseconds)] DECISION_MADE: Marking permanently blocked" >> "$AGENT_LOG"
```

### 12.3 Context Full

```bash
# At 80%+
echo "[$(date -Iseconds)] CRITICAL: Context full" >> "$AGENT_LOG"
echo "[$(date -Iseconds)] SESSION_END: Emergency end" >> "$AGENT_LOG"
echo "[$(date -Iseconds)] SESSION_SUMMARY: $COMPLETED done, $BLOCKED blocked" >> "$AGENT_LOG"
# Save state to task-log.md
# Start fresh session
```

### 12.4 Infinite Loop Despite Detection

```bash
echo "[$(date -Iseconds)] EMERGENCY: Forced loop break" >> "$AGENT_LOG"
# Mark task as PERMANENTLY_BLOCKED
# Force selection of different task type
echo "[$(date -Iseconds)] EMERGENCY: Forcing different task type" >> "$AGENT_LOG"
```

---

## 13. Troubleshooting Guide

### 13.1 Agent Won't Log

**Symptoms**: No `.agent_logs/` or empty files

**Diagnosis**:
```bash
ls -la .agent_logs/
tail -20 .agent_logs/agent_thought_*.log
```

**Solutions**:
1. Directory missing: `mkdir -p .agent_logs; chmod 755 .agent_logs`
2. Permission denied: `chmod 755 .agent_logs; chmod 644 .agent_logs/*.log`
3. Variable not set: Verify `AGENT_LOG` variable exists

### 13.2 Commands Not Running

**Symptoms**: Terminal locks, no command logs

**Diagnosis**:
```bash
ls -lh scripts/run-command.sh
test -x scripts/run-command.sh && echo "OK" || echo "Not executable"
```

**Solutions**:
1. Not executable: `chmod +x scripts/run-command.sh`
2. Missing: `git checkout scripts/run-command.sh`
3. Still direct: Review code, ensure ALL commands use wrapper

### 13.3 Loops Not Detected

**Symptoms**: Same task repeated >5 times

**Diagnosis**:
```bash
grep -c "npm test" .agent_logs/agent_thought_*.log
grep "HEALTH_CHECK" .agent_logs/agent_thought_*.log
```

**Solutions**:
1. Health checks not running: Verify runs every 5 tasks
2. Detection broken: Review loop detection function
3. Logs wrong format: Ensure proper log categories

### 13.4 Context Full

**Symptoms**: Token usage >80%, truncation

**Diagnosis**:
```bash
grep "CONTEXT:" .agent_logs/agent_thought_*.log | tail -10
```

**Solutions**:
1. **Immediate**: End session gracefully, save state
2. **Prevention**: Track context every 5 tasks (not 10)
3. **Recovery**: Start fresh session, reads task-log.md

---

## 14. Document Relationships

### 14.1 Priority Order

**When agent needs information**:

1. **agent-docs.md** (THIS FILE) → How to do things
2. **GEMINI.md** → Why decisions were made
3. **task-log.md** → Current state
4. **README.md** → User documentation

### 14.2 When to Consult

**Before selecting task** → Read `task-log.md`

**Before implementing** → Read `GEMINI.md` (architecture context)

**During implementation** → Follow `agent-docs.md` (procedures)

**When blocked** → Check `agent-docs.md` troubleshooting

**For user info** → Reference `README.md`

### 14.3 Update Responsibilities

| Document | Updated When | Updated By | Frequency |
|----------|--------------|------------|-----------|
| `agent-docs.md` | Procedures change | Manual | As needed |
| `GEMINI.md` | Architecture decisions | Manual | Per phase |
| `task-log.md` | Every task/blocker | Agent | Continuously |
| `README.md` | Features added | Manual | Per release |

---

## APPENDICES

### A. File Locations

```
GEMINI.md                       - Project context
agent-docs.md                   - THIS FILE (rules)
task-log.md                     - Task list & status
README.md                       - User docs
logs/command-*.json             - Command execution logs
.agent_logs/agent_thought_*.log - Agent decision logs
browser_console_logs/console-*.log - Electron logs
scripts/run-command.sh          - Command wrapper
```

### B. Log Formats

**Agent Log**:
```
[ISO8601] CATEGORY: Message
```

**Command Log**:
```json
{
  "timestamp": "ISO8601",
  "command": "string",
  "output": ["lines"],
  "exit_code": 0,
  "manual_intervention_required": false
}
```

**Browser Console Log**:
```json
{
  "timestamp": "ISO8601",
  "level": "info|warning|error",
  "message": "string",
  "source": "file",
  "line": 42
}
```

### C. Health Check Script

```bash
#!/bin/bash
AGENT_LOG="$1"
TASKS_COMPLETED="$2"

echo "[$(date -Iseconds)] HEALTH_CHECK_START" >> "$AGENT_LOG"

# 1. Loops
check_for_loops "$AGENT_LOG"

# 2. Log integrity
LINES=$(wc -l < "$AGENT_LOG")
EXPECTED=$((TASKS_COMPLETED * 10))
if [ "$LINES" -lt "$EXPECTED" ]; then
    echo "[$(date -Iseconds)] WARNING: Insufficient logging" >> "$AGENT_LOG"
fi

# 3. Context
# Log context percentage

# 4. Blocked tasks
BLOCKED=$(grep -c "⚠️ Blocked" task-log.md || echo "0")
echo "[$(date -Iseconds)] STATE: $BLOCKED blocked" >> "$AGENT_LOG"

# 5. Progress
echo "[$(date -Iseconds)] STATE: $TASKS_COMPLETED completed" >> "$AGENT_LOG"

echo "[$(date -Iseconds)] HEALTH_CHECK_COMPLETE" >> "$AGENT_LOG"
```

---

## SUCCESS CRITERIA

**Agent is WORKING when**:
- ✅ Agent log exists with 10-20+ entries per task
- ✅ All commands via wrapper
- ✅ All decisions logged
- ✅ task-log.md always current
- ✅ No loops detected
- ✅ Context tracked
- ✅ Continuous progress

**Agent is BROKEN when**:
- ❌ Agent log missing or <10 entries per task
- ❌ Commands run directly (not via wrapper)
- ❌ Same question asked twice
- ❌ No progress >10 actions
- ❌ Decisions not logged

---

**Version**: 4.0 - COMPLETE  
**Status**: All gaps filled - 100% complete  
**Completeness Verification**: ✅ All 14 sections complete