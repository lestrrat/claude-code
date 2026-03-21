---
name: test-fix-loop
description: Continuously find and fix failing Go tests in a worktree, syncing with a parent branch between iterations. Use when user wants to fix all (or many) test failures in a branch via an automated loop. Args: <parent-branch> [test-args...]
---

# Test Fix Loop

Continuously find and fix failing Go tests, syncing with a parent branch
between iterations. Multiple agents can run this loop in parallel on
separate worktrees against the same parent branch.

## Arguments

- `$1` — **parent branch** (required). Branch to sync from and merge back to. e.g. `feat-xslt3`.
- `$2...` — **extra test args** (optional). Passed verbatim to `go test`. e.g. `-run TestFoo`.

If no parent branch is given, ask the user.

## Setup

1. Confirm `$PARENT` branch exists: `git rev-parse --verify $PARENT`.
2. Determine worktree path + branch name.
   - Name: `fix-loop-<short-id>-<date>` — must be globally unique across agents/sessions.
   - Path: `$PROJECT/.worktrees/<branch>`.
3. Create worktree off `$PARENT`:
   ```
   git worktree add $PROJECT/.worktrees/<branch> -b <branch> $PARENT
   ```
4. `cd` to the new worktree. All subsequent work happens there.
5. Create `.tmp/` if missing.

## Worktree Sync Protocol

### Sync (start of each iteration)

Hard-reset your branch to current `$PARENT` HEAD:
```
git fetch . $PARENT
git reset --hard $PARENT
```

### Merge back (end of each iteration)

Rebase onto `$PARENT` so merge is fast-forward:
```
git fetch . $PARENT
git rebase $PARENT
```
Then fast-forward `$PARENT`:
```
cd $PROJECT/.worktrees/$PARENT   # or wherever $PARENT worktree lives
git merge --ff-only <your-branch>
```
If `--ff-only` fails → rebase again (another agent may have merged in between).
After merge, return to your worktree and start next iteration.

## Loop

1. **Sync** — reset to latest `$PARENT` HEAD.
2. **Test** — run full suite:
   ```
   go test ./... -timeout=10m $EXTRA_ARGS > .tmp/go-test-all.txt 2>&1
   ```
3. **Find first failure** — search `.tmp/go-test-all.txt`:
   - first `--- FAIL:` line
   - else first `FAIL\tgithub.com/...` line
   - else first `panic:` / compile error
   - Use earliest line only. Ignore later failures.
4. **Classify** — actionable → continue. Non-actionable → document blocker, stop.
5. **Reproduce** — narrow rerun of failing test:
   ```
   go test ./<pkg> -run 'TestName/subtest$' -count=1 -timeout=30s
   ```
6. **Debug first.** Read source + test. Trace data flow. Find root cause BEFORE writing fix. NEVER delegate fix without confirmed root cause. If root cause is in another package within the module → chase it there. Do not limit investigation to the failing test's package.
7. **Fix** root cause — even if it lives in a different package. Prefer source fix over test edit.
8. **Narrow verify** — rerun the specific test.
9. **Full verify** — rerun full suite with exact command from step 2.
10. If more actionable failures → repeat from step 3.
11. **Lint**:
    ```
    golangci-lint run ./... > .tmp/golangci-lint.txt 2>&1
    ```
    Fix all issues. Re-run until clean.
12. **Commit** all iteration fixes.
13. **Merge** back to `$PARENT`.
14. Repeat from step 1.

**STOP** only when no actionable failures remain.

## Hard Rules

- ALWAYS work in your worktree, not repo root.
- ALWAYS use globally unique worktree/branch name.
- ALWAYS write test output to `.tmp/go-test-all.txt`.
- ALWAYS commit before merging — NEVER merge uncommitted work.
- ALWAYS re-run full suite after any fix — NEVER assume downstream failures resolved.
- ALWAYS run lint before commit — NEVER commit with lint errors.
- NEVER stop after analysis only — every iteration must produce a commit or document a blocker.
- NEVER stop after one fix if more actionable failures remain.
- NEVER skip a failure because it looks "complex." That IS the work.
- Prefer fixing root cause that removes multiple downstream failures.
- NEVER limit fixes to the failing test's package. If root cause is in another package within the module → fix it there.

## Actionable vs Non-Actionable

| Actionable | Non-Actionable |
|------------|----------------|
| Implementation bug | External infra outage |
| Wrong error code / serialization | Corrupted checkout |
| Wrong whitespace / namespace behavior | Toolchain install failure |
| Missing feature needed by test | Permission / network issue |
| Flaky test from repo code | |
| Parser / fixture issue fixable in repo | |

"This requires implementing a new feature" is NOT a reason to skip. Implement it.

## Fix Strategy

- **Debug first, plan later.** Instrument, trace, find exact breakpoint. Only then fix.
- **Measure after each fix.** If fewer tests pass than expected → investigate before continuing.
- Decompose multi-layer failures. Prefer earliest failing assertion.
- Prefer source fix over test edit.
- Add skip ONLY when unsupported behavior is intentional — encode reason, keep it specific.

## Rebase Conflict Handling

- Resolve conflicts during `git rebase --continue`.
- Verify build + tests pass after resolution.
- If conflict invalidates your fix (another agent fixed same test) → discard, re-sync.
- If `--ff-only` fails after rebase → rebase again, retry.

## Report

Each iteration:
- first failing package + test
- root cause
- fix made
- narrow rerun result
- full rerun result

Final report: "no actionable failures remain" or "blocked by: <reason>".
