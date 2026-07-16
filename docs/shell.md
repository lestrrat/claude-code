# Shell Rules

Prefer one command per Bash call. `&&`/`||`/`;` chaining and multi-line commands are allowed when commands are tightly coupled, but separate calls are still preferred when earlier results should inform later commands.

## Syntax Rules

| Syntax | Rule |
|--------|------|
| `\|` (pipe) | OK for cheap local one-shot transforms (e.g. `go list ./... \| wc -l`). Expensive/large output → store to `.tmp/` first (see Output Storage below) |
| `$(...)` backticks | OK for trivial values (e.g. `$(git rev-parse --show-toplevel)`). Intermediate result matters or should inform later commands → separate Bash call |
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

## Killing Processes

Other agents, other sessions, and the user share this machine. Name/pattern kills match their processes too.

| Command | Rule |
|---------|------|
| `pkill`, `killall` | BANNED. No exceptions — a name pattern cannot tell your process from someone else's |
| `kill $(pgrep …)`, `kill $(lsof -t -i:PORT)`, `kill $(jobs -p)` | BANNED. Same problem: the PID set is not yours |
| `kill -9 -1`, `kill 0`, `kill -- -<pgid>` | BANNED. Kills whole sessions/groups |
| `kill <PID>` | ONLY for a PID from a process YOU started in THIS session and whose PID you captured at launch |

Background processes started via the Bash tool → stop with the harness background-task tool (`KillShell`/`TaskStop`), NEVER a shell kill.

Port in use, stale server, hung process you did NOT start:

- Do NOT kill it. It is very likely another agent's.
- Pick a different port, or work around it.
- Genuinely blocked → report to the user with the PID and command line, and let them decide.

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
