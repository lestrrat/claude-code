# Git Operations

## Command Style

NEVER pass `-C` to git. Instead, `cd` into the directory first then run git without `-C`.

## Permission Model

### No confirmation needed (run freely)

Read-only: `git log`, `git diff`, `git status`, `git show`, `git blame`, `git shortlog`, `git describe`, `git tag -l`, `git branch -l`, `git remote -v`, `git stash list`, `git rev-parse`, `git ls-files`, `git cat-file`

Worktree (except remove): `git worktree add`, `git worktree list`, `git worktree lock`, `git worktree unlock`, `git worktree move`, `git worktree prune`, `git worktree repair`

### REQUIRES explicit user request + confirmation every time

`git commit`, `git push`, `git add`, `git worktree remove`, `git --force` (any command)

CRITICAL: Approval is PER-INSTANCE. The user saying "commit and push" once does NOT authorize future commits or pushes. Each occurrence requires its own explicit request. NEVER infer standing permission from prior approvals.

## Commit Messages

- Terse.
- NEVER include Co-Authored-By or any AI/agent attribution.

## Branch Naming

Format: `<category>-<short-description>`

Categories: `fix`, `feat`, `refactor`, `chore`, `docs`, `test`

## Worktrees

ALWAYS use worktrees. NEVER work in the root checkout. Path: `$current_project_dir/.worktrees/<branch-name>`

New branch: `git worktree add $current_project_dir/.worktrees/<branch-name> -b <branch-name>`

Existing branch: `git worktree add $current_project_dir/.worktrees/<branch-name> <branch-name>`

Remove (requires confirmation): `git worktree remove $current_project_dir/.worktrees/<branch-name>`

### Migrating accidental root changes to a worktree

NEVER discard and redo. Use this exact sequence:

1. `cd $current_project_dir; git diff > $current_project_dir/.tmp/migrate.patch`
2. `git worktree add $current_project_dir/.worktrees/<branch-name> -b <branch-name>`
3. `cd $current_project_dir/.worktrees/<branch-name>; git apply $current_project_dir/.tmp/migrate.patch`
4. Verify build/tests pass in the worktree.
5. Only after step 4 succeeds: `cd $current_project_dir; git checkout .`
6. `rm $current_project_dir/.tmp/migrate.patch`

NEVER run step 5 before step 4 succeeds.
