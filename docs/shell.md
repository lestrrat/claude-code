# Shell Rules

Prefer one command per Bash call. `&&`/`||`/`;` chaining and multi-line commands are allowed when commands are tightly coupled, but separate calls are still preferred when earlier results should inform later commands.

## Banned Syntax

Banned syntax:

| Banned | Use instead |
|--------|-------------|
| `\|` (pipe) | Redirect to `.tmp/`, then Read/Grep the file |
| `>>` `<` | Write tool |
| `$(...)` backticks | Separate Bash call, capture result |
| `for` `while` `until` `if/then` `case` | Multiple parallel tool calls |

`>` is allowed ONLY for writing to `.tmp/` files.

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

- Run commands in another directory → `cd <dir>` as its own Bash call, then the command as a separate Bash call. `cd` back afterward.

## Temp Files

- NEVER use `/tmp/`. Use `$PROJECT_DIR/.tmp/`.
- NEVER commit `.tmp/` or its contents to git.
- Periodically clean up `.tmp/`: delete files older than 7 days or when total size exceeds 50 MB (largest files first).
- **Store command output**: when a Bash command produces output you need to process or inspect, redirect to `$PROJECT_DIR/.tmp/` first, then use Read/Grep on the file. See `~/.claude/docs/remote-data.md`.
