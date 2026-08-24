---
name: git-cleanup-merged
description: Clean up local branches and worktrees that have been merged into a target branch (default: main). Args: [target-branch]
---

# Git Cleanup Merged

Clean up local branches and worktrees whose changes have already been merged into a target branch.

## Args

`/git-cleanup-merged [target-branch] [trunk-branch]`

- `target-branch` — branch to check against. Default: `main`.
- `trunk-branch` — passed straight through to detection. Default: `main`.

Refer to the target branch as `$TARGET` below.

## Workflow

### 1. Detect merged branches

Use the `git-detect-merged` skill with the same args. It returns the TSV table that drives every later step — branch, merge type, status, worktree path, reason.

Detection exited non-zero → report the error and STOP. NEVER fall back to a hand-run `git branch --merged`.

Detection reported a non-zero `behind` count → STOP before step 2. `$TARGET` is missing the merges it was asked about, so the table understates what is merged, and deleting from it is safe but the run is incomplete. Tell the user the count and ask them to bring `$TARGET` up to date, then re-run.

### 2. Build cleanup candidates

- Include a row if and only if its `status` is exactly `clean`.
- Every other row is skipped, carrying its `reason` verbatim into the summary.
- NEVER widen this rule. `dirty`, `checked-out`, and `unknown` all mean detection could not prove the branch is safe to delete, and `unknown` in particular means it could not read the state at all.

### 3. Present summary

Show the user a single summary listing:

- **Worktrees to remove** (path + branch), for candidate rows whose `worktree` column is not `-`.
- **Branches to delete** (name + merge type). Mark squash-merged branches as requiring `-D` — `git branch -d` cannot see squash merges and always fails on them.
- **Skipped** — every non-`clean` row, with its `reason`.
- **Not merged** — the `unmerged` and `out-of-scope` counts from the detection metadata lines.

If there are no candidates, say so and stop.

### 4. Confirm

Ask the user for a single confirmation before proceeding. Do NOT proceed without approval. This confirmation covers `-D` for branches marked squash-merged in the summary — their merge was already verified by patch-id in detection.

### 5. Execute cleanup

- Remove worktrees first (`git worktree remove <path>`), then delete branches.
- Regular merges → `git branch -d <branch>`. Squash merges → `git branch -D <branch>` (covered by step 4 confirmation).
- If `-d` unexpectedly fails on a regular-merge branch, ask the user before using `-D`.
- Report results after each step.

## Rules

- NEVER delete `$TARGET` or `main`. Detection already excludes both; do not re-add them by hand.
- NEVER touch remote branches or remote tracking refs.
- Use `-d` (safe delete) for regular merges. `-D` for squash-merged branches is pre-approved by the step 4 confirmation; any other `-D` requires explicit user approval.
- If a worktree removal fails, report the error and continue with the remaining items.
- If a branch delete fails, report the error and continue with the remaining items.
