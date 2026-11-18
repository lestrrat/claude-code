# Claude Code

- Claude Code ONLY.
- Read BEFORE spawning a subagent via the Agent tool, messaging a subagent, reporting a subagent's status, using
  `/codex-exec`, or running other Claude-only slash-command workflows.

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

## Tracking Subagents

**Orchestrator owns every subagent it spawned until its deliverable is checked.** Status claims follow CLAUDE.md.global "Progress".

- Every delegation names the exact deliverable and where it lands: file path, branch, PR, or hand-back report.
- Valid status checks: `ListAgents` state, the deliverable's existence or mtime, git/PR state, a hand-back received.
- Run `ListAgents` before every status answer to the user and before every SendMessage to a subagent.
- Notification saying an agent stopped, "waiting on background work", or "has not reported yet" → its turn ended. It is
  NOT working and NOT a result. Wait only while `ListAgents` shows the background work it waits on still live.
  Otherwise it stopped without delivering → tell user, then resume it with a concrete ask or respawn it.
- SendMessage result "Resuming agent X" → X had stopped. Report that and correct any earlier "still running" claim.
- NEVER repeat "still running" or "Nothing needed from you" about an agent without a fresh check that turn.
- Check every instruction against the user's stated physical or product intent before forwarding it to an agent.
  Doubt → ask the user first.
