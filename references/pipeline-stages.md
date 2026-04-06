# Pipeline Stages — Deep Dive

Detailed operational reference for each stage of the pipeline-orchestrator. Read this when you need specifics beyond what SKILL.md covers.

---

## Stage 1: PLAN — Task Decomposition

### Goal
Transform a free-form task description into a structured DAG of sub-tasks with dependency edges, parallelism annotations, and complexity estimates.

### Input
- User's task description (natural language)
- Any referenced files or URLs

### Output
- `plan.json` (see state-schema.md for full schema)

### Process

#### 1.1 Task Extraction
Read the task description and extract every discrete unit of work. A "task" is something that:
- Has a clear start and end state
- Can be assigned to a single sub-agent
- Produces a verifiable artifact (file, change, output)

**Anti-patterns:**
- Tasks that are too broad: "Build the backend" → break into API routes, DB schema, auth, etc.
- Tasks that are too granular: "Create variable X" → merge into the function/module task
- Overlapping tasks: "Write the header component" and "Write the navigation" → merge if they modify the same file

#### 1.2 Dependency Analysis
For each task, ask: "Can this start without any other task completing first?"

Build edges:
```
t1 → t3 (t3 depends on t1's output)
t2 → t3
t1 → t4
```

**Dependency types:**
- **Data dependency:** Task B needs a file/output that Task A creates
- **Order dependency:** Task B must logically follow Task A (e.g., deploy after build)
- **Resource dependency:** Both tasks modify the same file (serialize them to avoid conflicts)

**Critical rule:** If two tasks modify the same file, they CANNOT be in the same parallel group. Either merge them or serialize them.

#### 1.3 Parallel Group Assignment
Tasks with no dependencies on each other go into the same parallel group. Assign groups by topological sort level:
- Group 1: All tasks with no dependencies (roots of the DAG)
- Group 2: Tasks whose dependencies are all in Group 1
- Group 3: Tasks whose dependencies are all in Groups 1-2
- etc.

#### 1.4 Complexity Estimation

| Complexity | Description | Examples |
|-----------|-------------|----------|
| `simple` | Straightforward, well-defined, no ambiguity | Create a config file, write a simple function, add an import |
| `medium` | Requires some thought, multiple steps, some edge cases | Build a module with error handling, write integration logic |
| `complex` | Significant implementation, many edge cases, architectural decisions | Design a data pipeline, implement auth system, build complex UI |

#### 1.5 Context File Selection
For each task, identify the MINIMUM set of files the sub-agent needs to read. Over-context is worse than under-context — it dilutes focus and burns tokens.

**Include:**
- Files the task will modify
- Files the task reads from (APIs, types, interfaces)
- Config files if relevant

**Exclude:**
- Unrelated source files
- Test files (unless the task is about tests)
- Documentation (unless the task is about docs)
- The entire project tree

### Validation Checks
Before finalizing the plan:
- [ ] No circular dependencies (DAG must be acyclic)
- [ ] Every task has at least one acceptance criterion possible
- [ ] Parallel groups respect all dependency edges
- [ ] No two tasks in the same group modify the same file
- [ ] Total task count is reasonable (3-20 for most pipelines)

---

## Stage 2: PRD — Product Requirements Document

### Goal
Define precise, testable acceptance criteria for every sub-task so that VERIFY can make binary pass/fail decisions.

### Input
- `plan.json`

### Output
- `prd.json`

### Process

#### 2.1 Criteria Writing
For each task, write 2-5 acceptance criteria. Each criterion must be:

**Binary:** Can be answered yes/no. Not "code is clean" but "no lint errors when running `eslint src/`."

**Observable:** Based on something you can check — file existence, command output, code content, test results.

**Specific:** Not "API works" but "GET /users returns 200 with JSON array."

**Examples of good criteria:**
```
✅ "File src/parser.js exists and exports a function named 'parse'"
✅ "Running 'node src/parser.js test.csv' outputs valid JSON to stdout"
✅ "All existing tests pass: 'npm test' exits with code 0"
✅ "No TypeScript errors: 'npx tsc --noEmit' exits with code 0"
```

**Examples of bad criteria:**
```
❌ "Code is well-written" (subjective)
❌ "It works" (not specific)
❌ "Performance is good" (not measurable without a benchmark)
❌ "Follows best practices" (vague)
```

#### 2.2 Verification Method Selection

| Method | When to use | How it works |
|--------|------------|--------------|
| `automated` | File existence, command exit codes, test suites | Run shell commands, check exit code 0 = pass |
| `manual` | Code quality, architectural decisions, UX | Agent reads files and makes judgment call |
| `hybrid` | Most real tasks | Some criteria automated, some manual review |

#### 2.3 Verification Command Writing
Write shell commands that the VERIFY stage can execute via `exec`:

```bash
# File existence
test -f src/parser.js && echo "PASS" || echo "FAIL"

# Function export check
node -e "const m = require('./src/parser'); console.log(typeof m.parse === 'function' ? 'PASS' : 'FAIL')"

# Test suite
npm test 2>&1; echo "EXIT:$?"

# Lint check
npx eslint src/ --quiet 2>&1; echo "EXIT:$?"

# Content check
grep -q "export default" src/parser.js && echo "PASS" || echo "FAIL"
```

**Rules for verification commands:**
- Must be idempotent (running twice gives same result)
- Must complete in <30 seconds
- Must not modify any files
- Should output PASS/FAIL or have meaningful exit codes
- Include `2>&1` to capture stderr

#### 2.4 Verification Checklist
For manual/hybrid verification, write checklist items that the verifying agent can assess by reading files:

```
- [ ] Error handling covers: empty input, malformed CSV, missing columns
- [ ] API response format matches the documented schema
- [ ] No hardcoded credentials or secrets in source files
- [ ] Code uses consistent naming conventions with the rest of the project
```

---

## Stage 3: EXEC — Execution

### Goal
Execute all sub-tasks, leveraging parallelism for independent work, tracking progress in real-time.

### Input
- `plan.json` (task definitions, dependencies, parallel groups)
- `prd.json` (acceptance criteria for each task)

### Output
- `progress.json` (continuously updated during execution)

### Process

#### 3.1 Pre-Execution Checks
Before spawning any sub-agents:
1. Verify all `contextFiles` from plan.json exist and are readable
2. Check for any shared files across tasks in the same parallel group (conflict risk)
3. Ensure state directory exists and meta.json is current

#### 3.2 Parallel Group Execution

```
for group in sorted(parallelGroups.keys()):
    tasks_in_group = parallelGroups[group]
    
    // Batch if >4 tasks
    for batch in chunks(tasks_in_group, 4):
        for task in batch:
            spawn_subagent(task)
        wait_for_all(batch)  // sessions_yield
        update_progress(batch)
    
    // Check for critical failures before next group
    if any task in group failed AND downstream tasks depend on it:
        mark downstream tasks as "blocked"
        log warning
```

#### 3.3 Sub-Agent Prompt Construction

The prompt given to each sub-agent is critical. It must be:
- **Focused:** Only the task at hand, not the whole pipeline
- **Complete:** All info needed to execute without asking questions
- **Bounded:** Clear scope of what to modify and what not to touch

**Template:**
```
You are executing a single sub-task as part of a larger pipeline.
Do your task completely and report results. Do not ask questions.

## Task: {task.name}
{task.description}

## Acceptance Criteria
You MUST satisfy ALL of the following:
{for each criterion}
- {criterion}

## Context Files
{for each contextFile, include the actual file content — not just the path}

## Scope Constraints
- Only modify files directly related to this task
- Do not install new system packages
- If you need to install npm/pip packages, document them
- Do not modify: {list files owned by other tasks}

## When Done
Report in this exact format:
### Result
- Status: completed | failed
- Files created: [list]
- Files modified: [list]

### Self-Assessment
{for each criterion}
- {criterion}: PASS | FAIL
  - Evidence: {what you observed}

### Issues
{any concerns, blockers, or notes for the pipeline}
```

#### 3.4 Handling Sub-Agent Results

When a sub-agent completes:
1. Parse its final message for the structured result format
2. Update `progress.json` with status, files modified, self-assessment
3. If the result is unstructured (agent didn't follow format), mark as `completed` but flag for careful verification

#### 3.5 Handling Failures During Execution
- If a sub-agent fails to produce output: mark as `failed`, reason = "no output"
- If a sub-agent reports failure: record its explanation, mark as `failed`
- If a task is blocked by a failed dependency: mark as `blocked`, skip execution
- Continue executing non-blocked tasks — don't abort the whole pipeline on one failure

---

## Stage 4: VERIFY — Verification

### Goal
Independently verify every sub-task against its acceptance criteria. Trust nothing from self-assessment — verify independently.

### Input
- `prd.json` (criteria and verification methods)
- `progress.json` (what was done)
- The actual files/artifacts produced

### Output
- `verify.json`

### Process

#### 4.1 Automated Verification
For each task with `verificationCommands`:
```bash
for cmd in verificationCommands:
    result = exec(cmd, timeout=30)
    record: command, exitCode, stdout, stderr
    verdict = exitCode == 0 ? "pass" : "fail"
```

Handle edge cases:
- Command times out (>30s) → `fail` with reason "timeout"
- Command not found → `fail` with reason "command not available"
- Ambiguous output → `partial`, flag for manual review

#### 4.2 Manual Verification
For each `verificationChecklist` item:
1. Read the relevant files using `read`
2. Assess whether the checklist item is satisfied
3. Record evidence (quote specific lines, note what was found/missing)

#### 4.3 Cross-Task Verification
After verifying individual tasks, check integration:
- Do files modified by different tasks conflict?
- If Task A created an interface and Task B implemented it, do they match?
- Run any project-wide checks (full test suite, build, lint)

#### 4.4 Verdict Assignment
For each task:
- **pass:** ALL criteria met (automated pass + checklist pass)
- **fail:** One or more criteria clearly not met
- **partial:** Ambiguous — some criteria met, others unclear. **Treat as fail for retry purposes.**

#### 4.5 Summary and Decision
```
if all tasks pass:
    pipeline.status = "completed"
    report success to user
else:
    pipeline.status = "fixing"
    proceed to FIX stage
```

---

## Stage 5: FIX — Bounded Retry

### Goal
Fix only what's broken, using failure context to guide targeted repairs.

### Input
- `verify.json` (what failed and why)
- `progress.json` (what was done)
- `prd.json` (what was expected)

### Output
- Updated `progress.json`
- New `verify.json` (after re-verification)

### Process

#### 5.1 Failure Triage
Categorize each failure:

| Category | Description | Action |
|----------|------------|--------|
| Implementation bug | Code exists but has a bug | Fix the specific bug |
| Missing implementation | Part of the task wasn't done | Complete the missing piece |
| Wrong approach | Fundamentally wrong solution | Re-implement (may need full sub-agent) |
| Spec issue | Acceptance criteria is wrong/impossible | Adjust criteria (rare, log prominently) |
| External blocker | Missing dependency, network issue, etc. | Flag as `needs-human` |

#### 5.2 Fix Sub-Agent Prompt
The fix prompt is different from the original exec prompt. It adds:
- **What was already done** (so the agent doesn't redo everything)
- **What specifically failed** (with evidence from verify.json)
- **Prior fix attempts** (if this isn't the first try)

```
You are FIXING a failed sub-task. This is attempt {N} of 3.

## Original Task
{task.description}

## What Was Previously Implemented
{summary of what was done — files created, approach taken}

## What Failed (from verification)
{for each failed criterion}
- FAILED: {criterion}
  Evidence: {evidence}
  Details: {failureDetails}

## What Passed (DO NOT break these)
{for each passed criterion}
- PASSED: {criterion}

## Your Job
Fix ONLY the failed criteria. Do not redo or modify anything that already passes.
If the failures are interconnected, fix the root cause.

{if attempt > 1}
## Previous Fix Attempts
Attempt {N-1} tried: {description of prior fix}
It still failed because: {why}
Try a different approach.
{/if}
```

#### 5.3 Retry Loop Logic
```
for attempt in 1..3:
    fix_failed_tasks()
    run_verify()
    
    if all pass:
        meta.status = "completed"
        break
    
    if attempt == 3 and still failing:
        meta.status = "needs-human"
        report: 
            - which tasks still fail
            - what was tried (all 3 attempts)
            - why it's stuck
            - suggested human action
```

#### 5.4 Escalation to Human
When marking `needs-human`, the report should include:
- Task ID and name
- All 3 fix attempts summarized
- The specific criterion that won't pass
- Agent's theory on why (if it has one)
- Suggested action for the human (modify spec? provide info? manual fix?)

---

## Stage Transitions

```
PLAN ──success──▶ PRD ──success──▶ EXEC ──success──▶ VERIFY
  │                 │                │                  │
  fail              fail             fail            all pass → DONE
  │                 │                │                  │
  ▼                 ▼                ▼              some fail
 ABORT            ABORT           continue            │
                                  (partial)           ▼
                                                     FIX ──success──▶ VERIFY
                                                      │                 │
                                                   attempt 3          all pass → DONE
                                                   still fail            
                                                      │              some fail + attempt < 3
                                                      ▼                  │
                                                  NEEDS-HUMAN           ▼
                                                                    FIX (loop)
```

- PLAN failure = task decomposition failed (circular deps, unclear requirements) → ask user for clarification
- PRD failure = can't write criteria (task too vague) → ask user for clarification
- EXEC failure = some tasks fail → continue, catch in VERIFY
- VERIFY → FIX → VERIFY loop, bounded at 3 iterations
- After 3 failed fixes → needs-human escalation
