# Git Operations

## Permissions

Free (no confirmation): `log`, `diff`, `status`, `show`, `stash`, `cherry`, `fetch`, `ls-tree`, `worktree add/list`

REQUIRES explicit user request + confirmation EVERY time: `commit`, `push`, `add`, `worktree remove`, `--force`

Approval is PER-INSTANCE. NEVER infer standing permission.

## Commit & PR Messages

Read `~/.claude/docs/git-messages.md` first.

## Branch Naming

`<category>-<short-description>` — categories: `fix`, `feat`, `refactor`, `chore`, `docs`, `test`

## Worktrees

ALWAYS use worktrees. NEVER work in root checkout.

Path: `$PROJECT/.worktrees/<branch>`

| Action | Command |
|--------|---------|
| New branch | `git worktree add $PROJECT/.worktrees/<branch> -b <branch>` |
| Existing branch | `git worktree add $PROJECT/.worktrees/<branch> <branch>` |
| Remove (confirm) | `git worktree remove $PROJECT/.worktrees/<branch>` |

Worktree directory name MUST match its checked-out branch. NEVER `git checkout <other-branch>` inside a worktree — the branch name is fixed to the worktree name for its entire lifetime.

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

## PR Comments

Terse, direct. No filler, no preamble, no "Great catch", no "Thanks for the review".

- Lead with what changed or why. Skip context the reviewer already has.
- One thought per comment. No bullet lists unless comparing alternatives.
- Use code references (`file:line`, backticks) over prose descriptions.
- OK to be a fragment: "done", "fixed in abc1234", "intentional — avoids double-lock".
- When dismissing a review item, say why in ≤1 sentence.

## Push Guard

Before pushing to a branch that has an associated PR, verify the PR is still open:

`gh pr view <branch> --json state --jq .state`

If state is `MERGED` or `CLOSED`, STOP. Do NOT push. Report to user that the PR is already merged/closed.

## Merged Branch Detection

ALWAYS verify before worktree/branch deletion. Use the `git-detect-merged` skill to check, then the `git-cleanup-merged` skill to delete.
