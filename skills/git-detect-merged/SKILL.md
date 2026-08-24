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

Four `#` metadata lines, then a TSV table with a header row:

```
# target: main
# trunk: main
# upstream: origin/main  behind: 0  last-fetch: 2026-08-18T19:23:40+0900
# candidates: 8  merged: 7  unmerged: 1  out-of-scope: 0
branch	merge	status	worktree	reason
wt-clean	regular	clean	/repo/.worktrees/wt-clean	-
wt-dirty	regular	dirty	/repo/.worktrees/wt-dirty	uncommitted-changes
```

Only merged branches get a row. The `unmerged` and `out-of-scope` counts cover every branch the script examined and excluded, so an excluded branch is visible rather than absent.

Read the `upstream` line before the table. A target that is behind its upstream does not yet contain the merges it is being asked about, so branches that really did land come back `unmerged`. The script warns on stderr when `behind` is not `0`; treat any non-zero value as making the whole table provisional, and say so when reporting. `last-fetch` is when the repo last contacted the remote at all — a value hours or days old means even `behind: 0` may be measuring against stale data, so fetch first when the counts look wrong.

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

Present the table to the user. State the target branch, plus the `unmerged` and `out-of-scope` counts. When `behind` is not `0`, say that first and state that the table cannot be trusted until the target catches up.
