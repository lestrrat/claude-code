---
name: checkpoint-summary
description: Create a resumable checkpoint file for another agent to continue work later. Use when user asks to save progress, create handoff notes, checkpoint current state, or leave a resume file for a future agent/session.
---

# Checkpoint Summary

Create a checkpoint file that another agent can read to resume work without reconstructing session history.

## Workflow

1. Identify brief topic for current session. Keep it short enough for filename slug.
2. Resolve skill directory. Bundled script lives in `scripts/` next to this `SKILL.md`.
3. `cd` to skill directory if needed, then run `./scripts/create-checkpoint.py "<topic>"`.
4. Read script output to get created checkpoint path.
5. Fill checkpoint file with current state before ending turn.
6. Tell user exact checkpoint path in final report.

## File Rules

- Store checkpoints under project `.tmp/checkpoints/`.
- Filename MUST include:
  - timestamp
  - unique id
  - brief topic slug
- Do not overwrite prior checkpoints.
- Prefer one checkpoint per meaningful handoff point.

## Checkpoint Contents

Write concise, high-signal content. Another agent should understand:

- task goal
- current status
- decisions already made
- files changed or inspected
- commands/tests already run and key outcomes
- blockers, risks, or assumptions
- exact next steps

## Template Guidance

Populate these sections:

- `Topic`
- `Goal`
- `Current State`
- `Decisions`
- `Files`
- `Commands`
- `Open Questions`
- `Next Steps`

## Rules

- Prefer facts over narrative.
- Include enough context to resume without rereading full chat.
- Do not dump large logs. Summarize outcomes.
- Use repo-relative file paths in file lists when practical.
- If no code changed yet, say so explicitly.
