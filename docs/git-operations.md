# Git Operations

## Command Style

NEVER use `git -C`. Always `cd <dir>; git ...`.

## Permissions

Free (no confirmation): `log`, `diff`, `status`, `show`, `blame`, `shortlog`, `describe`, `tag -l`, `branch -l`, `remote -v`, `stash list`, `rev-parse`, `ls-files`, `cat-file`, `worktree add/list/lock/unlock/move/prune/repair`

REQUIRES explicit user request + confirmation EVERY time: `commit`, `push`, `add`, `worktree remove`, `--force`

Approval is PER-INSTANCE. NEVER infer standing permission.

## Commit Messages

Read `~/.claude/docs/commit-messages.md` first.

## Branch Naming

`<category>-<short-description>` — categories: `fix`, `feat`, `refactor`, `chore`, `docs`, `test`

## Worktrees

ALWAYS use worktrees. NEVER work in root checkout.

Path: `$PWD/.worktrees/<branch>`

| Action | Command |
|--------|---------|
| New branch | `git worktree add $PWD/.worktrees/<branch> -b <branch>` |
| Existing branch | `git worktree add $PWD/.worktrees/<branch> <branch>` |
| Remove (confirm) | `git worktree remove $PWD/.worktrees/<branch>` |

### Migrate Root Changes to Worktree

NEVER discard+redo. Exact sequence:

1. `cd $PROJECT; git diff > $PROJECT/.tmp/migrate.patch`
2. `git worktree add $PROJECT/.worktrees/<branch> -b <branch>`
3. `cd $PROJECT/.worktrees/<branch>; git apply $PROJECT/.tmp/migrate.patch`
4. Verify build/tests pass in worktree
5. ONLY after 4 succeeds: `cd $PROJECT; git checkout .`
6. `rm $PROJECT/.tmp/migrate.patch`

## Merged Branch Detection

ALWAYS verify before worktree/branch deletion. Run steps in order; stop when safe-to-delete is determined.

A branch is **safe to delete** only when ALL of:
1. Its worktree (if any) has no uncommitted or untracked changes
2. Its content is fully contained in `<target>` (typically `main`)

### Step 1: Enumerate

`cd $PROJECT; git worktree list --porcelain`

Parse: `worktree <path>` + `branch refs/heads/<name>` pairs. Skip `detached` entries.

### Step 2: Cleanliness Gate

Per worktree from Step 1:

`cd <worktree-path>; git status --porcelain`

Non-empty (staged, unstaged, or untracked) → **not safe to delete; stop.**

No worktree for branch → skip to Step 3.

### Step 3: Ancestry

`cd $PROJECT; git merge-base --is-ancestor <branch> <target>`

Exit 0 → **safe to delete.** Exit 1 → continue to Step 4.

Fetch first if remote may be ahead: `git fetch origin main`

### Step 4: Cherry (Squash Merge)

Ancestry misses squash merges. Compare patch content:

`cd $PROJECT; git cherry -v <target> <branch>`

All `-` or no output → **safe to delete.** Any `+` → **not safe to delete.**

### Edge Cases

- No worktree for branch → skip Step 2
- Remote branch deleted ≠ safe to delete; check local content
- Rebased/amended → `git cherry` uses `patch-id`; handles it. If ambiguous: `git log --oneline <target>..<branch>`
- Merged into one target ≠ merged into all; always specify target
