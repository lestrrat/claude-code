---
name: git-cleanup-merged
description: Clean up local branches and worktrees that have been merged into main.
---

# Git Cleanup Merged

Clean up local branches and worktrees whose changes have already been merged into `main`.

## Workflow

### 1. Detect merged branches

Use the `git-detect-merged` skill to identify all merged branches, their merge type, active work status, and associated worktrees.

### 2. Build cleanup candidates

From the detection results:

- Include branches that are merged AND have no active work (status: `clean`).
- Include worktrees whose branch is merged AND clean.
- Exclude `main` — NEVER delete it.
- Exclude branches with active work (dirty or checked-out), even if merged.

### 3. Present summary

Show the user a single summary listing:

- **Worktrees to remove** (path + branch)
- **Branches to delete** (name + merge type: regular/squash)
- **Skipped** — merged branches/worktrees excluded due to active work, with the reason (e.g. "has uncommitted changes", "currently checked out")

If nothing to clean, say so and stop.

### 4. Confirm

Ask the user for a single confirmation before proceeding. Do NOT proceed without approval.

### 5. Execute cleanup

- Remove worktrees first (`git worktree remove <path>`), then delete branches (`git branch -d <branch>`).
- If a branch fails to delete with `-d` (e.g. git thinks it is not fully merged), ask the user whether to force-delete it with `-D`. Do NOT use `-D` without explicit user approval.
- Report results after each step.

## Rules

- NEVER delete `main`.
- NEVER touch remote branches or remote tracking refs.
- Use `-d` (safe delete) by default. Only use `-D` (force delete) if the user explicitly confirms.
- If a worktree removal fails, report the error and continue with the remaining items.
- If a branch delete fails, report the error and continue with the remaining items.
