# Shell Rules

Prefer one command per Bash call. `&&`/`||`/`;` chaining and multi-line commands are allowed when commands are tightly coupled, but separate calls are still preferred when earlier results should inform later commands.

## Syntax Rules

| Syntax | Rule |
|--------|------|
| `\|` (pipe) | OK for cheap local one-shot transforms (e.g. `go list ./... \| wc -l`). Expensive/remote output (gh, curl, test runs) → redirect to `.tmp/` first, then Read/Grep the file |
| `$(...)` backticks | OK for trivial values (e.g. `$(git rev-parse --show-toplevel)`). Intermediate result matters or should inform later commands → separate Bash call |
| `>` `>>` | ONLY for writing to `.tmp/` files. Creating/editing real files → Write/Edit tool |
| `<` | Avoid. Use Write tool or file arguments instead |
| `for` `while` `until` `if/then` `case` | Banned. Use multiple parallel tool calls — per-item failures stay visible |

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
- **Store expensive/remote output**: when output is costly to regenerate (gh, curl, kubectl, full test runs) or needs repeated inspection, redirect to `$PROJECT_DIR/.tmp/` first, then use Read/Grep on the file. See `~/.claude/docs/remote-data.md`.
