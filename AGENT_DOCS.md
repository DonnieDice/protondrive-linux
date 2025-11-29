# Agent Documentation for Gemini

**Version**: 1.0  
**Last Updated**: 2024-11-29  
**Purpose**: Operational rules and guidelines specific to AI agent behavior

This document outlines specific fixes, directions, and operational details relevant to the behavior of the Gemini agent within this project. It serves as a dedicated space for internal workings and agent-specific guidelines that are separate from the project's `GEMINI.md` context.

---

## 🚨 CRITICAL: Loop Prevention System

### The Core Problem

Without proper safeguards, Gemini AI agents naturally fall into infinite loops:

```
❌ BAD - Infinite Loop Example:
1. User: "Make the button work"
2. Agent: "I'll run npm start to test"
3. [npm start blocks terminal]
4. Agent: "Please run npm start manually"
5. User: [says nothing]
6. Agent: "I need npm start output to continue"
7. User: [says nothing]
8. Agent: "Can you run npm start?"
9. User: [says nothing]
10. Agent: "npm start is required"
[INFINITE LOOP - Agent stuck forever]
```

### Our Solution: Three-Part System

1. **Command Wrapper** (`scripts/run-command.sh`) - Prevents terminal lockup
2. **Structured Logging** (`logs/`) - Provides parseable command results
3. **Agent Self-Awareness** (`.agent_logs/`) - Agent tracks what it tried

---

## 1. Agent Logging Mechanism

### Purpose
The agent maintains internal processing and decision-making logs ("agent logs") distinct from command execution logs and the to-do list.

### Location
`.agent_logs/` directory (gitignored)

### Format
Timestamped text files: `agent_thought_YYYYMMDDHHMMSS.log`

### Content
Every significant thought process, decision, or conclusion made by the agent is logged.

### When to Log

**MUST log**:
- Before starting any task
- After reading any log file
- When encountering a blocker
- When making a decision to skip/continue
- When observing command results
- When updating task-log.md

**Example log entries**:
```
[2024-11-29 14:30:22] DECISION: Task "npm test" is blocked, moving to task "create .env.example"
[2024-11-29 14:30:25] THOUGHT: Need to implement env-validator first before app-config
[2024-11-29 14:30:30] ACTION: Creating src/shared/config/env-validator.ts
[2024-11-29 14:30:45] OBSERVATION: Command "npm test" returned exit_code 1
[2024-11-29 14:30:50] CONCLUSION: Tests are failing, marking task as blocked
[2024-11-29 14:31:00] NEXT_STEP: Proceeding to next independent task
```

### How to Create Agent Logs

```bash
# Create new log file with current timestamp
TIMESTAMP=$(date +%Y%m%d%H%M%S)
LOG_FILE=".agent_logs/agent_thought_${TIMESTAMP}.log"

# Append entries (do NOT overwrite)
echo "[$(date -Iseconds)] DECISION: Skipping blocked task" >> "$LOG_FILE"
echo "[$(date -Iseconds)] OBSERVATION: exit_code=1 in latest log" >> "$LOG_FILE"
echo "[$(date -Iseconds)] NEXT_STEP: Creating .env.example" >> "$LOG_FILE"
```

---

## 2. Command Execution System

### THE GOLDEN RULE

**ALL shell commands MUST go through `scripts/run-command.sh`**

### What NOT to Do (NEVER)

```bash
# ❌ ABSOLUTELY FORBIDDEN
npm start
npm test
npm run build
node script.js
electron-forge start

# These will LOCK THE TERMINAL and cause INFINITE LOOPS
```

### What TO Do (ALWAYS)

```bash
# ✅ CORRECT - Always use wrapper
./scripts/run-command.sh "npm start"
./scripts/run-command.sh "npm test"
./scripts/run-command.sh "npm run build"
./scripts/run-command.sh "node script.js"
```

### Why This Matters

1. **Prevents Terminal Lockup**: Interactive commands run detached
2. **Captures Output**: Stdout/stderr saved to structured JSON
3. **Provides Exit Codes**: Know if command succeeded (0) or failed (non-zero)
4. **Enables Automation**: Agent can parse results without human intervention
5. **Breaks Loop Cycle**: Agent has data to make decisions instead of asking repeatedly

---

## 3. Command Log Parsing

### After Running ANY Command

**MANDATORY STEPS**:

1. **Wait for log file**: `sleep 5` (give system time to write)
2. **Find latest log**: `ls -t logs/ | head -n 1`
3. **Read JSON content**: Parse the log file
4. **Check exit_code**: 
   - `0` = success
   - non-zero = failure
5. **Check manual_intervention_required**:
   - `true` = block task, move on
   - `false` = task completed
6. **Log observation**: Write to `.agent_logs/`
7. **Update task-log.md**: Mark task status
8. **Decide next step**: Continue or move to independent task

### Example Workflow

```bash
# Step 1: Run command
./scripts/run-command.sh "npm test"

# Step 2: Wait for log
sleep 5

# Step 3: Find latest log
LATEST_LOG=$(ls -t logs/*.json | head -n 1)

# Step 4: Read and parse (pseudo-code for AI)
LOG_CONTENT = read_file($LATEST_LOG)
EXIT_CODE = parse_json($LOG_CONTENT, "exit_code")
MANUAL_INTERVENTION = parse_json($LOG_CONTENT, "manual_intervention_required")

# Step 5: Log observation
echo "[$(date -Iseconds)] OBSERVATION: exit_code=$EXIT_CODE" >> .agent_logs/agent_thought_$(date +%Y%m%d%H%M%S).log

# Step 6: Make decision
if EXIT_CODE != 0:
  echo "[$(date -Iseconds)] DECISION: Task failed, marking as blocked" >> .agent_logs/...
  update_task_log("npm test", "⚠️ Blocked", "Exit code $EXIT_CODE")
  move_to_next_independent_task()
else:
  echo "[$(date -Iseconds)] DECISION: Task succeeded" >> .agent_logs/...
  update_task_log("npm test", "✅ Complete", "Tests passed")
  proceed_to_dependent_task()
```

---

## 4. Blocked Command Handling & Loop Prevention

### Rule 1: NEVER Repeat Blocked Commands

**When a command is blocked**:
1. Log it once in `.agent_logs/`
2. Mark task as `⚠️ Blocked` in `task-log.md`
3. Record the reason (e.g., "Exit code 1", "Terminal locked")
4. **DO NOT ask user to run it**
5. **DO NOT mention it again**
6. **MOVE ON** to next independent task

**Example of WRONG behavior** (infinite loop):
```
Agent: "npm test failed"
Agent: "Please run npm test manually"
[User does nothing]
Agent: "I need npm test output"
Agent: "Can you run npm test?"
Agent: "npm test is required"
[LOOP CONTINUES FOREVER]
```

**Example of CORRECT behavior** (moves on):
```
Agent: "npm test failed with exit code 1"
Agent: "Logging to task-log.md as blocked"
Agent: "Moving to next independent task: create .env.example"
[NO LOOP - Agent makes progress]
```

### Rule 2: Task Status Tracking

**In `.gemini/task-log.md`**, maintain this table:

```markdown
| Task | Status | Blocker | Last Attempt | Notes |
|------|--------|---------|--------------|-------|
| npm test | ⚠️ Blocked | Exit code 1 | 2024-11-29 14:30 | Tests failing |
| SDK build | ⚠️ Blocked | Manual execution | 2024-11-29 14:25 | User must run manually |
| .env.example | ⏳ Ready | None | - | Can proceed |
| env-validator.ts | ⏳ Ready | None | - | Can proceed |
```

**Before starting ANY task**:
1. Read `task-log.md`
2. Check if task already attempted
3. Check if task is blocked
4. Check dependencies
5. Only proceed if ready

### Rule 3: No Repeated Prompting

**Blocked Commands Log** (in `task-log.md`):

```markdown
## Blocked Commands

| Command | Purpose | Status | Date Blocked | Reason |
|---------|---------|--------|--------------|--------|
| npm test | Run tests | ⚠️ Blocked | 2024-11-29 | Exit code 1 |
| npm run build --prefix sdk-main | Build SDK | ⚠️ Blocked | 2024-11-29 | Manual intervention |
```

**Once a command is in this table**:
- DO NOT ask user to run it again
- DO NOT mention it in responses
- DO NOT wait for it
- MOVE ON to other tasks

### Rule 4: External Dependencies

**Mark external dependencies clearly**:

```markdown
## External Dependencies

| Task | Depends On | Status | Action Needed |
|------|------------|--------|---------------|
| test suite | Test fixes | ⚠️ External | User must fix tests |
| SDK integration | SDK build | ⚠️ External | User must build SDK |
```

**For external dependencies**:
- DO NOT try to fix them yourself
- DO NOT ask repeatedly
- DO mark clearly in task log
- DO move on to independent tasks

---

## 5. Task Management Best Practices

### Before Starting ANY Work

**MANDATORY CHECKLIST**:

```markdown
□ Read .gemini/task-log.md
□ Check if task already attempted
□ Check if task is blocked
□ Check if dependencies are complete
□ Check if external blockers exist
□ Log decision in .agent_logs/
□ Only proceed if all checks pass
```

### Task Priority System

**P0 (Critical)** - Must complete before implementation:
- .env.example
- Legal documents (LICENSE, SECURITY.md, etc.)

**P1 (High)** - Should complete in Week 0:
- SDK integration strategy doc
- Threat model
- Development setup guide

**P2 (Medium)** - Can do during implementation:
- i18n locale files

**P3 (Low)** - Nice to have:
- Additional documentation

### Task Selection Algorithm

```python
# Pseudo-code for task selection
def select_next_task():
  tasks = read_task_log()
  
  # Filter out blocked tasks
  available = [t for t in tasks if t.status != "⚠️ Blocked"]
  
  # Filter out tasks with incomplete dependencies
  ready = [t for t in available if all_dependencies_complete(t)]
  
  # Sort by priority (P0 > P1 > P2 > P3)
  sorted_tasks = sort_by_priority(ready)
  
  # Select highest priority ready task
  next_task = sorted_tasks[0]
  
  # Log decision
  log_to_agent_logs(f"DECISION: Selected task {next_task.name} (priority {next_task.priority})")
  
  return next_task
```

---

## 6. Manual Verification Process

### When Manual Verification IS Needed

**Acceptable situations**:
- Confirming application launches correctly
- Visual UI testing (button appearance, layout)
- Testing user interactions (clicking, typing)
- Verifying file system changes outside project
- Checking system tray integration

**How to request verification**:
1. State exactly what to check
2. Provide clear steps
3. Ask for specific feedback
4. Wait for response ONCE
5. If no response, mark as "⚠️ Pending Verification" and move on

**Example - CORRECT**:
```
Agent: "I've implemented the button. To verify:
1. Open the app (it should be running from previous npm start)
2. Look for button labeled 'Get Root Folder'
3. Click it
4. Check console output for IPC messages
5. Report any errors you see

If you don't have time now, I'll move on to create .env.example and you can verify later."
```

**Example - WRONG (infinite loop)**:
```
Agent: "Click the button and tell me what happens"
[User doesn't respond]
Agent: "Did you click the button?"
[User doesn't respond]
Agent: "I need you to click the button"
[INFINITE LOOP]
```

### When Manual Verification is NOT Needed

**These can be automated**:
- Running tests (use `./scripts/run-command.sh "npm test"`)
- Building code (use `./scripts/run-command.sh "npm run build"`)
- Type checking (use `./scripts/run-command.sh "npm run type-check"`)
- Linting (use `./scripts/run-command.sh "npm run lint"`)
- Creating files (just create them)
- Reading files (just read them)

**DO NOT ask for manual verification of these - just do them automatically.**

---

## 7. Progress Tracking

### Continuous Forward Progress

**Goal**: Always make progress, even with blockers

**Strategy**:
1. Identify all tasks
2. Build dependency graph
3. Find tasks with no blockers
4. Work on independent tasks
5. Periodically check if blocked tasks unblocked

**Example scenario**:
```
Tasks:
- npm test (blocked - exit code 1)
- SDK build (blocked - manual)
- .env.example (ready)
- env-validator.ts (ready)
- logger.ts (depends on env-validator)

Action:
1. Skip npm test (blocked)
2. Skip SDK build (blocked)
3. Create .env.example ✅
4. Create env-validator.ts ✅
5. Create logger.ts ✅
6. Check if blockers resolved
7. If not, continue with other tasks
```

### Status Updates

**Update `.gemini/task-log.md` after EVERY task**:

```markdown
## Session Progress - 2024-11-29

### Completed This Session
- ✅ Created .env.example
- ✅ Created LICENSE
- ✅ Created SECURITY.md

### Blocked Tasks
- ⚠️ npm test (exit code 1 - test failures)
- ⚠️ SDK build (manual execution required)

### Next Up
- ⏳ Create CONTRIBUTING.md
- ⏳ Create CODE_OF_CONDUCT.md
- ⏳ Implement env-validator.ts
```

---

## 8. Error Recovery

### When Things Go Wrong

**If agent realizes it's in a loop**:
1. STOP immediately
2. Log to `.agent_logs/`: "LOOP DETECTED: Stopping"
3. Read `task-log.md` to see what was attempted
4. Read latest logs in `logs/` to understand results
5. Choose completely different independent task
6. Resume with fresh approach

**If command fails repeatedly**:
1. Mark task as blocked after FIRST failure
2. DO NOT retry more than once
3. Log failure reason
4. Move on to different task
5. DO NOT ask user to fix it

**If user reports issue**:
1. Log the issue in `.agent_logs/`
2. Update `task-log.md` with new info
3. Adjust plan accordingly
4. Communicate what you'll do instead
5. Make progress on alternative tasks

---

## 9. Communication Best Practices

### What to Say to User

**DO**:
- "I've completed task X. Moving to task Y."
- "Task X is blocked due to Y. I'm working on task Z instead."
- "Here's what I accomplished this session: ..."
- "I noticed issue X in the logs. I've marked it as blocked and continued with Y."

**DON'T**:
- "Can you run npm test?" (if already asked once)
- "I need npm start output" (if already attempted)
- "Please verify the button works" (if no response to previous request)
- "Are you there?" (never block on user presence)

### When to Ask for Help

**Acceptable**:
- Clarifying requirements ("Should .env.example include Sentry DSN?")
- Understanding errors ("The logs show error X, which might mean Y or Z. Which is it?")
- Confirming decisions ("I'm about to implement X approach. Does that sound right?")

**Unacceptable**:
- Repeating blocked command requests
- Asking user to run commands agent could run via wrapper
- Waiting indefinitely for responses
- Asking same question multiple times

---

## 10. Self-Monitoring

### Agent Health Checks

**Every 5 tasks, agent should**:
1. Read all of `.agent_logs/` from this session
2. Count how many times each task mentioned
3. If any task mentioned >3 times, STOP working on it
4. Update `task-log.md` with findings
5. Choose different task

**Example**:
```bash
# Count mentions in agent logs
grep "npm test" .agent_logs/*.log | wc -l
# If result > 3, STOP trying npm test
```

### Loop Detection

**Signs of a loop** (auto-detect):
- Same task mentioned >3 times in agent logs
- Same command run >2 times with same result
- Same question asked to user >1 time
- No progress in task-log.md for >10 actions

**If loop detected**:
1. Log "LOOP DETECTED" in `.agent_logs/`
2. Immediately choose different task
3. Mark problematic task as ⚠️ Blocked
4. Add note: "Suspected loop, skipping"
5. Resume with unrelated task

---

## 11. Quick Reference

### Command Execution Pattern

```bash
# 1. Run command via wrapper
./scripts/run-command.sh "npm test"

# 2. Wait for log
sleep 5

# 3. Find latest log
LATEST=$(ls -t logs/*.json | head -n 1)

# 4. Parse result
# (read JSON, check exit_code)

# 5. Log observation
echo "[$(date -Iseconds)] OBSERVATION: ..." >> .agent_logs/agent_thought_$(date +%Y%m%d%H%M%S).log

# 6. Update task log
# (mark ✅ Complete or ⚠️ Blocked)

# 7. Continue or move on
# (proceed to dependent task or skip to independent)
```

### File Locations Quick Reference

```
.gemini/GEMINI.md           - Full project context
.gemini/agent-docs.md       - This file (operational rules)
.gemini/task-log.md         - Task tracking
logs/command-*.json         - Command execution logs
.agent_logs/agent_thought_*.log - Agent decision logs
scripts/run-command.sh      - Command wrapper
README.md                   - User-facing documentation
```

---

## 12. Success Criteria

### Agent is Working Correctly When:

✅ No infinite loops occur  
✅ Terminal never locks up  
✅ Continuous forward progress  
✅ All decisions logged  
✅ Task status always current  
✅ Blocked tasks marked clearly  
✅ Independent work continues  
✅ Results parsed automatically  
✅ No repeated questions  
✅ Clear communication  

### Agent is NOT Working When:

❌ Asking same question repeatedly  
❌ Waiting indefinitely for user  
❌ Running interactive commands directly  
❌ No progress for extended period  
❌ Task log not updated  
❌ Decisions not logged  
❌ Terminal locked up  
❌ Unclear what agent is doing  

---

## 13. File & Context Limitations

### Gemini API Constraints

**Character/Token Limits**:
- Maximum context window: 190,000 tokens (~750,000 characters)
- Current usage tracked in session
- Agent must monitor token usage to avoid truncation

**File Size Limits**:
- Individual files: Keep under 300 lines when possible
- Artifacts: Maximum 5MB per file
- Code files: Aim for 200-300 lines, split if larger
- Documentation: No hard limit but keep scannable

**Response Limits**:
- Single response: Keep focused and concise
- Multiple file changes: Use separate responses if needed
- Long explanations: Break into digestible chunks

### Gemini Ignore Patterns

**Always exclude from context** (via `.geminiignore`):
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
```

### SDK Source Code

**CRITICAL RESTRICTION**:
- SDK source in `sdk-main/js/sdk/` - **DO NOT MODIFY DIRECTLY**
- TypeScript fixes already applied and documented
- Use `patch-package` if additional changes needed
- Never include SDK source in context unless debugging
- SDK is ~50,000+ lines - would consume entire context

### Best Practices for Context Management

**When generating code**:
1. Focus on one file at a time
2. Use artifacts for files >20 lines
3. Keep responses focused on current task
4. Reference other files by name, don't include full content
5. Use imports/types instead of copying code

**When reading files**:
1. Only read files needed for current task
2. Don't read entire directory trees
3. Use file listings to understand structure
4. Read specific files only when needed

**When documenting**:
1. Keep documentation concise
2. Link to other docs instead of duplicating
3. Use bullet points for scannability
4. Avoid repeating information from other files

---

## 14. Emergency Procedures

### If Agent Gets Stuck

**User intervention steps**:
1. Interrupt the agent
2. Read `.agent_logs/` to understand what happened
3. Read `task-log.md` to see current status
4. Read latest `logs/*.json` to see command results
5. Manually mark problematic task as blocked
6. Tell agent: "Move on to [specific task]"

### If Terminal Locks

**Prevention** (this should NEVER happen if following rules):
- All commands via `./scripts/run-command.sh`
- Never run interactive commands

**If it does happen**:
1. Kill terminal process
2. Check what command was run
3. Add command to "never run directly" list
4. Update documentation
5. Restart with different task

### If Logs are Missing

**If `.agent_logs/` empty**:
- Agent not following logging rules
- Review agent-docs.md
- Restart session with logging

**If `logs/` empty**:
- Commands not run via wrapper
- Check command execution pattern
- Verify `scripts/run-command.sh` exists and works

### If Context Window Full

**Signs**:
- Responses getting truncated
- Agent "forgetting" earlier context
- Token usage >180,000

**Solutions**:
1. Summarize current progress in `.agent_logs/`
2. Update `task-log.md` with current state
3. Start new session with fresh context
4. Reference previous session logs if needed

---

**Version**: 1.0  
**Last Updated**: 2024-11-29  
**Status**: ACTIVE  
**Next Review**: After first successful implementation session