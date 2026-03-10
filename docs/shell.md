# Shell Rules

**One command per Bash call. No compound commands. No exceptions.**

## Before EVERY Bash Call — Verify

- [ ] Contains exactly ONE command (no `;` `&&` `||`)
- [ ] No pipes (`|`) — redirect to `.tmp/` instead, then Read/Grep
- [ ] No `cd` combined with other commands — `cd` must be its own Bash call
- [ ] Not using `cat`/`head`/`tail`/`grep`/`find`/`sed`/`awk` — use dedicated tools

If ANY check fails, split into separate Bash calls or use the correct dedicated tool.

## Banned Syntax

FORBIDDEN in ALL Bash calls. Violations break the permission allowlist.

| Banned | Examples | Use instead |
|--------|----------|-------------|
| `&&` `\|\|` | `cd dir && make` | Separate sequential Bash calls |
| `\|` (pipe) | `cmd \| grep x` | Redirect to `.tmp/`, then Read/Grep the file |
| `>>` `<` | `cmd >> file` | Write tool |
| `$(...)` backticks | `echo $(date)` | Separate Bash call, capture result |
| `;` with `cd` | `cd dir; make` | Separate sequential Bash calls |
| `for` `while` `until` `if/then` `case` | loops/conditionals | Multiple parallel tool calls |

`>` is allowed ONLY for writing to `.tmp/` files. `;` is allowed ONLY between non-`cd` commands.

## Dedicated Tools Over Shell

ALWAYS use dedicated tools. Bash is ONLY for commands with no tool equivalent.

| Task | Use | NOT |
|------|-----|-----|
| Read files | `Read` tool | `cat`/`head`/`tail` |
| Search content | `Grep` tool | `grep`/`rg` |
| Find files | `Glob` tool | `find`/`ls` |
| Edit files | `Edit` tool | `sed`/`awk` |
| Write files | `Write` tool | `echo`/`cat` with redirection |

## Other

- `head`/`tail`: MUST use `-n N`. NEVER `head -N` / `tail -N`.
- Run commands in another directory → `cd <dir>` as its own Bash call, then the command as a separate Bash call. `cd` back afterward.

## Temp Files

- NEVER use `/tmp/`. Use `$PROJECT_DIR/.tmp/`.
- NEVER commit `.tmp/` or its contents to git.
- Periodically clean up `.tmp/`: delete files older than 7 days or when total size exceeds 50 MB (largest files first).
- **Store command output**: when a Bash command produces output you need to process or inspect, redirect to `$PROJECT_DIR/.tmp/` first, then use Read/Grep on the file. See `~/.claude/docs/remote-data.md`.
