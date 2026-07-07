# Shell Rules

Prefer one command per Bash call. `&&`/`||`/`;` chaining and multi-line commands are allowed when commands are tightly coupled, but separate calls are still preferred when earlier results should inform later commands.

## Syntax Rules

| Syntax | Rule |
|--------|------|
| `\|` (pipe) | OK for cheap local one-shot transforms (e.g. `go list ./... \| wc -l`). Expensive/large output → store to `.tmp/` first (see Output Storage below) |
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

## Working Directory

- Prefer dir flags or absolute paths over `cd`: `git -C <dir>`, `go -C <dir>`, `make -C <dir>`, absolute file arguments.
- No flag/absolute-path option → `cd <dir>` as its own Bash call, then the command as a separate call. `cd` back afterward.

## Output Storage

Store output to `$PROJECT_DIR/.tmp/<tool>-<slug>.<ext>` first, then Read/Grep the file, when output is any of:

- **Expensive to regenerate** — network/remote calls (`gh`, `curl`, `wget`, `gcloud`/`aws`/`az`, `kubectl`/`helm`, `docker` logs/inspect, `ssh`), full build/test/lint runs.
- **Potentially large** — API/JSON responses, logs, `git log`/`git diff` against remote refs. Large piped output gets silently truncated; a stored file re-reads without re-fetching.
- **Needed more than once** — repeated inspection or multi-step processing.

Small single-value output (`git rev-parse HEAD`, `gh pr view --json state --jq .state`, `wc -l` counts) → use directly, no file.

Example: `gh api /repos/owner/repo/issues > $PROJECT_DIR/.tmp/gh-issues.json`, then Read/Grep/jq the file.

## Temp Files

- NEVER use `/tmp/`. Use `$PROJECT_DIR/.tmp/` — create if missing; applies outside worktrees too.
- NEVER commit `.tmp/` or its contents to git.
- Clean up when noticed: delete `.tmp/` files older than 7 days, or largest-first when total size exceeds 50 MB.
