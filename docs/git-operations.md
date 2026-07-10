# Git Operations

## Commit Messages

- Single line only. No body, no blank line + description.
- Max ~50 characters. Lowercase unless proper noun.
- No Co-Authored-By, AI/agent attribution, or any mention of coding agents.
- No trailing period.
- Imperative mood: "fix X", "add Y", "update Z" — not "fixed", "adds", "updated".

## PR Messages

- Title: same rules as commit messages above.
- Body: terse bullet points only. No prose, no filler, no "this PR does X".
- 1–3 bullets stating what changed. Each bullet ≤ 1 line.
- No "Test plan" section. Ever.
- No AI/agent attribution lines.
- Omit sections with no content. Don't add empty headings.

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

Carries staged + unstaged + untracked files. Does NOT carry ignored files (add `-a` to step 2 only if you truly need them) or work already committed on the wrong branch. It also skips nested worktree/repo directories, so `.worktrees/` stays in the root untouched. NEVER run `git clean -fd` in the root to "tidy up" the leftover `?? .worktrees/` — it would destroy every worktree under it. (Adding `.worktrees/` to `.gitignore` would hide that leftover, but that is a separate change.)

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
