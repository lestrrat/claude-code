---
name: worktree-task
description: Execute instructions in an isolated worktree, commit, fast-forward merge to parent, cleanup. Args: <parent-branch> <instructions...>
---

# Worktree Task

Execute a set of instructions in an isolated worktree branched from a parent branch.
Commit results, fast-forward merge back to parent, delete worktree/branch, report.

## Args

`/worktree-task <parent-branch> <instructions...>`

- `$PARENT` — branch to fork from and merge back to (required).
- `$INSTRUCTIONS` — what to do in the worktree (required). Free-form text.

If either is missing, ask the user.

## Setup

1. Verify `$PARENT` exists: `git rev-parse --verify $PARENT`.
2. Generate branch name: `task-<short-description>-<date>` derived from instructions.
   - `<short-description>` — 2-3 word slug from instructions. e.g. `task-add-logging-20260322`.
   - Path: `$PROJECT/.worktrees/<branch>`.
3. Create worktree:
   ```
   git worktree add $PROJECT/.worktrees/<branch> -b <branch> $PARENT
   ```
4. `cd` to worktree. All work happens there.
5. Create `.tmp/` if missing.

## Execute

1. Carry out `$INSTRUCTIONS` in the worktree.
2. Follow all standard pre-read rules (Go, shell, etc.) as applicable to the work.
3. If instructions are ambiguous, ask the user before proceeding.

## Commit

1. Stage only files relevant to the instructions. Do NOT stage `.tmp/` content.
2. Write a commit message per `~/.claude/docs/git-messages.md` rules.
3. Commit.

## Merge

Rebase onto `$PARENT` so merge is fast-forward:

```
git fetch . $PARENT
git rebase $PARENT
```

Then fast-forward `$PARENT`. Locate where `$PARENT` is checked out:

- If `$PARENT` has a worktree → `cd` there, run `git merge --ff-only <branch>`.
- If `$PARENT` is in root checkout → `cd $PROJECT`, run `git merge --ff-only <branch>`.
- If `$PARENT` is not checked out anywhere → `cd $PROJECT`, run:
  ```
  git fetch . <branch>:$PARENT
  ```

If `--ff-only` fails → rebase again, retry once. If still fails → report error, do NOT force.

## Cleanup

After successful merge:

1. `git worktree remove $PROJECT/.worktrees/<branch>`
2. `git branch -d <branch>`

If merge failed → do NOT delete. Report the worktree path so the user can inspect.

## Report

Always end with:

- **Commit**: `<hash>` (short hash on `$PARENT` after merge)
- **Files modified**: list of changed files
- **Summary**: 1-3 sentence description of what was done
- **Worktree**: cleaned up, or path if retained due to error

## Rules

- ALWAYS work in the worktree, NEVER in root checkout.
- ALWAYS commit before merging — NEVER merge uncommitted work.
- ALWAYS use `--ff-only` — NEVER create merge commits.
- NEVER stage `.tmp/` or unrelated files.
- NEVER force-push or use `--force`.
- If instructions produce no changes → report "no changes needed", cleanup worktree, stop.
