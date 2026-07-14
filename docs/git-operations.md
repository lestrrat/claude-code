# Git Operations

## Commit & PR Messages

Message rules live in `~/.claude/scripts/git-lint-message`, NOT in this doc. MANDATORY workflow for every `git commit`, `gh pr create`, `gh pr edit`:

1. `~/.claude/scripts/git-lint-message rules <commit|pr-title|pr-body>` → draft to that spec.
2. Write draft to `.tmp/` (`.tmp/commit-msg.txt`, `.tmp/pr-title.txt`, `.tmp/pr-body.md`).
3. `~/.claude/scripts/git-lint-message <commit|pr-title|pr-body> <file>` → fix every ERROR, re-run until exit 0.
4. Each WARN: fix, or confirm exemption genuinely applies (e.g. leading capital IS proper noun).
5. Use linted file verbatim: `git commit -F .tmp/commit-msg.txt`, `gh pr create --title "$(cat .tmp/pr-title.txt)" --body-file .tmp/pr-body.md`.

## Branch Naming

`<category>-<short-description>` — categories: `fix`, `feat`, `refactor`, `chore`, `docs`, `test`

## Worktrees

Use a worktree for any task that edits tracked files or mutates a branch — NEVER make such edits in the root checkout. Read-only work (analysis, exploration, answering questions, running queries) may run anywhere; do not build a worktree just to inspect.

Path: `$PROJECT/.worktrees/<branch>`

| Action | Command |
|--------|---------|
| New branch | `git worktree add $PROJECT/.worktrees/<branch> -b <branch>` |
| Existing branch | `git worktree add $PROJECT/.worktrees/<branch> <branch>` |
| Remove | `git worktree remove $PROJECT/.worktrees/<branch>` |

Worktree directory name MUST match its checked-out branch. NEVER `git checkout <other-branch>` inside a worktree — the branch name is fixed to the worktree name for its entire lifetime.

### Migrate Root Changes to Worktree

NEVER discard+redo. `git stash -u` carries staged, unstaged, AND untracked changes together; a bare `git diff` patch captures only unstaged tracked edits and leaves staged and untracked work behind in the root. Exact sequence (each command is a separate Bash call):

1. `cd "$PROJECT"`
2. `git stash push -u -m migrate` — moves staged, unstaged, and untracked *files* into the stash. It does NOT descend into nested worktree/repo directories: `git stash push -u` prints `Ignoring path .worktrees/<name>/` and leaves `.worktrees/` in place. So the root is NOT clean afterward — `git status` still shows `?? .worktrees/`. That leftover is EXPECTED; do NOT delete or clean it.
3. `git worktree add "$PROJECT/.worktrees/<branch>" -b <branch>`
4. `cd "$PROJECT/.worktrees/<branch>"`
5. `git stash apply` — restores every carried change here (all as unstaged; re-`git add` what you had staged)
6. Verify build/tests pass in worktree
7. ONLY after 6 succeeds: `git stash drop`

Carries staged + unstaged + untracked files. Does NOT carry ignored files (add `-a` to step 2 only if you truly need them) or work already committed on the wrong branch. It also skips nested worktree/repo directories, so `.worktrees/` stays in the root untouched. Leave the leftover `?? .worktrees/` alone — do NOT try to "tidy up" the root. `git clean -fd` SKIPS nested worktrees (prints `Skipping repository .worktrees/<name>`) and will NOT remove them, but `git clean -ffd` (double force) WILL delete every worktree under `.worktrees/` — NEVER run it in the root during this procedure. (Adding `.worktrees/` to `.gitignore` would hide that leftover, but that is a separate change.)

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
