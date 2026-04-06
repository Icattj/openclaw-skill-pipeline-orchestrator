# Dual Reasoning — Think/Act Pattern

The dual reasoning pattern ensures every stage of the pipeline goes through deliberate analysis before action. Inspired by Chat2Graph's Thinker/Actor model and System 1/System 2 thinking.

## The Pattern

```
┌──────────────┐     ┌──────────────┐
│   THINK      │ ──▶ │    ACT       │
│              │     │              │
│ • Analyze    │     │ • Execute    │
│ • Risk check │     │ • Follow plan│
│ • Plan steps │     │ • Report     │
│ • Edge cases │     │ • No improv  │
└──────────────┘     └──────────────┘
```

## Think Phase

Before any action, the agent MUST produce structured reasoning:

### Think Prompt Template
```
THINK PHASE — Do NOT take any action yet.

Before proceeding with this stage, analyze:

1. SITUATION
   - What is the current state of the pipeline?
   - What inputs do we have from prior stages?
   - What constraints are we operating under?

2. RISKS
   - What could go wrong in this stage?
   - What are the failure modes?
   - What's the blast radius if something fails?

3. DEPENDENCIES
   - What does this stage depend on?
   - What downstream stages depend on our output?
   - Are all prerequisites satisfied?

4. EDGE CASES
   - What non-obvious scenarios should we handle?
   - What happens with empty/null/unexpected inputs?
   - Are there concurrency concerns?

5. PRIOR FAILURES
   - Has this task been attempted before? (check verify.json)
   - What specifically failed last time?
   - How will this attempt differ?

6. PLAN
   - What specific steps will we take?
   - In what order?
   - What does success look like?

Output your reasoning clearly. Then proceed to ACT.
```

### Think Output Format
The think phase should produce reasoning like:

```
## THINK

**Situation:** Pipeline abc123, EXEC stage, parallel group 2. Group 1 completed
with 3/3 tasks passing. We have outputs from t1, t2, t3 available.

**Risks:** Task t4 depends on t2's output (parser module). If the interface 
changed during t2's implementation, t4 will fail. Also, t4 and t5 both modify 
config.json — potential conflict.

**Dependencies:** t4 depends on t2 (parser.js exports). t5 depends on t1 
(CLI args module). Both need to exist and be importable.

**Edge Cases:** t4's validation logic needs to handle Unicode invoice numbers 
(Indonesian market). t5's config merge could overwrite t4's additions if they 
run truly parallel.

**Prior Failures:** First attempt — no prior failures.

**Plan:**
1. Separate t4 and t5 into sequential execution (same-file conflict)
2. Spawn t4 first with t2's parser.js as context
3. After t4 completes, spawn t5 with t1's cli.js + updated config.json
4. Update progress.json after each
```

## Act Phase

After think, execute with discipline:

### Act Prompt Template
```
ACT PHASE — Execute your plan from the THINK phase.

Rules:
1. Follow your plan step by step. No improvisation.
2. If you discover something unexpected:
   - Note it in your report
   - Continue with the plan unless it's a blocker
   - If blocked, explain WHY rather than guessing a workaround
3. Report results in structured format
4. Track what you did vs. what you planned
```

### Act Output Format
```
## ACT

**Step 1:** Spawned sub-agent for t4 with parser.js context
- Result: Completed, validation module created at src/validate.js
- Deviation from plan: None

**Step 2:** Spawned sub-agent for t5 with cli.js + config.json
- Result: Completed, config.json updated with new keys
- Deviation from plan: t5 also needed validate.js as input (discovered at runtime)
  - Handled by including t4's output in t5's context

**Step 3:** Updated progress.json
- t4: completed
- t5: completed

**Unexpected findings:**
- t5 revealed that config.json schema should include a 'validation' section
  not originally planned. Added it. May affect t6 (tests).
```

## When to Use Each Phase

| Stage | Think Focus | Act Focus |
|-------|------------|-----------|
| PLAN | Task boundaries, dependencies, complexity | Write plan.json |
| PRD | Testability, specificity, coverage | Write prd.json |
| EXEC | Parallelism, conflicts, context | Spawn agents, track progress |
| VERIFY | Suspicious passes, integration | Run checks, write verify.json |
| FIX | Root cause, prior attempts, approach | Targeted fixes only |

## Why This Matters

Without Think/Act separation:
- Agents jump to implementation and miss edge cases
- Failures are harder to diagnose (no reasoning trail)
- Fix attempts repeat the same mistake
- Parallel execution creates conflicts nobody anticipated

With Think/Act:
- Reasoning is documented and reviewable
- Failures have context ("I thought X but Y happened")
- Fix attempts can reference prior reasoning
- Conflicts are caught before they happen

## Dual Model Variant (Advanced)

In Chat2Graph's original design, Thinker and Actor are different models:
- Thinker: Larger/smarter model (planning, analysis)
- Actor: Faster/cheaper model (execution, tool calls)

In OpenClaw, we achieve this through:
- Think phase uses the orchestrating agent (main session, potentially opus-level)
- Act phase spawns sub-agents (can be sonnet-level for lighter tasks)

This naturally maps to smart model routing:
- PLAN think = opus (deep decomposition) → PLAN act = write files (sonnet ok)
- EXEC think = opus (conflict detection) → EXEC act = sub-agents (model per complexity)

## Anti-Patterns

1. **Skipping Think:** "I know what to do, let me just start coding." This leads to missed edge cases and repeated failures.

2. **Think without substance:** "I thought about it and it's fine." The think phase must produce SPECIFIC analysis, not handwaving.

3. **Deviating in Act:** "I found a better way while implementing." Unless it's a blocker, stick to the plan. Note improvements for next iteration.

4. **Think paralysis:** Spending 80% of time thinking and 20% acting. Think should be thorough but bounded — aim for 20% think, 80% act.

5. **Ignoring Think output in Act:** The whole point is that Act follows Think. If Act does something different, the reasoning trail is useless.
