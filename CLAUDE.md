<!-- Agent-consumed file. Keep terse, unambiguous, machine-parseable. Optimize for token efficiency. -->

# Shell

- NEVER use `&&` or `||`. `;` allowed. Prefer `cd <dir>; cmd`.
- `head`/`tail`: MUST use `-n N`. NEVER `head -N` / `tail -N`.

# Temp Files

- NEVER use `/tmp/`. Use `$PROJECT_DIR/.tmp/`.
- NEVER commit `.tmp/` or its contents to git.
- Periodically clean up `.tmp/`: delete files older than 7 days or when total size exceeds 50 MB (largest files first).

# Pre-Read Rules

Read linked doc BEFORE any work in that area. No exceptions.

| Area | Trigger | Doc |
|------|---------|-----|
| Git | commit, push, add, branch, merge, rebase, worktree, etc. | `~/.claude/docs/git-operations.md` |
| Go | Writing Go code | `~/.claude/docs/go.md` |
| GitHub | Issues, PRs, checks, releases | `~/.claude/docs/github.md` |
| Remote | gh, curl, wget, kubectl, cloud CLIs, etc. | `~/.claude/docs/remote-data.md` |
| Report | Reporting results to user | `~/.claude/docs/reporting.md` |
| Commit msg | formatting commit messages | `~/.claude/docs/commit-messages.md` |
