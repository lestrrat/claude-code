# Git Operations

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

NEVER discard+redo. Exact sequence (each command is a separate Bash call):

1. `cd $PROJECT`
2. `git diff > $PROJECT/.tmp/migrate.patch`
3. `git worktree add $PROJECT/.worktrees/<branch> -b <branch>`
4. `cd $PROJECT/.worktrees/<branch>`
5. `git apply $PROJECT/.tmp/migrate.patch`
6. Verify build/tests pass in worktree
7. ONLY after 6 succeeds: `cd $PROJECT`
8. `git checkout .`
9. `rm $PROJECT/.tmp/migrate.patch`

## Merged Branch Detection

ALWAYS verify before worktree/branch deletion. Use the `git-detect-merged` skill for the canonical procedure.
