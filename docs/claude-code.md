# Claude Code

- Claude Code ONLY.
- Read BEFORE spawning a subagent via the Agent tool, using `/codex-exec`, or running other Claude-only slash-command workflows.

## Codex Delegation

- Use `/codex-exec` for exploratory tasks and other light work: file searches, code reads, simple queries, low-reasoning subtasks.
- NEVER use `/codex-exec` from Codex or other agents.
- NEVER delegate substantive implementation, debugging, or high-reasoning tasks to `/codex-exec`.

## Subagent Model Choice

**Spawning agent picks `model` on every Agent call by task difficulty.** Per-call `model` overrides agent-definition and default models.

| Task | `model` |
|------|---------|
| Mechanical edits, no decisions: renames, reformatting, applying a fully specified change | `haiku` |
| Routine work, small decisions: focused searches, simple fixes with a clear spec | `sonnet` |
| Design, debugging, review, anything unclear | omit → session default |

- Unsure which row fits → omit `model`. A task that looks mechanical but needs judgment (e.g. a rename that changes meaning) belongs in the last row.
- `subagent_type: "fork"` ignores `model` and always runs on the parent model. Need a cheaper model → spawn a fresh subagent with a self-contained prompt instead of a fork.
