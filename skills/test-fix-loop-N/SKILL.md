---
name: test-fix-loop-N
description: Discover Go test failures, partition by package/count, spawn N parallel test-fix-loop agents, verify results. Args: <parent-branch> [max-agents]
---

# Test Fix Loop N

Discover all Go test failures, partition across N parallel agents, each
running `/test-fix-loop`. Agents merge back to shared parent branch via
existing sync protocol.

## Arguments

- `$1` — **parent branch** (required). e.g. `feat-xslt3`.
- `$2` — **max agents** (optional, default 4).

If no parent branch given, ask user.

## 1. Setup

1. Confirm `$PARENT` exists: `git rev-parse --verify $PARENT`.
2. Create orchestrator worktree:
   - Name: `fix-orch-<short-id>-<date>` — globally unique.
   - Path: `$PROJECT/.worktrees/<branch>`.
   ```
   git worktree add $PROJECT/.worktrees/<branch> -b <branch> $PARENT
   ```
3. `cd` to orchestrator worktree. Create `.tmp/` if missing.
4. This worktree is for discovery + final verification only. Orchestrator does NOT fix code.

## 2. Discovery

1. Run full suite:
   ```
   go test ./... -timeout=15m -v > .tmp/go-test-discovery.txt 2>&1
   ```
   `-v` required — ensures every test name appears in output.
2. Parse `.tmp/go-test-discovery.txt`. Extract every failure:
   - `--- FAIL: TestName` → capture test name
   - `FAIL\tpkg/path` → capture package
   - `panic:` / compile error → capture package, mark `__compile_error__`
3. Build failure manifest: list of `(package, test_name)` tuples.
4. Store in `.tmp/failure-manifest.txt`.
5. Zero failures → report clean, stop.

## 3. Partitioning

1. Group by package → `(pkg_path, [test_names], count)`.
2. Sort by count descending.
3. Compile-error packages → isolated partition each (one package per partition).
4. Target partition size: `ceil(total_failures / max_agents)`.
5. Large packages (count > target) → split into sub-partitions by test name.
6. Small packages → combine into one partition if combined count <= target.
7. Final partition count: `min(len(partitions), max_agents)`.

Per partition compute:

| Field | Value |
|-------|-------|
| Package list | One or more `./pkg/path` entries |
| `-run` regex | `^(TestA\|TestB\|TestC)$` — anchored, metacharacters escaped |
| Omit `-run` | When partition owns ALL failures in a package |

Store partition plan in `.tmp/partition-plan.txt`.

### Regex Rules

- ALWAYS anchor with `^...$` — Go `-run` does substring match.
- Escape regex metacharacters in test names (`+`, `.`, `(`, etc.) with `\`.
- Parent test name suffices for subtests — Go runs all subtests when parent matches.

## 4. Spawn Agents

Issue ALL Agent tool calls in **single block** (parallel execution).

Each agent receives prompt:

```
Run /test-fix-loop <parent-branch> -run '^(TestA|TestB|TestC)$' ./pkg1 ./pkg2

You are responsible for fixing ALL of these assigned failing tests:
1. ./pkg1 — TestA
2. ./pkg1 — TestB
3. ./pkg2 — TestC

COMPLETION RULES:
- MUST attempt every assigned test. Do NOT stop after fixing one or a few.
- After each fix+merge cycle, re-check which assigned tests still fail.
  Continue until all fixed or documented as non-actionable blockers.
- Test now passes (another agent fixed root cause) → counts as resolved, move on.
- "Complex" / "requires large change" is NOT a reason to stop. That IS the work.
- DONE only when: (a) all assigned tests pass, OR (b) every remaining failure
  documented as non-actionable blocker with specific reason.

REPORT FORMAT when done:
For each assigned test: test name, status (fixed/already-passing/blocked),
root cause, fix description or blocker reason.
```

- Each agent creates own worktree (test-fix-loop handles naming).
- Cross-agent fix propagation: existing sync protocol resets to parent HEAD each iteration.
- Wait for all agents to return.

## 5. Collect & Validate Reports

1. Parse each agent's return: fixed tests, blockers, errors.
2. **Validate completeness**: every assigned test MUST appear in agent's report.
   - Missing tests → record as `agent abandoned — needs retry`.
3. Consolidate into `.tmp/agent-reports.txt`.

## 6. Final Verification

1. Sync orchestrator worktree to `$PARENT` HEAD:
   ```
   git fetch . $PARENT
   git reset --hard $PARENT
   ```
2. Run full suite:
   ```
   go test ./... -timeout=15m > .tmp/go-test-final.txt 2>&1
   ```
3. Cross-reference against original manifest → categorize each test:
   - **fixed** — was failing, now passes
   - **blocked** — agent documented as non-actionable
   - **abandoned** — agent quit early, test still failing

## 7. Retry Wave

**Trigger**: failures remain AND (wave made progress OR any agent abandoned tests).

1. Re-run discovery (step 2) against current state.
2. Collect only tests still failing.
3. Exclude tests confirmed as non-actionable blockers.
4. Re-partition remaining failures, spawn new wave (steps 3–6).
5. Cap at 3 total waves (initial + 2 retries).
6. STOP if wave makes zero progress (same failure count as previous wave).

## 8. Cleanup

1. Remove orchestrator worktree:
   ```
   cd $PROJECT
   git worktree remove .worktrees/<orch-branch> --force
   ```
2. Agent worktrees left per existing convention.

## 9. Final Report

```
## Orchestrator Report

Failures discovered: N
Waves: W
Agents spawned: M (wave 1) [+ K (wave 2) ...]
Tests fixed: X
Tests blocked: Y
Tests abandoned: Z

### Per-Agent Summary
| Agent | Wave | Worktree | Assigned | Fixed | Blocked | Abandoned |
|-------|------|----------|----------|-------|---------|-----------|

### Remaining Failures (if any)
| Package | Test | Status | Reason |
|---------|------|--------|--------|
```

## Hard Rules

- ALWAYS discover in orchestrator worktree, not repo root.
- ALWAYS spawn via Agent tool in single parallel block.
- NEVER exceed `max_agents`.
- NEVER mix compile-error packages with test-failure packages in same partition.
- ALWAYS anchor `-run` regex with `^...$`.
- ALWAYS run final verification after all agents complete.
- NEVER exceed 3 total waves.
- NEVER skip retry wave if agents abandoned tests or wave made progress.
- ALWAYS include full test assignment list + completion rules in agent prompts.
- ALWAYS validate agent reports for completeness — detect early quitters.
- ALWAYS re-queue abandoned tests in retry waves.
- NEVER accept "complex" / "large change" as blocker reason — only non-actionable items (infra, permissions, network).

## Actionable vs Non-Actionable

Same criteria as `test-fix-loop`:

| Actionable | Non-Actionable |
|------------|----------------|
| Implementation bug | External infra outage |
| Wrong error code / serialization | Corrupted checkout |
| Missing feature needed by test | Toolchain install failure |
| Flaky test from repo code | Permission / network issue |
| Parser / fixture issue fixable in repo | |
