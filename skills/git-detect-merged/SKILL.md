---
name: git-detect-merged
description: Detect whether local branches/worktrees have been merged into a target branch (default: main), including squash merges. Args: [target-branch]
---

# Git Detect Merged

Detect whether local branches and worktrees have their changes already merged into a target branch. Handles both regular merges and squash merges.

## Args

`/git-detect-merged [target-branch] [trunk-branch]`

- `target-branch` — branch to check against. Default: `main`.
- `trunk-branch` — branch the scope pre-filter measures against when it differs from the target. Default: `main`. Pass it ONLY in repos whose trunk is not `main` (e.g. `master`).

## Run the detector

`~/.claude/scripts/git-detect-merged [target-branch] [trunk-branch]`

The script performs the entire detection: candidate selection, scope pre-filter, regular- and squash-merge classification, and active-work status. NEVER re-derive any part of it by hand. The fail-closed logic lives in the script, and a hand-run `git branch --merged` misses squash merges and ignores the scope pre-filter.

Exit codes: `0` → table produced, `1` → runtime error, `2` → usage error. Non-zero → report the error and STOP.

## Output

Three `#` metadata lines, then a TSV table with a header row:

```
# target: main
# trunk: main
# candidates: 8  merged: 7  unmerged: 1  out-of-scope: 0
branch	merge	status	worktree	reason
wt-clean	regular	clean	/repo/.worktrees/wt-clean	-
wt-dirty	regular	dirty	/repo/.worktrees/wt-dirty	uncommitted-changes
```

Only merged branches get a row. The `unmerged` and `out-of-scope` counts cover every branch the script examined and excluded, so an excluded branch is visible rather than absent.

| Column | Values |
|--------|--------|
| `branch` | Branch name |
| `merge` | `regular` or `squash` |
| `status` | `clean`, `dirty`, `checked-out`, `unknown` |
| `worktree` | Absolute path, or `-` when the branch has no worktree |
| `reason` | Why the status is not clean, or `-` when it is |

`clean` is the ONLY status meaning "safe to delete". The other three each block deletion:

| Status | Meaning |
|--------|---------|
| `dirty` | Worktree has uncommitted changes, or untracked files outside `.tmp/` |
| `checked-out` | Branch occupies the main working tree |
| `unknown` | State unverifiable — worktree prunable, missing, at a path other than `<repo>/.worktrees/<branch>`, or its status command failed |

A branch checked out in its OWN `<repo>/.worktrees/<branch>` is not active work — that is the expected layout, and `git-cleanup-merged` removes the worktree before deleting the branch.

## Report

Present the table to the user. State the target branch, plus the `unmerged` and `out-of-scope` counts.
