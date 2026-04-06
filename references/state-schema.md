# State File Schemas

Complete JSON schemas for all pipeline state files.

## Directory Structure

```
state/pipeline-{id}/
├── meta.json        — Pipeline metadata
├── plan.json        — Task decomposition (DAG)
├── prd.json         — Acceptance criteria
├── progress.json    — Execution tracking
└── verify.json      — Verification results
```

## meta.json

```json
{
  "id": "string — pipeline-{8 hex chars}",
  "task": "string — original task description from user",
  "status": "planning | prd | executing | verifying | fixing | completed | failed | cancelled | needs-human",
  "currentStage": "PLAN | PRD | EXEC | VERIFY | FIX",
  "created": "ISO 8601 timestamp",
  "updated": "ISO 8601 timestamp",
  "completedAt": "ISO 8601 timestamp | null",
  "fixAttempts": "integer 0-3",
  "maxFixAttempts": 3,
  "taskCount": "integer — total sub-tasks in plan",
  "passedCount": "integer — tasks that passed verification",
  "failedCount": "integer — tasks that failed verification"
}
```

### Status State Machine
```
planning → prd → executing → verifying → completed
                                ↓
                             fixing → verifying (loop, max 3)
                                ↓
                           needs-human

Any state → cancelled (user cancel)
Any state → failed (unrecoverable error)
```

## plan.json

```json
{
  "id": "string — same as meta.id",
  "task": "string — original task description",
  "created": "ISO 8601 timestamp",
  "tasks": [
    {
      "id": "string — t1, t2, etc.",
      "name": "string — short descriptive name",
      "description": "string — detailed description of what needs to be done",
      "dependencies": ["string — task IDs that must complete before this starts"],
      "complexity": "simple | medium | complex",
      "parallelGroup": "integer — execution wave number (1 = first)",
      "contextFiles": ["string — paths to files this sub-agent needs"]
    }
  ],
  "parallelGroups": {
    "1": ["t1", "t3"],
    "2": ["t2", "t4"],
    "3": ["t5"]
  },
  "estimatedDuration": "string — human-readable estimate",
  "risks": ["string — identified risks"]
}
```

### Validation Rules
- `tasks[].id` must be unique
- `tasks[].dependencies` must reference existing task IDs
- No circular dependencies (DAG constraint)
- Tasks in the same `parallelGroup` must NOT depend on each other
- Tasks in group N must only depend on tasks in groups < N
- `parallelGroups` keys must be sequential integers starting from 1
- Every task must appear in exactly one parallel group

## prd.json

```json
{
  "pipelineId": "string — same as meta.id",
  "created": "ISO 8601 timestamp",
  "requirements": [
    {
      "taskId": "string — references plan.tasks[].id",
      "taskName": "string — for readability",
      "acceptanceCriteria": [
        "string — binary pass/fail criterion"
      ],
      "verificationMethod": "automated | manual | hybrid",
      "verificationCommands": [
        "string — shell commands returning PASS/FAIL or exit 0/1"
      ],
      "verificationChecklist": [
        "string — manual check items for agent review"
      ]
    }
  ]
}
```

### Verification Command Rules
- Must be idempotent (safe to run multiple times)
- Must complete in < 30 seconds
- Must NOT modify any files
- Should output "PASS" / "FAIL" or use exit codes (0 = pass, non-zero = fail)
- Include `2>&1` to capture stderr
- Must work from the workspace root directory

## progress.json

```json
{
  "pipelineId": "string — same as meta.id",
  "currentGroup": "integer — parallel group currently executing",
  "tasks": {
    "t1": {
      "status": "pending | running | completed | failed | blocked",
      "startedAt": "ISO 8601 timestamp | null",
      "completedAt": "ISO 8601 timestamp | null",
      "agentSessionKey": "string | null — OpenClaw session key of sub-agent",
      "result": "string | null — summary of what was done or error message",
      "filesModified": ["string — paths to files created or modified"],
      "selfAssessment": {
        "criterion text": "pass | fail"
      }
    }
  }
}
```

### Task Status Transitions
```
pending → running → completed
pending → running → failed
pending → blocked (dependency failed)
failed → running (during FIX stage)
```

## verify.json

```json
{
  "pipelineId": "string — same as meta.id",
  "verifiedAt": "ISO 8601 timestamp",
  "attempt": "integer — which verification pass (1, 2, 3)",
  "results": [
    {
      "taskId": "string",
      "verdict": "pass | fail | partial",
      "criteria": [
        {
          "criterion": "string — the acceptance criterion text",
          "result": "pass | fail",
          "evidence": "string — what was observed",
          "failureDetails": "string | null — why it failed (only for failures)"
        }
      ],
      "automatedResults": [
        {
          "command": "string — the verification command",
          "exitCode": "integer",
          "output": "string — stdout+stderr (truncated to 500 chars)",
          "result": "pass | fail"
        }
      ]
    }
  ],
  "summary": {
    "total": "integer — total tasks",
    "passed": "integer",
    "failed": "integer",
    "partial": "integer",
    "allPassed": "boolean"
  }
}
```

### Verdict Rules
- `pass`: ALL criteria pass (automated + manual)
- `fail`: One or more criteria clearly fail
- `partial`: Some criteria ambiguous — treated as `fail` for retry logic
