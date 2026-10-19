# Codex

- Codex ONLY.
- Read BEFORE spawning a subagent (`spawn_agent`), calling `wait_agent`, or running other Codex-only workflows.
- Codex loads this repo's `CLAUDE.md.global` as `~/.codex/AGENTS.md` (symlink to `~/.claude/CLAUDE.md`). Rules marked
  "Claude Code ONLY" there do not apply to Codex.

## Waiting on Subagents

- Every `wait_agent` call follows the `# Codex` section of `CLAUDE.md.global`. That section owns the `timeout_ms` rule.

## Claude-Only Tooling

- NEVER use `/codex-exec`, the Agent tool, or other Claude Code slash-command workflows. They exist only in Claude Code.
- Need another agent to do light work → spawn a Codex subagent. Keep substantive implementation, debugging, and
  high-reasoning work in the current agent.
