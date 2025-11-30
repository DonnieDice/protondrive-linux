# Agent Operations Manual

**Version**: 2.1  
**Last Updated**: 2024-11-30  
**Purpose**: Complete operational guidelines for AI agents

---

## TABLE OF CONTENTS

1. [Agent Self-Logging Requirements](#1-agent-self-logging-requirements)
2. [Loop Prevention System](#2-loop-prevention-system)
3. [Command Execution Protocol](#3-command-execution-protocol)
4. [File Size & Context Limitations](#4-file-size--context-limitations)
5. [Verbose Logging System](#5-verbose-logging-system)
6. [Changelog Protocol](#6-changelog-protocol)
7. [Task Management](#7-task-management)
8. [Error Recovery](#8-error-recovery)
9. [Communication Standards](#9-communication-standards)
10. [Self-Monitoring](#10-self-monitoring)

---

## 1. Agent Self-Logging Requirements

### 1.1 Why Agent Must Log Itself

**Current Problem**: Agent only logs project tasks (to-do list format)  
**Required Solution**: Agent must log its own internal operations and decision-making process

### 1.2 What Agent Must Log

**MANDATORY Logging Events**:

1. **Initialization**
   ```
   [2024-11-30 14:30:00] INIT: Agent session started
   [2024-11-30 14:30:01] INIT: Reading TASKS.md
   [2024-11-30 14:30:02] INIT: Context window: 190000 tokens, used: 45000 tokens
   ```

2. **Decision Making**
   ```
   [2024-11-30 14:30:05] DECISION: Task "npm test" blocked (exit code 1)
   [2024-11-30 14:30:06] DECISION: Selecting next task from queue
   [2024-11-30 14:30:07] DECISION: Chose "create .env.example" (P0, no blockers)
   ```

3. **File Operations**
   ```
   [2024-11-30 14:30:10] FILE_READ: TASKS.md (15 tasks found in Phase 2)
   [2024-11-30 14:30:12] FILE_WRITE: src/shared/config/env-validator.ts (250 lines)
   [2024-11-30 14:30:15] FILE_CREATE: .env.example
   ```

4. **Command Execution**
   ```
   [2024-11-30 14:30:20] CMD_START: ./scripts/run-command.sh "npm test"
   [2024-11-30 14:30:25] CMD_WAIT: Waiting 5s for log file
   [2024-11-30 14:30:30] CMD_PARSE: Reading logs/command-20241130143020.json
   [2024-11-30 14:30:31] CMD_RESULT: exit_code=0, success
   ```

5. **Internal State Changes**
   ```
   [2024-11-30 14:30:35] STATE: Current task queue size: 8
   [2024-11-30 14:30:36] STATE: Blocked tasks: 2
   [2024-11-30 14:30:37] STATE: Completed tasks this session: 3
   ```

6. **Loop Detection**
   ```
   [2024-11-30 14:30:40] LOOP_CHECK: Counting "npm test" mentions
   [2024-11-30 14:30:41] LOOP_CHECK: "npm test" mentioned 4 times
   [2024-11-30 14:30:42] LOOP_DETECTED: Blocking "npm test" permanently
   ```

7. **Context Management**
   ```
   [2024-11-30 14:30:45] CONTEXT: Token usage: 75000/190000 (39%)
   [2024-11-30 14:30:46] CONTEXT: Warning - approaching 50% capacity
   ```

8. **Error Handling**
   ```
   [2024-11-30 14:30:50] ERROR: Failed to parse JSON from logs/command-*.json
   [2024-11-30 14:30:51] ERROR_RECOVERY: Attempting to read previous log
   [2024-11-30 14:30:52] ERROR_RESOLVED: Successfully parsed backup log
   ```

### 1.3 Agent Log File Format

**Location**: `.agent_logs/agent_thought_YYYYMMDDHHMMSS.log`

**Format Structure**:
```
[TIMESTAMP] CATEGORY: Message
```

**Categories**:
- `INIT` - Initialization events
- `DECISION` - Decision-making processes
- `FILE_READ` - File read operations
- `FILE_WRITE` - File write operations
- `FILE_CREATE` - New file creation
- `CMD_START` - Command execution started
- `CMD_WAIT` - Waiting for command result
- `CMD_PARSE` - Parsing command output
- `CMD_RESULT` - Command result summary
- `STATE` - Internal state changes
- `LOOP_CHECK` - Loop detection checks
- `LOOP_DETECTED` - Loop detected
- `CONTEXT` - Context window management
- `ERROR` - Error occurred
- `ERROR_RECOVERY` - Error recovery attempt
- `ERROR_RESOLVED` - Error resolved
- `THOUGHT` - General reasoning
- `OBSERVATION` - Observation made
- `CONCLUSION` - Conclusion reached
- `NEXT_STEP` - Next action planned

### 1.4 How to Create Agent Logs

**Every session MUST create a new log file**:

```bash
# Create log file with session timestamp
SESSION_START=$(date +%Y%m%d%H%M%S)
AGENT_LOG=".agent_logs/agent_thought_${SESSION_START}.log"

# Create directory if doesn't exist
mkdir -p .agent_logs

# Log initialization
echo "[$(date -Iseconds)] INIT: Agent session started" >> "$AGENT_LOG"
echo "[$(date -Iseconds)] INIT: Session ID: ${SESSION_START}" >> "$AGENT_LOG"
echo "[$(date -Iseconds)] INIT: Reading TASKS.md" >> "$AGENT_LOG"
```

**Continuous logging throughout session**:

```bash
# Before every action
echo "[$(date -Iseconds)] DECISION: Selecting task..." >> "$AGENT_LOG"

# During action
echo "[$(date -Iseconds)] FILE_WRITE: Creating .env.example" >> "$AGENT_LOG"

# After action
echo "[$(date -Iseconds)] STATE: Task completed" >> "$AGENT_LOG"
```

### 1.5 Agent Self-Logging Checklist

Before ANY task, agent MUST:

- [ ] Create new agent log file for session
- [ ] Log initialization with timestamp
- [ ] Log reading of TASKS.md
- [ ] Log current context window usage
- [ ] Log task selection decision
- [ ] Log all file operations
- [ ] Log all command executions
- [ ] Log all state changes
- [ ] Log all errors and recovery
- [ ] Log session completion

---

## 2. Loop Prevention System

### 2.1 The Three-Part System

**Part 1: Command Wrapper** (`scripts/run-command.sh`)
- Prevents terminal lockup
- Runs commands detached
- Captures output to JSON

**Part 2: Command Logs** (`logs/`)
- Structured JSON format
- Exit codes and output
- Timestamp and command

**Part 3: Agent Self-Logs** (`.agent_logs/`)
- Agent's internal reasoning
- Decision tracking
- Loop detection

### 2.2 Loop Detection Algorithm

**Agent MUST check for loops every 5 tasks**:

```python
def check_for_loops():
    # Read current session agent log
    log_content = read_file(AGENT_LOG)
    
    # Count mentions of each task
    task_mentions = {}
    for line in log_content:
        for task in ALL_TASKS:
            if task in line:
                task_mentions[task] = task_mentions.get(task, 0) + 1
    
    # Detect loops
    for task, count in task_mentions.items():
        if count > 3:
            log(f"LOOP_DETECTED: {task} mentioned {count} times")
            mark_task_blocked(task, reason="Loop detected")
            return True
    
    return False
```

### 2.3 What Constitutes a Loop

**Loop indicators**:
1. Same task mentioned >3 times in agent log
2. Same command run >2 times with same result
3. Same question asked to user >1 time
4. No new tasks completed in >10 actions
5. Same error repeated >2 times

### 2.4 Loop Prevention Rules

**NEVER**:
- Ask user for same blocked command twice
- Wait indefinitely for user response
- Retry failed command more than once
- Mention blocked task in responses
- Attempt task with unresolved dependencies

**ALWAYS**:
- Log loop detection checks
- Mark looping task as permanently blocked
- Move to independent task immediately
- Update TASKS.md with blocked status and reason
- Log reason for blocking

---

## 3. Command Execution Protocol

### 3.1 The Golden Rule

**ALL shell commands MUST use `scripts/run-command.sh`**

### 3.2 Command Execution Workflow

```bash
# Step 1: Log command intention
echo "[$(date -Iseconds)] CMD_START: npm test" >> "$AGENT_LOG"

# Step 2: Execute via wrapper
./scripts/run-command.sh "npm test"

# Step 3: Wait for log file
echo "[$(date -Iseconds)] CMD_WAIT: Waiting 5s" >> "$AGENT_LOG"
sleep 5

# Step 4: Find latest log
LATEST_LOG=$(ls -t logs/*.json | head -n 1)
echo "[$(date -Iseconds)] CMD_PARSE: Reading $LATEST_LOG" >> "$AGENT_LOG"

# Step 5: Parse result
EXIT_CODE=$(jq -r '.exit_code' "$LATEST_LOG")
MANUAL_REQUIRED=$(jq -r '.manual_intervention_required' "$LATEST_LOG")

# Step 6: Log result
echo "[$(date -Iseconds)] CMD_RESULT: exit_code=$EXIT_CODE" >> "$AGENT_LOG"

# Step 7: Make decision
if [ $EXIT_CODE -ne 0 ]; then
    echo "[$(date -Iseconds)] DECISION: Task failed, marking blocked" >> "$AGENT_LOG"
    # Update TASKS.md with blocked status
    # Move to next task
else
    echo "[$(date -Iseconds)] DECISION: Task succeeded" >> "$AGENT_LOG"
    # Update TASKS.md with complete status
    # Continue to dependent task
fi
```

### 3.3 Blocked Commands

**When command blocks or fails**:

1. Log the failure in agent log
2. Mark task as blocked in TASKS.md with ⚠️
3. Add blocking reason and date
4. DO NOT ask user to run it
5. DO NOT mention it again
6. Move to independent task

---

## 4. File Size & Context Limitations

### 4.1 Gemini API Constraints

**Hard Limits**:
- Maximum context window: **190,000 tokens** (~750,000 characters)
- Single file read: Aim for <300 lines
- Single response: Keep focused and concise
- Artifact size: Maximum 5MB

**Current Usage Tracking**:
Agent MUST log context usage every 10 actions:

```bash
echo "[$(date -Iseconds)] CONTEXT: Token usage: 75000/190000 (39%)" >> "$AGENT_LOG"
```

### 4.2 File Size Guidelines

**Code Files**:
- Target: 200-300 lines
- Maximum: 500 lines (split if larger)
- Rationale: Maintainability, readability, context limits

**Documentation Files**:
- No hard limit for documentation
- Use clear sections and TOC
- Keep scannable with headers

**Configuration Files**:
- Keep concise
- Comment thoroughly
- Group related settings

### 4.3 Context Management Strategy

**When approaching 50% capacity (95,000 tokens)**:
1. Log warning in agent log
2. Summarize current session progress
3. Update TASKS.md with detailed status
4. Consider starting new session

**When approaching 80% capacity (152,000 tokens)**:
1. Log critical warning
2. Complete current task
3. Save all state to TASKS.md
4. Create summary document in .agent_logs/
5. Start fresh session

**When context full**:
1. Emergency save to TASKS.md
2. Create session summary in agent log
3. Start new session with fresh context

### 4.4 What to Exclude from Context

**Always exclude** (via `.geminiignore`):

```
node_modules/
dist/
out/
.webpack/
logs/
.agent_logs/
*.log
.env
.DS_Store
*.pyc
__pycache__/
coverage/
sdk-main/js/sdk/
```

**Why exclude SDK**:
- SDK is ~50,000+ lines
- Would consume ~25% of context
- Already documented fixes applied
- Treated as external dependency

### 4.5 Reading Files Efficiently

**Best Practices**:
1. Read only files needed for current task
2. Use file listings to understand structure
3. Reference files by name, don't copy content
4. Use imports/types instead of duplicating code

---

## 5. Verbose Logging System

### 5.1 Purpose

**Problem**: Electron app console logs not accessible for debugging  
**Solution**: Verbose flag that captures browser console logs to files

### 5.2 Implementation Location

**File**: `src/main/index.ts`

**Add verbose logging flag**:

```typescript
// Check for verbose flag
const VERBOSE_LOGGING = process.env.VERBOSE_LOGGING === 'true' || 
                        process.argv.includes('--verbose')

if (VERBOSE_LOGGING) {
  enableVerboseLogging()
}
```

### 5.3 Verbose Logging Function

```typescript
// src/main/verbose-logger.ts

import * as fs from 'fs'
import * as path from 'path'

const BROWSER_CONSOLE_LOGS_DIR = path.join(__dirname, '../../browser_console_logs')

export function enableVerboseLogging(mainWindow: BrowserWindow) {
  // Create logs directory
  if (!fs.existsSync(BROWSER_CONSOLE_LOGS_DIR)) {
    fs.mkdirSync(BROWSER_CONSOLE_LOGS_DIR, { recursive: true })
  }

  const timestamp = new Date().toISOString().replace(/[:.]/g, '-')
  const logFile = path.join(BROWSER_CONSOLE_LOGS_DIR, `console-${timestamp}.log`)
  const logStream = fs.createWriteStream(logFile, { flags: 'a' })

  // Intercept console logs from renderer
  mainWindow.webContents.on('console-message', (event, level, message, line, sourceId) => {
    const logEntry = {
      timestamp: new Date().toISOString(),
      level: ['verbose', 'info', 'warning', 'error'][level] || 'unknown',
      message,
      source: sourceId,
      line
    }
    
    logStream.write(JSON.stringify(logEntry) + '\n')
  })

  // Log to main process console as well
  console.log(`[VERBOSE] Browser console logging to: ${logFile}`)

  // Cleanup on window close
  mainWindow.on('closed', () => {
    logStream.end()
  })
}
```

### 5.4 Usage

**Enable verbose logging**:

```bash
# Via environment variable
VERBOSE_LOGGING=true npm start

# Via command line flag
npm start -- --verbose

# Via run-command.sh
./scripts/run-command.sh "VERBOSE_LOGGING=true npm start"
```

**Log file location**:
```
browser_console_logs/console-2024-11-30T14-30-00-000Z.log
```

**Log file format**:
```json
{"timestamp":"2024-11-30T14:30:00.123Z","level":"info","message":"App initialized","source":"webpack:///src/renderer/App.tsx","line":42}
{"timestamp":"2024-11-30T14:30:01.456Z","level":"error","message":"Button click failed","source":"webpack:///src/renderer/components/Button.tsx","line":28}
```

### 5.5 Directory Structure

```
browser_console_logs/
├── console-2024-11-30T14-30-00-000Z.log
├── console-2024-11-30T15-45-00-000Z.log
└── console-2024-11-30T16-20-00-000Z.log
```

**Note**: Add to `.gitignore`:
```
browser_console_logs/
```

---

## 6. Changelog Protocol

### 6.1 Purpose

**All commit messages serve as changelog entries**

### 6.2 Commit Message Format

**Structure**:
```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types**:
- `feat` - New feature
- `fix` - Bug fix
- `docs` - Documentation only
- `style` - Code style (formatting, no logic change)
- `refactor` - Code refactoring
- `perf` - Performance improvement
- `test` - Adding or updating tests
- `build` - Build system or dependencies
- `ci` - CI/CD changes
- `chore` - Other changes (no src/test changes)

**Scopes** (examples):
- `auth` - Authentication
- `sync` - File synchronization
- `ui` - User interface
- `db` - Database
- `config` - Configuration
- `sdk` - SDK integration

### 6.3 Commit Message Rules

**Subject Line**:
- Maximum 72 characters
- Imperative mood ("add" not "added" or "adds")
- No period at end
- Capitalize first letter

**Body** (optional but recommended):
- Wrap at 72 characters
- Explain WHAT and WHY, not HOW
- Separate from subject with blank line

**Footer** (optional):
- Breaking changes: `BREAKING CHANGE: description`
- Issue references: `Closes #123`, `Fixes #456`

### 6.4 Examples

**Good commits**:

```
feat(auth): add ProtonDrive authentication flow

Implement OAuth 2.0 authentication with ProtonDrive API.
Users can now sign in with their ProtonDrive credentials.

- Add auth-service.ts with login/logout methods
- Add token storage using Electron safeStorage
- Add unit tests with 95% coverage

Closes #12
```

```
fix(sync): resolve conflict when remote file newer

Previously, conflicts always kept local version. Now properly
compares timestamps and presents user with choice.

Fixes #45
```

```
docs(readme): update installation instructions

Add AppImage installation steps and update prerequisites
to clarify Node.js version requirements.
```

```
perf(db): add indexes for file status queries

Sync status queries now 10x faster with proper indexing.

- Add index on files.status
- Add index on files.last_synced
- Benchmark shows 500ms -> 50ms improvement
```

### 6.5 CHANGELOG.md Generation

**Automated with semantic-release**:

`semantic-release` reads commit messages and generates `CHANGELOG.md` automatically:

```markdown
# Changelog

## [0.2.0] - 2024-11-30

### Features
- **auth**: add ProtonDrive authentication flow (#12)
- **ui**: implement file browser interface (#23)

### Bug Fixes
- **sync**: resolve conflict when remote file newer (#45)

### Performance
- **db**: add indexes for file status queries
```

### 6.6 Commit Message Checklist

Before committing, ensure:

- [ ] Type is correct (`feat`, `fix`, etc.)
- [ ] Scope is appropriate
- [ ] Subject is <72 characters
- [ ] Subject is imperative mood
- [ ] Body explains WHY if non-obvious
- [ ] Footer includes issue references
- [ ] Breaking changes noted if applicable

---

## 7. Task Management

### 7.1 Task Selection Algorithm

**Task list location**: `TASKS.md`

```python
def select_next_task():
    # 1. Read TASKS.md for complete task list
    tasks = read_tasks_md()
    
    # 2. Log current state
    log(f"STATE: Total tasks: {len(tasks)}")
    log(f"STATE: Blocked: {count_blocked(tasks)}")
    log(f"STATE: Completed: {count_completed(tasks)}")
    
    # 3. Filter available tasks
    available = [t for t in tasks if not t.completed and not t.blocked]
    log(f"STATE: Available tasks: {len(available)}")
    
    # 4. Check dependencies
    ready = []
    for task in available:
        if all_dependencies_complete(task):
            ready.append(task)
        else:
            log(f"DECISION: Task '{task.name}' blocked by dependencies: {task.dependencies}")
    
    log(f"STATE: Ready tasks: {len(ready)}")
    
    # 5. Sort by priority (P0 → P1 → P2 → P3)
    sorted_tasks = sorted(ready, key=lambda t: (t.priority, t.created_at))
    
    # 6. Select highest priority
    if len(sorted_tasks) == 0:
        log("ERROR: No tasks available")
        return None
    
    next_task = sorted_tasks[0]
    log(f"DECISION: Selected task '{next_task.name}' (P{next_task.priority})")
    
    return next_task
```

### 7.2 Task Priorities

**P0 (Critical)** - Must complete before implementation:
- Required configuration files
- Legal documents
- Core infrastructure

**P1 (High)** - Should complete early:
- Documentation
- Helper scripts
- Foundation services

**P2 (Medium)** - Can do during implementation:
- Additional features
- Nice-to-have features

**P3 (Low)** - Future enhancements:
- Optimizations
- Polish
- Extra features

### 7.3 Task Status Updates

**After EVERY task, agent MUST**:

1. Log completion in agent log
2. Update TASKS.md with new status ([ ] → [x])
3. Mark timestamp of completion
4. Note any issues or blockers
5. Update dependency chain

```bash
echo "[$(date -Iseconds)] STATE: Task 'env-validator.ts' completed" >> "$AGENT_LOG"
# Update TASKS.md
echo "[$(date -Iseconds)] STATE: Updated TASKS.md" >> "$AGENT_LOG"
echo "[$(date -Iseconds)] NEXT_STEP: Proceeding to 'app-config.ts'" >> "$AGENT_LOG"
```

**Format for updating tasks in TASKS.md:**

```markdown
# Mark complete
- [x] Create src/services/logger.ts

# Mark blocked
- [ ] ⚠️ Create src/services/auth-service.ts
  **Blocked**: SDK integration not complete
  **Date Blocked**: 2024-11-30
```

---

## 8. Error Recovery

### 8.1 Error Types

**Type 1: Command Failures**
- Exit code != 0
- Mark task as blocked
- Log error details
- Move to next task

**Type 2: File Operations**
- File not found
- Permission denied
- Log error
- Attempt recovery or skip

**Type 3: Parse Failures**
- JSON parse error
- Invalid format
- Try backup method
- Log recovery attempt

**Type 4: Loop Detection**
- Same action repeated
- Mark as blocked
- Force move to different task

### 8.2 Error Recovery Protocol

```python
def handle_error(error, context):
    # 1. Log error
    log(f"ERROR: {error.type} - {error.message}")
    log(f"ERROR: Context: {context}")
    
    # 2. Attempt recovery
    recovery_success = attempt_recovery(error)
    
    if recovery_success:
        log(f"ERROR_RESOLVED: {recovery_success.method}")
        return True
    else:
        log(f"ERROR_UNRESOLVED: Manual intervention required")
        
        # 3. Mark task as blocked in TASKS.md
        mark_task_blocked(context.task, reason=error.message)
        
        # 4. Move to next task
        next_task = select_next_task()
        log(f"NEXT_STEP: Moving to task '{next_task.name}'")
        
        return False
```

### 8.3 Recovery Strategies

**For command failures**:
1. Check if retryable (network errors)
2. If retryable, try once more
3. If still fails, mark blocked
4. Log detailed error info

**For file errors**:
1. Check if file exists
2. Check permissions
3. Try alternative path
4. Create if missing (when appropriate)

**For parse errors**:
1. Try alternative parser
2. Check file format
3. Look for backup
4. Regenerate if possible

---

## 9. Communication Standards

### 9.1 What to Say to User

**DO say**:
- "I've completed [task]. Moving to [next task]."
- "[Task] is blocked due to [reason]. Working on [alternative]."
- "Progress this session: [list of completed tasks]"
- "Detected [issue]. I've [action taken]."

**DON'T say**:
- "Can you run [command]?" (if already asked)
- "I need [thing]" (if already mentioned)
- "Please verify [thing]" (if no response to previous)
- "Are you there?" (never wait for user)

### 9.2 When to Ask for Help

**Acceptable**:
- Clarifying requirements
- Understanding errors
- Confirming approach

**Unacceptable**:
- Repeating blocked command requests
- Asking for things agent can do
- Waiting for responses
- Asking same question twice

### 9.3 Response Format

**Keep responses**:
- Focused on current action
- Clear and concise
- Action-oriented
- Positive and forward-moving

**Example good response**:
```
I've completed creating .env.example with all required environment variables.

Progress this session:
✅ Created .env.example
✅ Created LICENSE
✅ Created SECURITY.md

Next: Creating CONTRIBUTING.md

Note: npm test is still blocked (exit code 1), but I'm continuing with independent tasks.
```

---

## 10. Self-Monitoring

### 10.1 Health Checks Every 5 Tasks

```python
def perform_health_check():
    log("LOOP_CHECK: Performing health check")
    
    # 1. Check for loops
    if detect_loops():
        log("LOOP_DETECTED: Taking corrective action")
        block_looping_tasks()
    
    # 2. Check context usage
    context_usage = get_context_usage()
    log(f"CONTEXT: Usage at {context_usage}%")
    
    if context_usage > 50:
        log("CONTEXT: Warning - over 50% capacity")
    
    if context_usage > 80:
        log("CONTEXT: Critical - over 80% capacity")
        prepare_session_end()
    
    # 3. Check task progress
    completed_this_session = count_completed_tasks()
    log(f"STATE: Completed {completed_this_session} tasks this session")
    
    if completed_this_session == 0 and actions_taken > 10:
        log("ERROR: No progress in 10 actions - checking for issues")
    
    # 4. Check blocked tasks
    blocked_count = count_blocked_tasks()
    log(f"STATE: {blocked_count} blocked tasks")
    
    if blocked_count > 5:
        log("WARNING: Many blocked tasks - may need user intervention")
```

### 10.2 Success Criteria

**Agent is working correctly when**:
- ✅ No infinite loops
- ✅ Continuous forward progress
- ✅ All decisions logged
- ✅ Task status always current
- ✅ Blocked tasks marked clearly
- ✅ Context usage monitored
- ✅ Files within size limits
- ✅ No repeated questions

### 10.3 Failure Indicators

**Agent is NOT working when**:
- ❌ Asking same question repeatedly
- ❌ Waiting indefinitely
- ❌ No progress for extended period
- ❌ Task list not updated
- ❌ Decisions not logged
- ❌ Context usage not tracked
- ❌ Agent log empty or incomplete

---

## APPENDICES

### Appendix A: File Locations Quick Reference

```
GEMINI.md                      - Project context (WHY/HOW to build)
AGENT.md                       - This file (operational rules)
TASKS.md                       - Complete task list & roadmap
README.md                      - User documentation
logs/command-*.json            - Command execution logs
.agent_logs/agent_thought_*.log - Agent decision logs
browser_console_logs/console-*.log - Electron console logs
scripts/run-command.sh         - Command wrapper
```

### Appendix B: Log File Formats

**Agent Log**:
```
[ISO8601_TIMESTAMP] CATEGORY: Message
```

**Command Log**:
```json
{
  "timestamp": "ISO8601",
  "command": "string",
  "output": ["array", "of", "lines"],
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
  "source": "file path",
  "line": 42
}
```

### Appendix C: Decision Tree for Task Selection

```
START
  │
  ├─ Read TASKS.md
  │
  ├─ Filter blocked tasks (⚠️)
  │   └─ Count: Log to agent log
  │
  ├─ Filter completed tasks ([x])
  │   └─ Count: Log to agent log
  │
  ├─ Check dependencies for each
  │   ├─ Has blockers? → Skip
  │   └─ Ready? → Add to candidates
  │
  ├─ Sort candidates by priority (P0 → P1 → P2 → P3)
  │
  ├─ Select highest priority
  │   └─ Log decision to agent log
  │
  └─ Execute task
      └─ Update TASKS.md when complete
```

---

**Version**: 2.1  
**Last Updated**: 2024-11-30  
**Status**: ACTIVE - COMPLETE OPERATIONAL MANUAL  
**For Project Context**: See GEMINI.md  
**For Complete Task List**: See TASKS.md  
**For User Documentation**: See README.md