---
name: git-detect-merged
description: Detect whether local branches/worktrees have been merged into a target branch (default: main), including squash merges. Args: [target-branch]
---

# Git Detect Merged

Detect whether local branches and worktrees have their changes already merged into a target branch. Handles both regular merges and squash merges.

## Args

`/git-detect-merged [target-branch]`

- `target-branch` — branch to check against. Default: `main`.

Refer to the target branch as `$TARGET` below.

## Step A: Regular merge detection

Run `git branch --merged $TARGET`. Any branch listed here (except `$TARGET` itself) is merged via a regular or fast-forward merge.

## Step B: Squash merge detection

Branches NOT listed by `--merged` may still have been squash-merged. For each remaining local branch, use a two-phase check:

### Phase 1: Single-commit cherry check

Run `git cherry -v $TARGET <branch>`.

- All `-` or no output → **squash-merged**. Mark as candidate.
- Any `+` → continue to Phase 2.

### Phase 2: Combined patch-id check (multi-commit squash merges)

`git cherry` compares patch-ids of individual commits. When a multi-commit branch is squash-merged into a single commit, the combined diff has a different patch-id than any individual commit, so `git cherry` reports all `+` even though the branch is fully merged. Detect this by computing the combined patch-id:

Each step below is a separate Bash call. `git patch-id` only reads stdin, so `|` is permitted here as an exception.

1. Find the merge base: `git merge-base $TARGET <branch>` → save output as `base`.
2. Compute the combined patch-id of the branch: `git diff $base..<branch> | git patch-id --stable` → extract the first field as `branch_pid`.
3. For each commit hash from `git log --format=%H $base..$TARGET`: run `git diff <hash>^..<hash> | git patch-id --stable` → extract the first field.
4. If `branch_pid` matches any commit's patch-id → **squash-merged**. Mark as candidate.
5. If no match → **not merged**. Skip it.

## Detecting active work

A branch or worktree is considered "actively being worked on" if any of these are true:

- The worktree has uncommitted changes (staged or unstaged): `cd` to the worktree path first, then run `git status --porcelain` — any output means dirty.
- The worktree has untracked files outside `.tmp/`: visible in `--porcelain` output (lines starting with `??`). Ignore untracked `.tmp/` content.
- The branch is currently checked out in any worktree (including the main working tree).

## Output

Report each branch with:

- Branch name
- Target branch checked against
- Merge type: `regular` or `squash`
- Active work status: `clean`, `dirty`, or `checked-out`
- Associated worktree path (if any)
